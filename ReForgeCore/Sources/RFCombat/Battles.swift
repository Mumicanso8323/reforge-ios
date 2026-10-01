import RFContent
import RFKernel
import RFRules
import RFWorld

/// 戦闘の始まり・加わり・終わり(世界状態への反映と来歴)。帯の中の計算は Lane。
enum Battles {
    // MARK: 始める

    @discardableResult
    static func start(_ kind: BattleState.Kind, at: WorldPoint, threats: [EntityID], persons: [PersonID],
                      _ ctx: inout StepContext, def: CombatDef) -> EntityID? {
        let w = ctx.world
        let ts = threats.compactMap { w.combat.threats[$0] }
        // 定義の無い敵とは戦えない(戦闘にしない)
        guard ts.allSatisfy({ ctx.content.enemies[$0.kind] != nil }) else { return nil }
        // 倒れるほど傷んでいる人は戦いに出ない(R1 の獣との戦いで死なないように)
        let persons = persons.filter { (w.people[$0]?.body.health.raw ?? 0) / 1000 >= Int64(def.down) }
        guard !ts.isEmpty, !persons.isEmpty else { return nil }
        var units: [BattleUnit] = []
        let laneSize = max(def.lane, ts.compactMap { ctx.content.enemies[$0.kind]?.laneSize }.max() ?? 0)
        for (i, p) in persons.enumerated() {
            guard let ps = w.people[p] else { continue }
            let hp = max(1, Int(ps.body.health.raw / 1000))
            let wp = Weapons.profile(ps.equipment[def.slot], def: def, ruleBook: ctx.content.ruleBook)
            units.append(BattleUnit(ref: .person(p), side: .allies, position: min(i, max(0, laneSize / 2 - 1)), hp: hp,
                                    maxHP: 100, attack: def.attack + wp.bonus, defense: def.defense, speed: def.speed,
                                    reachMin: wp.reachMin, reachMax: wp.reachMax, weaponOrigin: wp.origin))
        }
        for t in ts { units += enemyUnits(t, startingAt: units.filter { $0.side == .enemies }.count, laneSize: laneSize, ctx) }
        let id = ctx.world.newEntityID()
        let first = ts[0]
        var inputs = ts.compactMap(\.origin)
        if case .guardNest(let poi) = first.intent, let r = w.combat.nests[poi]?.destroyed { inputs.append(r) }
        let rec = ctx.record(.fought, .enemy(first.kind, first.id), actor: persons.first, place: at, inputs: inputs,
                             detail: ["enemies": .int(Int64(ts.reduce(0) { $0 + $1.count }))])
        let b = BattleState(id: id, kind: kind, at: at, laneSize: laneSize, participants: persons,
                            enemies: ts.map(\.id), units: units, stance: w.combat.defaultStance, startedAt: w.clock.now,
                            firstTurnAt: w.clock.now + GameDuration(seconds: def.turn), origin: rec)
        ctx.world.combat.battles[id] = b
        for t in ts { ctx.world.combat.threats[t.id]?.motion = nil }
        if w.clock.phase != .day { ctx.world.combat.night.battles += 1 }
        ctx.emit(.battleStarted(battle: id, record: rec))
        ctx.changes.mark(.combat)
        return id
    }

    /// 群れを帯の上の 1 体ずつにする(残りの体力を前から配る)。
    static func enemyUnits(_ t: ThreatState, startingAt k: Int, laneSize: Int, _ ctx: StepContext) -> [BattleUnit] {
        guard let d = ctx.content.enemies[t.kind], t.count > 0 else { return [] }
        let g = Threats.growth(t.kind, ctx)
        let each = max(1, d.health * g / 1000)
        var rest = t.hp
        var out: [BattleUnit] = []
        for i in 0..<t.count {
            let h = max(1, min(each, rest - (t.count - 1 - i)))
            rest -= h
            out.append(BattleUnit(ref: .enemy(threat: t.id, kind: t.kind, index: i), side: .enemies,
                                  position: max(laneSize / 2, laneSize - 1 - (k + i)), hp: h, maxHP: each,
                                  attack: d.attack * g / 1000, defense: (d.defense ?? 0) * g / 1000, speed: d.speed ?? 5,
                                  reachMin: d.reachMin ?? 0, reachMax: max(d.reachMin ?? 0, d.reachMax ?? 0)))
        }
        return out
    }

    /// 近くの戦闘に群れが加わる。
    static func join(_ battle: EntityID, threat: EntityID, _ ctx: inout StepContext) {
        guard var b = ctx.world.combat.battles[battle], let t = ctx.world.combat.threats[threat],
              !b.enemies.contains(threat) else { return }
        let k = b.units.filter { $0.side == .enemies }.count
        b.units += enemyUnits(t, startingAt: k, laneSize: b.laneSize, ctx).map { u in
            var u = u
            u.position = b.laneSize - 1
            return u
        }
        b.enemies.append(threat)
        ctx.world.combat.battles[battle] = b
        ctx.world.combat.threats[threat]?.motion = nil
        ctx.changes.mark(.combat)
    }

    // MARK: 手番

    static func tick(_ id: EntityID, _ ctx: inout StepContext, def: CombatDef) {
        guard var b = ctx.world.combat.battles[id] else { return }
        b.elapsed += SimStep.gameSeconds
        // 帯の上に誰もいない戦闘(他の仕組みが作った枠)は進めない
        if b.units.isEmpty {
            ctx.world.combat.battles[id] = b
            return
        }
        // いなくなった人(死んだ・失って続けるで外れた)は帯から抜ける
        for i in b.units.indices where b.units[i].isActive {
            guard let p = b.units[i].person else { continue }
            if (b.units[i].side == .allies && !b.participants.contains(p)) || ctx.world.people[p]?.presence.isAlive != true {
                b.units[i].state = .escaped
            }
        }
        var result = Lane.outcome(of: b)
        if result == nil, ctx.world.clock.now >= b.nextTurnAt {
            result = ctx.random(.combat) { Lane.resolveTurn(&b, def: def, rng: &$0) }
            b.nextTurnAt = b.nextTurnAt + GameDuration(seconds: def.turn)
            // 決着がつかないまま長引いたら獣が引く(最小の傷 1 があるので普通は起きない)
            if result == nil, b.turn >= 200 { result = .fled }
            ctx.changes.mark(.combat)
        }
        ctx.world.combat.battles[id] = b
        if let result { end(id, result, &ctx, def: def) }
    }

    // MARK: 終える

    static func end(_ id: EntityID, _ outcome: BattleState.Outcome, _ ctx: inout StepContext, def: CombatDef) {
        guard var b = ctx.world.combat.battles.removeValue(forKey: id) else { return }
        b.outcome = outcome
        let now = ctx.world.clock.now
        let night = ctx.world.clock.phase != .day
        // 一番多く倒した人(同じなら並びの先)
        let topKiller = b.units.filter { $0.side == .allies }.max { x, y in x.kills < y.kills }
            .flatMap { u in u.kills > 0 ? u.person : nil } ?? b.participants.first
        let holder: HolderID
        if case .raid = b.kind { holder = .base } else { holder = topKiller.map { .person($0) } ?? .base }

        var defeatRecords: [ProvenanceID] = []
        var survivors: [EntityID] = []
        for tid in b.enemies {
            guard var t = ctx.world.combat.threats[tid] else { continue }
            let mine = b.units.filter { if case .enemy(let x, _, _) = $0.ref { x == tid } else { false } }
            let killed = mine.filter { $0.state == .dead }.count
            if killed > 0 {
                let rec = Threats.recordKills(t, killed, actor: topKiller, place: b.at, inputs: [b.origin],
                                              holder: holder, &ctx)
                defeatRecords.append(rec)
            }
            let alive = mine.filter { $0.isActive }
            if alive.isEmpty {
                Threats.remove(tid, &ctx, lastRecord: defeatRecords.last)
            } else {
                t.count = alive.count
                t.hp = alive.reduce(0) { $0 + $1.hp }
                t.calmUntil = now + .hours(def.calm)
                ctx.world.combat.threats[tid] = t
                survivors.append(tid)
            }
        }

        let subject: SubjectRef = b.units.lazy.compactMap { u -> SubjectRef? in
            if case .enemy(let t, let k, _) = u.ref { return .enemy(k, t) }
            return nil
        }.first ?? .none
        let endRecord: ProvenanceID
        switch outcome {
        case .won:
            endRecord = defeatRecords.first ?? ctx.record(.fought, subject, actor: topKiller, place: b.at,
                                                           inputs: [b.origin], detail: ["result": .string("won")])
        case .fled:
            endRecord = ctx.record(.fled, subject, actor: b.participants.first, place: b.at, inputs: [b.origin])
        case .lost:
            endRecord = ctx.record(.fought, subject, actor: b.participants.first, place: b.at, inputs: [b.origin],
                                   detail: ["result": .string("lost")])
        }

        // 蓄えを狙って来た獣に負けた・逃げた: 奪われる
        if case .raid(let target) = b.kind, outcome != .won {
            for tid in survivors { Threats.steal(tid, at: target, cause: endRecord, &ctx) }
        }

        // 傷(体の書き換えは人の担当)
        for u in b.units where u.side == .allies {
            guard let p = u.person else { continue }
            if u.state == .dead {
                ctx.queue(.crew(.dieFromEffect(person: p, reason: "reason.combat.killed", cause: endRecord)))
            } else if u.damageTaken > 0 {
                // 死なない戦い: 傷は「いまの体力 − 1」まで(人の担当は体力 0 以下で死なせる)
                var amount = u.damageTaken * 1000
                if !b.lethal { amount = min(amount, Int((ctx.world.people[p]?.body.health.raw ?? 0) - 1000)) }
                if amount > 0 { ctx.queue(.crew(.injureFromEffect(person: p, amount: amount, cause: endRecord))) }
            }
            if u.damageTaken > 0, night, !ctx.world.combat.night.injured.contains(p) {
                ctx.world.combat.night.injured.append(p)
            }
        }

        // 相手の側の人(集団との戦い。U16): 死・傷は人の担当へ。集団の旗で結果を残す
        if case .group(let g) = b.kind {
            for u in b.units where u.side == .enemies {
                guard let p = u.person else { continue }
                if u.state == .dead {
                    ctx.queue(.crew(.dieFromEffect(person: p, reason: "reason.combat.killed", cause: endRecord)))
                } else if u.damageTaken > 0 {
                    var amount = u.damageTaken * 1000
                    if !b.lethal { amount = min(amount, Int((ctx.world.people[p]?.body.health.raw ?? 0) - 1000)) }
                    if amount > 0 { ctx.queue(.crew(.injureFromEffect(person: p, amount: amount, cause: endRecord))) }
                }
            }
            let flag = outcome == .won ? "battle.won" : (outcome == .fled ? "battle.fled" : "battle.lost")
            EffectApplier.apply([.groupFlag(id: g, flag: flag, on: true)], &ctx, cause: endRecord)
        }

        ctx.world.combat.lastBattle = b
        ctx.emit(.battleEnded(battle: id, won: outcome == .won, fled: outcome == .fled, record: endRecord))
        ctx.changes.mark(.combat)
    }

    // MARK: 集団との戦い(U16・D11)

    /// 拠点の外の集団の人と戦う。味方は near の近く(rally)にいる一員、相手はその集団の生きている人(members で名指し)。
    /// 帯・手番・方針・撤退は獣との戦いと同じ。人はどちらの側でも倒れて外れ、lethal なら 0 で死ぬ。
    @discardableResult
    static func startGroup(_ g: GroupID, near: WorldPoint, members: [PersonID]?, lethal: Bool, cause: ProvenanceID?,
                           _ ctx: inout StepContext, def: CombatDef) -> EntityID? {
        let w = ctx.world
        func fit(_ p: PersonID) -> Bool {
            guard let ps = w.people[p], ps.presence.isAlive else { return false }
            return Int(ps.body.health.raw / 1000) >= def.down
        }
        let allies = Threats.fighters(w).filter { p, pos in
            !Threats.busy(p, w) && pos.layer == near.layer && pos.point.chebyshev(to: near.point) <= def.rally && fit(p)
        }.map(\.0)
        let foes = (members ?? w.people.order.filter { w.people[$0]?.group == g })
            .filter { fit($0) && !w.people.members.contains($0) && !Threats.busy($0, w) }
        guard !allies.isEmpty, !foes.isEmpty else { return nil }
        let laneSize = max(def.lane, foes.count + 2)
        var units: [BattleUnit] = []
        func unit(_ p: PersonID, _ side: BattleUnit.Side, _ pos: Int) -> BattleUnit? {
            guard let ps = w.people[p] else { return nil }
            let wp = Weapons.profile(ps.equipment[def.slot], def: def, ruleBook: ctx.content.ruleBook)
            return BattleUnit(ref: .person(p), side: side, position: pos, hp: max(1, Int(ps.body.health.raw / 1000)),
                              maxHP: 100, attack: def.attack + wp.bonus, defense: def.defense, speed: def.speed,
                              reachMin: wp.reachMin, reachMax: wp.reachMax, weaponOrigin: wp.origin)
        }
        for (i, p) in allies.enumerated() {
            if let u = unit(p, .allies, min(i, max(0, laneSize / 2 - 1))) { units.append(u) }
        }
        for (i, p) in foes.enumerated() {
            if let u = unit(p, .enemies, max(laneSize / 2, laneSize - 1 - i)) { units.append(u) }
        }
        let id = ctx.world.newEntityID()
        let rec = ctx.record(.fought, .person(foes[0]), actor: allies.first, place: near,
                             inputs: [cause].compactMap { $0 },
                             detail: ["group": .string(g.rawValue), "enemies": .int(Int64(foes.count))])
        let b = BattleState(id: id, kind: .group(g), at: near, laneSize: laneSize, participants: allies, enemies: [],
                            units: units, stance: w.combat.defaultStance, startedAt: w.clock.now,
                            firstTurnAt: w.clock.now + GameDuration(seconds: def.turn), origin: rec, lethal: lethal)
        ctx.world.combat.battles[id] = b
        if w.clock.phase != .day { ctx.world.combat.night.battles += 1 }
        ctx.emit(.battleStarted(battle: id, record: rec))
        ctx.changes.mark(.combat)
        return id
    }
}
