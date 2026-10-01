import RFContent
import RFKernel
import RFRules
import RFWorld

/// 出来事(CORE-10・16)。DomainEvent の hook と世界の状態(Condition)で EventDef を発火し、効果
/// (EffectApplier)で世界を変える。決断(PendingDecision。blocking のものだけ時計を止める)、場面(3 行まで)、
/// 予約、追跡カウンタ(TrackerDef)、目標・章・結末、範囲の効果の付け外し。確率は物語の乱数の流れだけ。
///
/// 書いてよい切れ端: narrative(と EffectApplier 経由の各所)。乱数の流れ: .narrative。
/// 受けるコマンド: .narrative(.decide / .advanceScene)。
///
/// 骨組みとして最小の動きを入れてある(hook で引く・条件・効果・一度きり・選択肢・決める)。
/// 予約・追跡カウンタ・目標の達成・クールダウン・優先度・場面の進行は担当が入れる。
public struct NarrativeSystem: SimSystem {
    public let name = "narrative"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .narrative(let c) = command else { return .notMine }
        switch c {
        case .decide(let id, let choice):
            guard let i = ctx.world.narrative.pending.firstIndex(where: { $0.id == id }) else {
                return .rejected(Rejection("reason.narrative.no_decision"))
            }
            let d = ctx.world.narrative.pending[i]
            guard d.choices.contains(choice), let def = ctx.content.events[d.event]?.choices?.first(where: { $0.id == choice })
            else { return .rejected(Rejection("reason.narrative.bad_choice")) }
            ctx.world.narrative.pending.remove(at: i)
            let rec = ctx.record(.chose, .choice(d.event, choice), actor: .noah, inputs: d.origin.map { [$0] } ?? [],
                                 tags: Set(def.tags ?? []))
            ctx.emit(.decided(decision: id, choice: choice, record: rec))
            EffectApplier.apply(def.effects, &ctx, cause: rec)
            ctx.changes.mark(.narrative)
            return .done
        case .advanceScene:
            guard var s = ctx.world.narrative.scene else { return .done }
            s.line += 1
            let count = ctx.content.scenes[s.scene]?.lines.count ?? 0
            ctx.world.narrative.scene = s.line < count ? s : nil
            ctx.changes.mark(.narrative)
            return .done
        }
    }

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        let hook = event.hook
        // ID 順に調べる(決定的)。優先度・クールダウンは担当が足す。
        for (id, def) in ctx.content.events.sorted(by: { $0.key < $1.key }) {
            guard def.trigger.on?.contains(hook) ?? (hook == "dawn") else { continue }
            if (def.repeats ?? .once) == .once, ctx.world.narrative.fired[id] != nil { continue }
            guard ConditionEvaluator.evaluate(def.trigger.when, &ctx, trigger: event.record) else { continue }
            fire(id, def, &ctx, trigger: event.record)
        }
    }

    func fire(_ id: EventID, _ def: EventDef, _ ctx: inout StepContext, trigger: ProvenanceID?) {
        let rec = ctx.record(.chose, .event(id), inputs: trigger.map { [$0] } ?? [], tags: Set(def.tags ?? []))
        let prev = ctx.world.narrative.fired[id]?.count ?? 0
        ctx.world.narrative.fired[id] = FiredRecord(count: prev + 1, lastAt: ctx.world.clock.now, lastRecord: rec)
        ctx.emit(.eventFired(event: id, record: rec))
        EffectApplier.apply(def.effects, &ctx, cause: rec)
        if let scene = def.scene { EffectApplier.apply([.startScene(scene: scene)], &ctx, cause: rec) }
        if let choices = def.choices, !choices.isEmpty {
            let open = choices.filter { c in
                c.when.map { ConditionEvaluator.evaluatePure($0, world: ctx.world, content: ctx.content, trigger: rec) ?? false } ?? true
            }.map(\.id)
            let did = ctx.world.newEntityID()
            ctx.world.narrative.pending.append(PendingDecision(id: did, event: id, choices: open, blocking: def.blocking ?? false,
                                                               since: ctx.world.clock.now, origin: rec))
            ctx.emit(.decisionOpened(decision: did, event: id))
        }
        ctx.changes.mark(.narrative)
    }
}
