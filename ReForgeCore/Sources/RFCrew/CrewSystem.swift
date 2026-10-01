import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 人(CORE-09・17)。ノアと仲間は地図上の実体: 経路(RFMap)で歩き、配属(運搬・モジュール・見張り・建造・採取)を
/// 自分で実行し、夜は焚き火で話す。関係ランク、思想の傾きによる賛否(来歴の印 × 思想の重み)、記憶、
/// 配属の上書き(出来事・範囲の効果 drawTowardSource)、合流・離脱・死、視界と地図の既知(knowledge.mapKnown)。
///
/// 書いてよい切れ端: people・knowledge.mapKnown(と発見)。乱数の流れ: .crew(いまは引かない)。受けるコマンド: .crew(...)。
///
/// 1 ステップ: 関係のランクを直す → 歩く(1 実秒 4 マス)→ 視界で既知を増やす(霧が晴れたら経路を引き直す)
/// → 配属を実行する(行き先を決めて歩き出す・着いたら働く)。
/// 他のシステムが読むもの: `PersonState.position / motion / activity / workSpeed / haulLeg`、
/// `PeopleState.workers(at:) / workSpeedPermille(at:) / guards / haulers(of:)`、出来事 arrived・assigned・opinion。
public struct CrewSystem: SimSystem {
    public let name = "crew"
    public init() {}

    // MARK: コマンド

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .crew(let c) = command else { return .notMine }
        switch c {
        case .walk(let to): return walk(to: to, &ctx)
        case .stop: return stop(&ctx)
        case .assign(let p, let a): return assign(p, a, &ctx)
        case .talk(let p): return Relations.talk(p, &ctx)
        case .equip(let p, let slot, let stock): return equip(p, slot: slot, stock: stock, &ctx)
        case .meetFromEffect(let p, let at, let cause): return Membership.meet(p, at: at, cause: cause, &ctx)
        case .joinFromEffect(let p, let cause): return Membership.join(p, cause: cause, &ctx)
        case .leaveFromEffect(let p, let cause): return Membership.leave(p, cause: cause, &ctx)
        case .dieFromEffect(let p, let reason, let cause): return Membership.die(p, reason: reason, cause: cause, &ctx)
        case .injureFromEffect(let p, let amount, let cause): return Membership.injure(p, amount: amount, cause: cause, &ctx)
        }
    }

    /// ノアを歩かせる(確認なし)。歩いている途中なら行き先を変える。通れないマス・置いた物なら、その隣まで。
    func walk(to: WorldPoint, _ ctx: inout StepContext) -> CommandResult {
        guard let ps = ctx.world.people[.noah], ps.presence.isAlive, let pos = ps.position else {
            return .rejected(Rejection("reason.walk.no_one"))
        }
        if case .fighting(let b) = ps.activity, ctx.world.combat.battles[b] != nil {
            return .rejected(Rejection("reason.walk.in_battle"))
        }
        guard to.layer == pos.layer, let layer = ctx.world.map[to.layer], layer.size.contains(to.point) else {
            return .rejected(Rejection("reason.walk.unreachable"))
        }
        var planner = PathPlanner(world: ctx.world, content: ctx.content, workspace: PathWorkspace())
        guard let anchor = Walking.anchor(ps, planner: &planner) else { return .rejected(Rejection("reason.walk.no_one")) }
        let known = planner.known(.noah, to.layer)
        let standable = planner.passableBelief(to.point, to.layer, known: known)
        let r = planner.approach(for: .noah, layer: to.layer, from: anchor, target: [to.point], standOn: standable)
        guard let r else { return .rejected(Rejection("reason.walk.unreachable")) }
        // プレイヤーが自分で歩かせたら、ノアの配属は外れる(連れて行かれない。上書きは残る)
        if ps.assignment != .idle {
            ctx.world.people[.noah]?.assignment = .idle
            ctx.world.people[.noah]?.workSpeed = nil
            ctx.emit(.assigned(person: .noah, assignment: .idle))
        }
        ctx.world.people[.noah]?.dwellUntil = nil
        if r.path.isEmpty && anchor == pos.point {
            ctx.world.people[.noah]?.motion = nil
            ctx.world.people[.noah]?.activity = .idle
            ctx.changes.mark(.people)
            return .done
        }
        Walking.start(.noah, anchor: anchor, path: r.path, goal: r.goal, throughFog: r.throughFog, &ctx)
        ctx.world.people[.noah]?.activity = .walking(to: WorldPoint(to.layer, r.goal))
        return .done
    }

    /// 止まる(次のマスへの途中なら、そのマスで止まる)。
    func stop(_ ctx: inout StepContext) -> CommandResult {
        guard var ps = ctx.world.people[.noah], let pos = ps.position else { return .rejected(Rejection("reason.walk.no_one")) }
        if var m = ps.motion {
            if m.progress > 0, let next = m.path.first {
                m.path = [next]
                m.goal = next
                m.throughFog = false
                ps.motion = m
            } else {
                ps.motion = nil
                ps.activity = .idle
            }
        }
        _ = pos
        ctx.world.people[.noah] = ps
        ctx.changes.mark(.people)
        return .done
    }

    /// 役割を与える。配属はプレイヤーの判断として来歴に残り(印 = 配属の種類)、仲間の賛否の元になる。
    func assign(_ id: PersonID, _ a: Assignment, _ ctx: inout StepContext) -> CommandResult {
        guard let ps = ctx.world.people[id], ps.presence.isMember, ps.position != nil else {
            return .rejected(Rejection("reason.assign.not_member"))
        }
        let w = ctx.world
        switch a {
        case .operate(let e):
            guard w.placements.items[e] != nil else { return .rejected(Rejection("reason.assign.no_target")) }
        case .build(let e):
            guard let p = w.placements.items[e] else { return .rejected(Rejection("reason.assign.no_target")) }
            guard Duties.isUnderConstruction(p) else { return .rejected(Rejection("reason.assign.nothing_to_build")) }
        case .haul(let r):
            guard w.logistics.routes[r] != nil else { return .rejected(Rejection("reason.assign.no_target")) }
        case .follow(let other):
            guard other != id, w.people[other]?.presence.isAlive == true else {
                return .rejected(Rejection("reason.assign.no_target"))
            }
        case .guardArea(let c, _), .gather(_, let c):
            guard w.map[c.layer]?.size.contains(c.point) == true else { return .rejected(Rejection("reason.assign.no_target")) }
        case .idle, .rest:
            break
        }
        var p = ps
        p.assignment = a
        p.haulLeg = nil
        p.workSpeed = nil
        p.dwellUntil = nil
        if case .working = p.activity { p.activity = .idle }
        if case .guarding = p.activity { p.activity = .idle }
        if case .interposing = p.activity { p.activity = .idle }
        if case .carrying = p.activity { p.activity = .idle }
        ctx.world.people[id] = p
        let tags = AssignmentTags.tags(for: a, in: w)
        let rec = ctx.record(.assigned, .person(id), actor: .noah, place: p.position, tags: tags,
                             detail: ["assignment": .string(AssignmentTags.kindName(a))])
        ctx.emit(.assigned(person: id, assignment: a))
        ctx.changes.mark(.people)
        Relations.consider(rec, &ctx)
        if id != .noah { Lines.say(context: "assigned.\(AssignmentTags.kindName(a))", speaker: id, &ctx, trigger: rec) }
        return .done
    }

    /// 装備を替える(蓄えから 1 つ取り、前の物は蓄えへ戻す)。
    func equip(_ id: PersonID, slot: String, stock: StockSelector, _ ctx: inout StepContext) -> CommandResult {
        guard let ps = ctx.world.people[id], ps.presence.isMember else { return .rejected(Rejection("reason.assign.not_member")) }
        guard let took = ctx.takeStock(1, from: stock.holder, where: {
            $0.stuff == stock.stuff && (stock.unique == nil || $0.unique == stock.unique)
        }) else { return .rejected(Rejection("reason.equip.none")) }
        let origin = took.keys.sorted().first
        if let old = ps.equipment[slot] {
            ctx.addStock(old.stuff, 1, to: .base, origin: old.origin)
        }
        ctx.world.people[id]?.equipment[slot] = EquippedItem(stuff: stock.stuff, origin: origin)
        ctx.changes.mark([.people, .inventory])
        return .done
    }

    // MARK: ステップ

    public func step(_ ctx: inout StepContext) {
        Relations.normalizeAll(&ctx)
        Membership.deathsFromHealth(&ctx)
        let order = ctx.world.people.order
        guard order.contains(where: { ctx.world.people[$0]?.position != nil }) else { return }
        let workspace = PathWorkspace()
        let base = CrewRules.progressPerStep(ctx.content.clock)

        // 歩く
        var planner = PathPlanner(world: ctx.world, content: ctx.content, workspace: workspace)
        for id in order {
            guard let ps = ctx.world.people[id], ps.presence.isAlive, ps.motion != nil else { continue }
            if case .fighting(let b) = ps.activity, ctx.world.combat.battles[b] != nil { continue }
            let heavy = id == .noah && ps.override != nil
            let speed = heavy ? base * CrewRules.heavyStepPermille / 1000 : base
            Walking.advance(id, speed: speed, &ctx, planner: &planner)
        }

        // 見る。霧の先を通っている経路は、霧が晴れたら引き直す
        let before = ctx.world.knowledge.mapKnown
        Vision.update(&ctx)
        if ctx.world.knowledge.mapKnown != before {
            planner = PathPlanner(world: ctx.world, content: ctx.content, workspace: workspace)
            for id in order {
                guard let m = ctx.world.people[id]?.motion, m.throughFog == true else { continue }
                Walking.replan(id, &ctx, planner: &planner)
            }
        }

        // 配属を実行する
        planner = PathPlanner(world: ctx.world, content: ctx.content, workspace: workspace)
        for id in order {
            guard let ps = ctx.world.people[id], ps.presence.isMember, ps.position != nil else { continue }
            Duties.run(id, &ctx, planner: &planner)
        }
    }

    // MARK: 出来事への反応

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        switch event {
        case .battleStarted(let b, _):
            for id in ctx.world.combat.battles[b]?.participants ?? [] {
                guard ctx.world.people[id]?.presence.isAlive == true else { continue }
                ctx.world.people[id]?.activity = .fighting(battle: b)
                ctx.world.people[id]?.motion = nil
                ctx.world.people[id]?.workSpeed = nil
                ctx.changes.mark(.people)
            }
        case .battleEnded(let b, _, _, _):
            for id in ctx.world.people.order {
                guard case .fighting(let x) = ctx.world.people[id]?.activity, x == b else { continue }
                ctx.world.people[id]?.activity = .idle
                ctx.changes.mark(.people)
            }
        case .skillAcquired(let p, let skill, _):
            // スキルを書くのは人の切れ端の持ち主(RFResearch は出来事を出すだけ)
            if ctx.world.people[p]?.skills.contains(skill) == false {
                ctx.world.people[p]?.skills.insert(skill)
                ctx.changes.mark(.people)
            }
        case .bodyChanged:
            Membership.deathsFromHealth(&ctx)
        case .runResumed(_, let rec):
            // 巻き戻しの後: 前の周回を覚えている仲間の「前にも」の一言(記憶は RFFailure が付けている)
            Lines.say(context: "rewind.deja_vu", speaker: nil, &ctx, trigger: rec)
        default:
            break
        }
        if Relations.decisionHooks.contains(event.hook), let rec = event.record {
            Relations.consider(rec, &ctx)
        }
    }
}
