import RFContent
import RFKernel
import RFRules
import RFWorld

/// 脅威と戦闘(CORE-11)。
///
/// - 夜: 日没に今夜の群れを決め(EnemyDef.raid)、時刻が来たら巣か灯りの外の遠くに出す。群れは蓄え(保管か拠点の中心)へ歩く。
///   獣を寄せない範囲(repelEnemies。灯り・後で別のもの)と柵のマスには入らない。罠を踏めば倒れる。夜明けに帰る。
/// - 昼: 出会う地形(森の近道など)にいる人に獣が寄って来る。巣に近づけば守りが出る。
/// - 人に寄った(見張りの半径・1 マス)・蓄えに着いた(拠点の人が駆けつける)ら、1 次元の帯の戦闘になる(Lane)。
///   帯は手番ごとに自動で進み、プレイヤーは方針(前に出る / 距離を取る)と撤退だけ選ぶ。
/// - 勝てば獲物(ドロップ表)と倒した記録(数・場所・印)。巣の守りを全部倒せば巣が壊れる。
///   負ければ(逃げても)蓄えを狙って来た群れは奪って帰り、傷を負った人は人の担当に傷を渡す。
///
/// 書いてよい切れ端: combat。乱数の流れ: .combat。受けるコマンド: .combat(...)。
/// Wave 防衛は持たない(オーナー決定 CONF-03)。
public struct CombatSystem: SimSystem {
    public let name = "combat"
    /// 規則(nil ならコンテンツの設定、それも無ければ R1 の既定)。
    public let rules: CombatDef?

    public init(rules: CombatDef? = nil) {
        self.rules = rules
    }

    /// 使う規則。
    public func def(_ content: ContentDB) -> CombatDef {
        // ContentDB に combat の設定が入ったら content.combat を読む(統合担当に依頼済み)
        rules ?? CombatDef()
    }

    // MARK: コマンド

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .combat(let c) = command else { return .notMine }
        let def = def(ctx.content)
        switch c {
        case .stance(let battle, let stance):
            guard ctx.world.combat.battles[battle] != nil else { return .rejected(Rejection("reason.combat.no_battle")) }
            ctx.world.combat.battles[battle]?.stance = stance
            ctx.changes.mark(.combat)
            return .done
        case .retreat(let battle):
            guard let b = ctx.world.combat.battles[battle] else { return .rejected(Rejection("reason.combat.no_battle")) }
            guard !b.retreating else { return .rejected(Rejection("reason.combat.already_retreating")) }
            ctx.world.combat.battles[battle]?.retreating = true
            ctx.changes.mark(.combat)
            return .done
        case .setDefaultStance(let stance):
            ctx.world.combat.defaultStance = stance
            ctx.changes.mark(.combat)
            return .done
        case .spawnEnemy(let kind, let count, let near, let cause):
            guard let d = ctx.content.enemies[kind] else { return .rejected(Rejection("reason.combat.unknown_enemy")) }
            let night = ctx.world.clock.phase != .day
            let nocturnal = (d.nocturnal ?? true) && night
            let intent: ThreatState.Intent
            if nocturnal {
                intent = .raid(target: Threats.foodTarget(ctx))
            } else if let p = nearestPerson(to: near, ctx.world) {
                intent = .hunt(person: p)
            } else {
                intent = .roam
            }
            guard Threats.spawn(kind, count: count, near: near, intent: intent, nocturnal: nocturnal, origin: cause, &ctx)
                != nil else { return .rejected(Rejection("reason.combat.no_room")) }
            return .done
        case .startBattle(let kind, let count, let near):
            guard ctx.content.enemies[kind] != nil else { return .rejected(Rejection("reason.combat.unknown_enemy")) }
            let intent: ThreatState.Intent = nearestPerson(to: near, ctx.world).map { .hunt(person: $0) } ?? .roam
            guard let t = Threats.spawn(kind, count: count, near: near, intent: intent, nocturnal: false,
                                        origin: ctx.cause, &ctx) else { return .rejected(Rejection("reason.combat.no_room")) }
            let pos = ctx.world.combat.threats[t]!.position
            let persons = Threats.fighters(ctx.world)
                .filter { !Threats.busy($0.0, ctx.world) && $0.1.layer == pos.layer && $0.1.point.chebyshev(to: pos.point) <= def.rally }
                .map(\.0)
            Battles.start(.encounter, at: pos, threats: [t], persons: persons, &ctx, def: def)
            return .done
        }
    }

    // MARK: 1 ステップ

    public func step(_ ctx: inout StepContext) {
        let c = ctx.world.combat
        let content = ctx.content
        let anyEncounter = content.enemies.values.contains { ($0.encounterPerHour ?? 0) > 0 }
        let anyNest = content.enemies.values.contains { !($0.nests ?? []).isEmpty }
        if c.threats.isEmpty, c.battles.isEmpty, c.plannedRaids.isEmpty, !anyEncounter, !anyNest { return }
        let def = def(content)
        if ctx.world.clock.phase != .day { Threats.releaseRaids(&ctx, def: def) }
        if anyEncounter { Threats.encounters(&ctx) }
        if anyNest { Threats.guardNests(&ctx, def: def) }
        Threats.moveAll(&ctx)
        engage(&ctx, def: def)
        for id in ctx.world.combat.battles.keys.sorted() { Battles.tick(id, &ctx, def: def) }
    }

    // MARK: 出来事

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        switch event {
        case .phaseChanged(to: .dusk, _):
            ctx.world.combat.night = NightTally()
            ctx.world.combat.plannedRaids = []
            Threats.planRaids(&ctx, def: def(ctx.content))
        case .dawn:
            // 夜の獣は帰る(戦っている群れは戦いの後で)。罠は仕掛け直す。
            let inBattle = Set(ctx.world.combat.battles.values.flatMap(\.enemies))
            for (id, t) in ctx.world.combat.threats.sorted(by: { $0.key < $1.key }) where t.nocturnal && !inBattle.contains(id) {
                Threats.remove(id, &ctx, lastRecord: nil)
            }
            ctx.world.combat.plannedRaids = []
            ctx.world.combat.sprungTraps = []
            ctx.changes.mark(.combat)
        default:
            break
        }
    }

    // MARK: 寄る

    /// 脅威と人が出会ったら戦闘にする。
    func engage(_ ctx: inout StepContext, def: CombatDef) {
        let now = ctx.world.clock.now
        for id in ctx.world.combat.threats.keys.sorted() {
            guard let t = ctx.world.combat.threats[id] else { continue }
            if ctx.world.combat.battles.values.contains(where: { $0.enemies.contains(id) }) { continue }
            let calm = t.calmUntil.map { now < $0 } ?? false
            // 1. 近くの戦闘に加わる
            if let b = ctx.world.combat.battles.values.sorted(by: { $0.id < $1.id }).first(where: {
                $0.at.layer == t.position.layer && $0.at.point.chebyshev(to: t.position.point) <= def.join
            }), !calm {
                Battles.join(b.id, threat: id, &ctx)
                continue
            }
            let free = Threats.fighters(ctx.world).filter { !Threats.busy($0.0, ctx.world) && $0.1.layer == t.position.layer }
            let kind: BattleState.Kind
            if case .guardNest(let poi) = t.intent { kind = .nest(poi: poi) } else { kind = .encounter }
            if !calm {
                // 2. 持ち場に着いて立っている見張り(人の担当の PeopleState.guards)が見つける。見張りの火の近くなら遠くまで
                let watches = Threats.structures("watch", ctx)
                let standing = Set(ctx.world.people.guards)
                let guards = free.filter { p, pos in
                    guard standing.contains(p), let ps = ctx.world.people[p],
                          case .guardArea(_, let radius) = ps.override?.assignment ?? ps.assignment
                    else { return false }
                    let bonus = watches.filter { $0.0.at.layer == pos.layer && $0.0.at.point.chebyshev(to: pos.point) <= $0.1 }
                        .map(\.1).max() ?? 0
                    return pos.point.chebyshev(to: t.position.point) <= radius + bonus
                }.map(\.0)
                if !guards.isEmpty {
                    Battles.start(kind, at: t.position, threats: [id], persons: guards, &ctx, def: def)
                    continue
                }
                // 3. 蓄えに着いた: 拠点の人が駆けつける(下の 5 で、誰もいなければ奪って帰る)
                if case .raid(let target) = t.intent, t.position.point.chebyshev(to: target.point) <= 1 {
                    let defenders = free.filter { $0.1.point.chebyshev(to: target.point) <= def.rally }.map(\.0)
                    if !defenders.isEmpty {
                        Battles.start(.raid(target: target), at: t.position, threats: [id], persons: defenders, &ctx, def: def)
                        continue
                    }
                }
                // 4. すぐそばの人に寄る(獣を寄せない範囲の中にいる人には寄れない)
                let reach = def.engage + (kind == .encounter ? 0 : 1)
                let near = free.filter { _, pos in
                    pos.point.chebyshev(to: t.position.point) <= reach
                        && !Auras.repelsEnemies(at: pos, in: ctx.world, content: ctx.content)
                }
                if !near.isEmpty {
                    let party = free.filter { _, pos in pos.point.chebyshev(to: t.position.point) <= max(reach, def.join) }
                        .map(\.0)
                    Battles.start(kind, at: t.position, threats: [id], persons: party, &ctx, def: def)
                    continue
                }
            }
            // 5. 蓄えに着いたが誰も来ない(か、負かした直後): 奪って帰る
            if case .raid(let target) = t.intent, t.position.point.chebyshev(to: target.point) <= 1,
               ctx.world.combat.threats[id] != nil {
                Threats.steal(id, at: target, cause: nil, &ctx)
            }
        }
    }

    func nearestPerson(to p: WorldPoint, _ w: WorldState) -> PersonID? {
        Threats.fighters(w).filter { $0.1.layer == p.layer }
            .min { a, b in
                let da = a.1.point.chebyshev(to: p.point), db = b.1.point.chebyshev(to: p.point)
                return da != db ? da < db : false
            }?.0
    }
}
