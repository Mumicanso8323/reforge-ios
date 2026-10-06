import RFContent
import RFKernel
import RFRules
import RFWorld

/// 出来事(CORE-10・16)。物語を運ぶ仕組みの心臓。
///
/// - 引き金: DomainEvent の hook(工業の行為: 初めて作った・建てた・配属した・解体した・観測した…)と、世界の状態
///   (Condition: 前の出来事・追跡カウンタ・来歴・初めて・在庫・人・範囲)。trigger.on が無い出来事は夜明けと毎時("hour")。
///   日数では引かない(検証で警告)。
/// - 効果(EffectApplier)が世界を変える: 配属の上書き・範囲の付け外しと半分化・地形・人の合流と離脱・解禁・部品・
///   過去の記録への印・事実を知る・章と結末。場面(3 行まで)と一言は添え物。
/// - 決断(PendingDecision。blocking のものだけ時計を止める)・予約・クールダウン・1 日 1 回・優先度・
///   追跡カウンタ(TrackerDef)・目標の達成と失敗・章・結末・場面の時間での進行・範囲の効果の整理。
/// - 確率は物語の乱数の流れ(.narrative)だけ。同じ seed と操作の列なら同じ出来事の列(TEST-S5)。
///
/// 書いてよい切れ端: narrative・auras(と EffectApplier 経由の各所)。受けるコマンド: .narrative(...)。
public struct NarrativeSystem: SimSystem {
    public let name = "narrative"
    public init() {}

    /// 場面の 1 行を出しておくゲーム秒(押さなくても次の行へ流れる。昼なら実時間で約 7 秒)。
    public static let sceneLineSeconds: Int64 = 1200

    // MARK: - コマンド

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
            Self.advanceScene(&ctx)
            return .done
        case .fireFromEffect(let id, let cause):
            guard let def = ctx.content.events[id] else { return .rejected(Rejection("reason.narrative.no_event")) }
            if Self.mayFire(id, def, ctx.world) { fire(id, def, &ctx, trigger: cause) }
            return .done
        case .openSheet, .grant, .placeAnswer, .setRosterPick, .confirmRoster:
            return SheetActions.handle(c, &ctx) ?? .notMine
        }
    }

    // MARK: - ステップ

    public func step(_ ctx: inout StepContext) {
        runScheduled(&ctx)
        Trackers.step(&ctx)
        Auras.maintain(&ctx)
        if Self.crossedHour(ctx.world.clock.now) {
            Trackers.refreshLedgerCounts(&ctx)
            check(hook: "hour", trigger: nil, &ctx)
            checkGoals(&ctx)
        }
        sceneTick(&ctx)
    }

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        if case .dawn = event { Trackers.dawn(&ctx) }
        if event.record != nil { Trackers.refreshLedgerCounts(&ctx) }
        SheetActions.refreshDeclarations(hook: event.hook, &ctx)
        check(hook: event.hook, trigger: event.record, &ctx)
        checkGoals(&ctx)
    }

    /// このステップで毎時の区切りを越えたか(ステップの終わりの時刻で判定)。
    static func crossedHour(_ now: GameTime) -> Bool { now.seconds % 3600 < SimStep.gameSeconds }

    // MARK: - 発火

    /// hook で調べる出来事を、優先度の大きい順・ID 順に評価して起こす。
    func check(hook: String, trigger: ProvenanceID?, _ ctx: inout StepContext) {
        let defs = ctx.content.events.values.filter { def in
            if let on = def.trigger.on { return on.contains(hook) }
            return hook == "dawn" || hook == "hour"
        }.sorted { ($0.priority ?? 0, $1.id) > ($1.priority ?? 0, $0.id) }
        for def in defs {
            guard Self.mayFire(def.id, def, ctx.world) else { continue }
            guard ConditionEvaluator.evaluate(def.trigger.when, &ctx, trigger: trigger) else { continue }
            fire(def.id, def, &ctx, trigger: trigger)
        }
    }

    /// 繰り返しの規則と、同じ出来事の決断待ちが無いかを見る。
    static func mayFire(_ id: EventID, _ def: EventDef, _ w: WorldState) -> Bool {
        if w.narrative.pending.contains(where: { $0.event == id }) { return false }
        guard let f = w.narrative.fired[id] else { return true }
        switch def.repeats ?? .once {
        case .once: return false
        case .cooldown(let h): return w.clock.now - f.lastAt >= .hours(h)
        case .oncePerDay: return f.lastDay != w.clock.day
        case .always: return true
        }
    }

    func fire(_ id: EventID, _ def: EventDef, _ ctx: inout StepContext, trigger: ProvenanceID?) {
        let place = trigger.flatMap { ctx.world.ledger.record($0)?.place }
        let rec = ctx.record(.chose, .event(id), place: place, inputs: trigger.map { [$0] } ?? [], tags: Set(def.tags ?? []))
        let prev = ctx.world.narrative.fired[id]?.count ?? 0
        ctx.world.narrative.fired[id] = FiredRecord(count: prev + 1, lastAt: ctx.world.clock.now, lastRecord: rec,
                                                    lastDay: ctx.world.clock.day)
        ctx.emit(.eventFired(event: id, record: rec))
        EffectApplier.apply(def.effects, &ctx, cause: rec)
        if let scene = def.scene { EffectApplier.apply([.startScene(scene: scene)], &ctx, cause: rec) }
        if let choices = def.choices, !choices.isEmpty {
            let open = choices.filter { c in
                c.when.map { ConditionEvaluator.evaluatePure($0, world: ctx.world, content: ctx.content, trigger: rec) ?? false } ?? true
            }.map(\.id)
            if !open.isEmpty {
                let did = ctx.world.newEntityID()
                ctx.world.narrative.pending.append(PendingDecision(id: did, event: id, choices: open, blocking: def.blocking ?? false,
                                                                   since: ctx.world.clock.now, origin: rec))
                if def.blocking ?? false { ctx.dropNoahSteer() }
                ctx.emit(.decisionOpened(decision: did, event: id))
            }
        }
        ctx.changes.mark(.narrative)
    }

    /// 予約の時刻が来た出来事を起こす(trigger.when が成り立たなければ起こさずに捨てる)。
    func runScheduled(_ ctx: inout StepContext) {
        let now = ctx.world.clock.now
        guard ctx.world.narrative.scheduled.contains(where: { $0.at <= now }) else { return }
        let due = ctx.world.narrative.scheduled.enumerated().filter { $0.element.at <= now }
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        ctx.world.narrative.scheduled.removeAll { $0.at <= now }
        for s in due {
            guard let def = ctx.content.events[s.event] else {
                ctx.warnings.append("予約した出来事の定義が無い: \(s.event)")
                continue
            }
            guard Self.mayFire(s.event, def, ctx.world),
                  ConditionEvaluator.evaluate(def.trigger.when, &ctx, trigger: s.cause) else { continue }
            fire(s.event, def, &ctx, trigger: s.cause)
        }
        ctx.changes.mark(.narrative)
    }

    // MARK: - 目標・結末

    /// 進行中の目標の達成・失敗と、結末の条件を見る(乱数を使わない評価)。
    func checkGoals(_ ctx: inout StepContext) {
        for (id, st) in ctx.world.narrative.objectives.sorted(by: { $0.key < $1.key }) where st == .active {
            guard let def = ctx.content.objectives[id] else { continue }
            let w = ctx.world
            if ConditionEvaluator.evaluatePure(def.completeWhen, world: w, content: ctx.content) == true {
                ctx.world.narrative.objectives[id] = .done
                // 達成の来歴(後で「あの目標を果たしたこと」を指せる)
                let rec = ctx.record(.achieved, .none, detail: ["objective": .string(id.rawValue), "status": .string("done")])
                ctx.emit(.objectiveChanged(objective: id, status: .done))
                EffectApplier.apply(def.effects ?? [], &ctx, cause: rec)
                ctx.changes.mark(.narrative)
            } else if let f = def.failWhen, ConditionEvaluator.evaluatePure(f, world: w, content: ctx.content) == true {
                ctx.world.narrative.objectives[id] = .failed
                ctx.emit(.objectiveChanged(objective: id, status: .failed))
                ctx.changes.mark(.narrative)
            }
        }
        guard ctx.world.narrative.ending == nil else { return }
        for (id, def) in ctx.content.endings.sorted(by: { $0.key < $1.key }) {
            guard ConditionEvaluator.evaluatePure(def.when, world: ctx.world, content: ctx.content) == true else { continue }
            let rec = ctx.record(.achieved, .none, detail: ["ending": .string(id.rawValue)])
            EffectApplier.apply(def.effects ?? [], &ctx, cause: rec)
            if let s = def.scene { EffectApplier.apply([.startScene(scene: s)], &ctx, cause: rec) }
            EffectApplier.apply([.ending(id: id)], &ctx, cause: rec)
            return
        }
    }

    // MARK: - 場面

    func sceneTick(_ ctx: inout StepContext) {
        guard let s = ctx.world.narrative.scene else { return }
        guard ctx.content.scenes[s.scene]?.style != .prologue,
              ctx.content.scenes[s.scene]?.style != .stage
        else { return }
        let since = s.lineSince ?? ctx.world.clock.now
        if ctx.world.clock.now - since >= GameDuration(seconds: Self.sceneLineSeconds) { Self.advanceScene(&ctx) }
    }

    /// 次の行へ(条件が成り立たない行は飛ばす)。最後の行の次で場面は終わる。
    static func advanceScene(_ ctx: inout StepContext) {
        guard var s = ctx.world.narrative.scene else { return }
        guard let definition = ctx.content.scenes[s.scene] else {
            ctx.world.narrative.scene = nil
            ctx.changes.mark(.narrative)
            return
        }
        let lines = definition.lines
        s.line += 1
        while s.line < lines.count, let c = lines[s.line].when,
              ConditionEvaluator.evaluatePure(c, world: ctx.world, content: ctx.content, trigger: s.origin) != true {
            s.line += 1
        }
        s.lineSince = ctx.world.clock.now
        if s.line < lines.count {
            ctx.world.narrative.scene = s
            for fact in lines[s.line].learns ?? [] { ctx.learn(fact, via: s.origin) }
        } else {
            ctx.world.narrative.scene = nil
            EffectApplier.apply(definition.onEnd ?? [], &ctx, cause: s.origin)
            if let next = definition.then {
                EffectApplier.apply([.startScene(scene: next)], &ctx, cause: s.origin)
            }
        }
        ctx.changes.mark(.narrative)
    }
}
