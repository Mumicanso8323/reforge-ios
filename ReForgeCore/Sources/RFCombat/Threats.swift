import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 地図の上の脅威: 出る(夜の群れ・森で出会う・巣の守り・効果)・歩く(灯りと柵を避ける)・罠・人に寄る・奪う。
enum Threats {
    // MARK: 読むもの

    /// 倒した数による強さ(千分率。R2 の敵の拡大。R1 は growthPerKill が無いので 1000)。
    static func growth(_ kind: EnemyKindID, _ ctx: StepContext) -> Int {
        let per = ctx.content.enemies[kind]?.growthPerKill ?? 0
        return 1000 + per * (ctx.world.combat.kills[kind] ?? 0)
    }

    /// 戦える人(一員・生きている・地図の上にいる)。並びの順。
    static func fighters(_ w: WorldState) -> [(PersonID, WorldPoint)] {
        w.people.members.compactMap { p in
            guard let ps = w.people[p], ps.presence.isAlive, let pos = ps.position else { return nil }
            return (p, pos)
        }
    }

    static func busy(_ p: PersonID, _ w: WorldState) -> Bool { w.combat.battle(of: p) != nil }

    /// 完成した建造物のうち、provides[tag] > 0 のもの(実体の順)。
    static func structures(_ tag: String, _ ctx: StepContext) -> [(Placement, Int)] {
        let w = ctx.world
        return w.placements.sortedIDs.compactMap { id in
            guard let p = w.placements.items[id], case .structure = p.kind, p.status == .running,
                  let v = Hearths.provides(p, ctx.content)[tag], v > 0 else { return nil }
            return (p, v)
        }
    }

    /// 獣が狙う蓄えの場所: 最も早く建てた保管、無ければ拠点の範囲の中心。
    static func foodTarget(_ ctx: StepContext) -> WorldPoint {
        let w = ctx.world
        if let s = structures("storage", ctx).min(by: { $0.0.origin < $1.0.origin }) { return s.0.at }
        if let a = w.base.area ?? w.map.baseArea {
            return WorldPoint(.surface, GridPoint(a.origin.x + a.size.width / 2, a.origin.y + a.size.height / 2))
        }
        return w.map.spawn
    }

    /// 獣が入れないマス(柵・獣を寄せない範囲の中)。
    static func blocked(on layer: LayerID, _ ctx: StepContext) -> Set<GridPoint> {
        var out: Set<GridPoint> = []
        for (p, _) in structures("fence", ctx) where p.at.layer == layer {
            for f in p.footprint { out.insert(p.at.point + f) }
        }
        let w = ctx.world
        for a in w.auras.active.values.sorted(by: { $0.id < $1.id }) {
            guard a.strength > 0, a.until.map({ w.clock.now < $0 }) ?? true,
                  ctx.content.auras[a.kind]?.modifiers.contains(where: { if case .repelEnemies = $0 { true } else { false } }) == true,
                  let c = Auras.center(of: a, in: w), c.layer == layer else { continue }
            for dy in -a.radius...a.radius { for dx in -a.radius...a.radius { out.insert(c.point + GridPoint(dx, dy)) } }
        }
        return out
    }

    static func passable(_ p: GridPoint, _ layer: MapLayer, _ costs: MoveCostTable) -> Bool {
        guard let b = layer.biome(at: p) else { return false }
        return costs.cost(b) != nil
    }

    // MARK: 出る

    /// 群れを地図に出す。near から近い、通れて獣の入れるマスに。置けなければ nil。
    @discardableResult
    static func spawn(_ kind: EnemyKindID, count: Int, near: WorldPoint, intent: ThreatState.Intent, nocturnal: Bool,
                      nest: EntityID? = nil, origin: ProvenanceID? = nil, _ ctx: inout StepContext) -> EntityID? {
        guard let d = ctx.content.enemies[kind], count > 0, let layer = ctx.world.map.layers[near.layer] else { return nil }
        let costs = MoveCostTable(terrains: ctx.content.terrains)
        let block = blocked(on: near.layer, ctx)
        var spot: GridPoint?
        search: for r in 0...4 {
            for dy in -r...r {
                for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    let p = near.point + GridPoint(dx, dy)
                    if passable(p, layer, costs) && !block.contains(p) { spot = p; break search }
                }
            }
        }
        guard let spot else { return nil }
        let id = ctx.world.newEntityID()
        let hp = max(1, d.health * growth(kind, ctx) / 1000) * count
        ctx.world.combat.threats[id] = ThreatState(id: id, kind: kind, position: WorldPoint(near.layer, spot), count: count,
                                                   hp: hp, intent: intent, nocturnal: nocturnal, nest: nest, origin: origin)
        ctx.emit(.threatAppeared(threat: id, kind: kind))
        ctx.changes.mark(.combat)
        return id
    }

    /// center から距離 r の四角い輪の上の、獣の入れるマス(乱数で選ぶ。24 回試して無ければ nil)。
    static func ringPoint(around center: WorldPoint, radius r: Int, _ ctx: inout StepContext) -> WorldPoint? {
        guard let layer = ctx.world.map.layers[center.layer], r > 0 else { return nil }
        let costs = MoveCostTable(terrains: ctx.content.terrains)
        let block = blocked(on: center.layer, ctx)
        for _ in 0..<24 {
            let (side, off) = ctx.random(.combat) { ($0.int(below: 4), $0.int(in: -r...r)) }
            let d: GridPoint
            switch side {
            case 0: d = GridPoint(off, -r)
            case 1: d = GridPoint(r, off)
            case 2: d = GridPoint(off, r)
            default: d = GridPoint(-r, off)
            }
            let p = center.point + d
            if passable(p, layer, costs), !block.contains(p) { return WorldPoint(center.layer, p) }
        }
        return nil
    }

    /// 巣(地図の POI)のうち、その獣の巣で壊れていないもの(実体の順)。
    static func nests(of kind: EnemyKindID, _ ctx: StepContext) -> [(EntityID, POIState)] {
        guard let kinds = ctx.content.enemies[kind]?.nests, !kinds.isEmpty,
              let layer = ctx.world.map.layers[.surface] else { return [] }
        return layer.pois.filter { kinds.contains($0.value.kind) && ctx.world.combat.nests[$0.key]?.destroyed == nil }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// 日没に今夜の群れを決める。
    /// darkOnly: 夜のうちに火が消えたときの振り直し(闇の重みだけで振る)。
    static func planRaids(_ ctx: inout StepContext, def: CombatDef, darkOnly: Bool = false) {
        let target = foodTarget(ctx)
        for (kind, d) in ctx.content.enemies.sorted(by: { $0.key < $1.key }) {
            guard let raid = d.raid, ctx.world.clock.day >= (raid.fromDay ?? 1) else { continue }
            if darkOnly, (raid.lure?.dark ?? 0) <= 0 { continue }
            if let th = raid.lure?.threshold {
                let gate = FactRate.rate(10_000, requires: raid.requiresFact, until: raid.untilFact,
                                         modifiers: nil, known: ctx.world.knowledge.factSet)
                guard gate > 0, !ctx.world.combat.plannedRaids.contains(where: { $0.kind == kind }),
                      lure(kind, raid, darkOnly: false, ctx) >= th else { continue }
                planRaid(kind, raid, target: target, def: def, &ctx)
                continue
            }
            let base = darkOnly ? 0 : raid.perNight
            let gate = FactRate.rate(10_000, requires: raid.requiresFact, until: raid.untilFact,
                                     modifiers: nil, known: ctx.world.knowledge.factSet)
            guard gate > 0 else { continue }
            var perNight = darkOnly ? 0 : FactRate.rate(base, requires: raid.requiresFact, until: raid.untilFact,
                                                        modifiers: raid.factModifiers, known: ctx.world.knowledge.factSet)
            perNight += lure(kind, raid, darkOnly: darkOnly, ctx)
            guard perNight > 0 else { continue }
            let roll = ctx.random(.combat) { $0.int(below: 10_000) }
            guard roll < perNight else { continue }
            planRaid(kind, raid, target: target, def: def, &ctx)
        }
    }

    /// 群れを 1 つ予定に入れる(数・時刻・巣を決める)。
    static func planRaid(_ kind: EnemyKindID, _ raid: RaidDef, target: WorldPoint, def: CombatDef,
                         _ ctx: inout StepContext) {
        let lo = max(1, raid.min ?? 1)
        let count = ctx.random(.combat) { $0.int(in: lo...max(lo, raid.max ?? lo)) }
        let hours = ctx.random(.combat) { $0.int(in: def.raidHours) }
        let knownOnly = raid.requiresKnownNest == true
        let nest = nests(of: kind, ctx)
            .filter { $0.1.at.chebyshev(to: target.point) <= def.nestReach }
            .filter { !knownOnly || ctx.world.knowledge.discovered.contains($0.0) }
            .min { a, b in
                let da = a.1.at.chebyshev(to: target.point), db = b.1.at.chebyshev(to: target.point)
                return da != db ? da < db : a.0 < b.0
            }?.0
        if (raid.requiresNest == true || knownOnly) && nest == nil { return }
        ctx.world.combat.plannedRaids.append(
            PlannedRaid(kind: kind, count: count, at: ctx.world.clock.now + .hours(hours), nest: nest))
    }

    /// 獣が寄る 3 つの入力の足し(確率の型では万分率、しきい値の型では点)。煙 = 燃えている火床の数、縄張り = 巣のそばの置いた物、闇 = 焚き火が消えている。
    static func lure(_ kind: EnemyKindID, _ raid: RaidDef, darkOnly: Bool, _ ctx: StepContext) -> Int {
        guard let l = raid.lure else { return 0 }
        let w = ctx.world
        let hearths = Hearths.structureHearths(w, ctx.content).compactMap { w.placements.items[$0] }
        let lit = hearths.filter { (Hearths.level(of: $0, ctx.content) ?? .out) != .out }.count
        let dark = !hearths.isEmpty && lit == 0 ? (l.dark ?? 0) : 0
        if darkOnly { return dark }
        var add = lit * (l.smoke ?? 0) + dark
        if let t = l.territory, t > 0, let fc = l.fellingCounter {
            add += (w.narrative.counters[fc] ?? 0) * t
        } else if let t = l.territory, t > 0 {
            let r = l.territoryRadius ?? 6
            let nestPoints = nests(of: kind, ctx).map(\.1.at)
            let near = w.placements.items.values.filter { p in
                p.at.layer == .surface && nestPoints.contains { $0.chebyshev(to: p.at.point) <= r }
            }.count
            add += near * t
        }
        return add
    }

    /// 時刻の来た群れを出す(夜だけ)。
    static func releaseRaids(_ ctx: inout StepContext, def: CombatDef) {
        let now = ctx.world.clock.now
        let due = ctx.world.combat.plannedRaids.filter { $0.at <= now }
        guard !due.isEmpty else { return }
        ctx.world.combat.plannedRaids.removeAll { $0.at <= now }
        let target = foodTarget(ctx)
        for r in due {
            let from: WorldPoint?
            if let n = r.nest, let poi = ctx.world.map.layers[.surface]?.pois[n] {
                from = WorldPoint(.surface, poi.at)
            } else {
                from = ringPoint(around: target, radius: def.approach, &ctx)
            }
            guard let from else { continue }
            if spawn(r.kind, count: r.count, near: from, intent: .raid(target: target), nocturnal: true, nest: r.nest,
                     &ctx) != nil {
                ctx.world.combat.night.raids += 1
            }
        }
    }

    /// 昼に出会う地形(森の近道など)にいる人に、獣が寄って来る。
    static func encounters(_ ctx: inout StepContext) {
        let known = ctx.world.knowledge.factSet
        let defs: [(EnemyKindID, EnemyDef, Int)] = ctx.content.enemies.sorted { $0.key < $1.key }.compactMap { kind, d in
            guard !(d.habitats ?? []).isEmpty else { return nil }
            let rate = FactRate.rate(d.encounterPerHour ?? 0, requires: d.encounterRequiresFact,
                                     until: d.encounterUntilFact, modifiers: d.encounterFactModifiers, known: known)
            return rate > 0 ? (kind, d, rate) : nil
        }
        guard !defs.isEmpty, let layer = ctx.world.map.layers[.surface] else { return }
        let stepsPerHour = 3600 / Int(SimStep.gameSeconds)
        for (p, pos) in fighters(ctx.world) where pos.layer == .surface && !busy(p, ctx.world) {
            guard let terrain = layer.terrain(at: pos.point) else { continue }
            if Auras.repelsEnemies(at: pos, in: ctx.world, content: ctx.content) { continue }
            let hunted = ctx.world.combat.threats.values.contains { if case .hunt(let x) = $0.intent { x == p } else { false } }
            if hunted { continue }
            for (kind, d, rate) in defs where d.habitats?.contains(terrain) == true {
                let roll = ctx.random(.combat) { $0.int(below: 10_000 * stepsPerHour) }
                guard roll < rate else { continue }
                let lo = max(1, d.encounterMin ?? 1)
                let n = ctx.random(.combat) { $0.int(in: lo...max(lo, d.encounterMax ?? lo)) }
                if let at = ringPoint(around: pos, radius: 3, &ctx) {
                    spawn(kind, count: n, near: at, intent: .hunt(person: p), nocturnal: false, &ctx)
                }
                break
            }
        }
    }

    /// 巣に近づいた人がいれば、巣の守りが出る。
    static func guardNests(_ ctx: inout StepContext, def: CombatDef) {
        let kinds = ctx.content.enemies.sorted { $0.key < $1.key }.filter { !($0.value.nests ?? []).isEmpty }
        guard !kinds.isEmpty else { return }
        let people = fighters(ctx.world).filter { $0.1.layer == .surface }
        guard !people.isEmpty else { return }
        for (kind, d) in kinds {
            for (poi, state) in nests(of: kind, ctx) {
                if let g = ctx.world.combat.nests[poi]?.guardThreat, ctx.world.combat.threats[g] != nil { continue }
                guard people.contains(where: { $0.1.point.chebyshev(to: state.at) <= def.engage + 2 }) else { continue }
                let at = WorldPoint(.surface, state.at)
                if let t = spawn(kind, count: max(1, d.nestGuard ?? 2), near: at, intent: .guardNest(poi: poi),
                                 nocturnal: false, nest: poi, &ctx) {
                    var n = ctx.world.combat.nests[poi] ?? NestState()
                    n.guardThreat = t
                    ctx.world.combat.nests[poi] = n
                }
            }
        }
    }

    // MARK: 歩く

    static func moveAll(_ ctx: inout StepContext) {
        let ids = ctx.world.combat.threats.keys.sorted()
        guard !ids.isEmpty else { return }
        let inBattle = Set(ctx.world.combat.battles.values.flatMap(\.enemies))
        var blockCache: [LayerID: Set<GridPoint>] = [:]
        let costs = MoveCostTable(terrains: ctx.content.terrains)
        for id in ids where !inBattle.contains(id) {
            guard let t = ctx.world.combat.threats[id], let goal = goal(of: t, ctx.world),
                  let layer = ctx.world.map.layers[t.position.layer] else { continue }
            if t.position.point.chebyshev(to: goal.point) <= 1 { continue }
            let block = blockCache[t.position.layer] ?? blocked(on: t.position.layer, ctx)
            blockCache[t.position.layer] = block
            var cur = t
            cur.moveCarry += (ctx.content.enemies[t.kind]?.mapSpeed ?? 4) * Int(SimStep.gameSeconds)
            while cur.moveCarry >= 3600 {
                cur.moveCarry -= 3600
                guard let next = nextTile(&cur, goal: goal.point, layer: layer, costs: costs, block: block, ctx) else {
                    cur.moveCarry = 0
                    break
                }
                cur.position = WorldPoint(cur.position.layer, next)
                ctx.world.combat.threats[id] = cur
                if !springTraps(id, at: cur.position, &ctx) { break }
                guard let again = ctx.world.combat.threats[id] else { break }
                cur = again
                if next.chebyshev(to: goal.point) <= 1 { break }
            }
            if ctx.world.combat.threats[id] != nil { ctx.world.combat.threats[id] = cur }
            ctx.changes.mark(.combat)
        }
    }

    static func goal(of t: ThreatState, _ w: WorldState) -> WorldPoint? {
        switch t.intent {
        case .raid(let target): return target.layer == t.position.layer ? target : nil
        case .hunt(let p):
            guard let ps = w.people[p], ps.presence.isAlive, let pos = ps.position, pos.layer == t.position.layer
            else { return nil }
            return pos
        case .guardNest, .roam: return nil
        }
    }

    /// 次の 1 マス。道があればそれに沿い、無ければ(灯りの中が行き先など)近づけるだけ近づく。
    static func nextTile(_ t: inout ThreatState, goal: GridPoint, layer: MapLayer, costs: MoveCostTable,
                         block: Set<GridPoint>, _ ctx: StepContext) -> GridPoint? {
        let here = t.position.point
        func ok(_ p: GridPoint) -> Bool { passable(p, layer, costs) && !block.contains(p) }
        if var path = t.motion?.path, let first = path.first, first.chebyshev(to: here) == 1, ok(first),
           path.last.map({ $0.chebyshev(to: goal) <= 1 }) == true {
            path.removeFirst()
            t.motion = path.isEmpty ? nil : Motion(path: path)
            return first
        }
        let found = RFMapPathFinder().path(on: layer, terrains: ctx.content.terrains, from: here, to: goal,
                                           blocked: block.subtracting([here]))
        if var steps = found {
            if steps.first == here { steps.removeFirst() }
            if let first = steps.first, ok(first) {
                steps.removeFirst()
                t.motion = steps.isEmpty ? nil : Motion(path: steps)
                return first
            }
        }
        t.motion = nil
        // 道が無い: 近づけるだけ近づく(灯りの縁で止まる)
        let d0 = here.chebyshev(to: goal)
        let best = here.neighbors8.filter(ok).min { a, b in
            let da = a.chebyshev(to: goal), db = b.chebyshev(to: goal)
            return da != db ? da < db : a.manhattan(to: goal) < b.manhattan(to: goal)
        }
        guard let best, best.chebyshev(to: goal) < d0 else { return nil }
        return best
    }

    // MARK: 罠

    /// 罠を踏んだら倒す。群れが残っていれば true。
    static func springTraps(_ id: EntityID, at pos: WorldPoint, _ ctx: inout StepContext) -> Bool {
        guard var t = ctx.world.combat.threats[id] else { return false }
        for (p, cap) in structures("trap", ctx) where p.covers(pos) && !ctx.world.combat.sprungTraps.contains(p.id) {
            let n = min(cap, t.count)
            let each = max(1, t.hp / max(1, t.count))
            let rec = recordKills(t, n, actor: nil, place: pos, inputs: [p.origin], holder: .base, &ctx)
            ctx.world.combat.sprungTraps.insert(p.id)
            ctx.emit(.trapSprung(placement: p.id, record: rec))
            t.count -= n
            t.hp = max(0, t.hp - each * n)
            if t.count <= 0 || t.hp <= 0 {
                remove(id, &ctx, lastRecord: rec)
                return false
            }
            ctx.world.combat.threats[id] = t
        }
        return true
    }

    // MARK: 倒す・消える・奪う

    /// 倒した記録(1 件に数をまとめる)と、倒した分の獲物。
    @discardableResult
    static func recordKills(_ t: ThreatState, _ n: Int, actor: PersonID?, place: WorldPoint, inputs: [ProvenanceID],
                            holder: HolderID, _ ctx: inout StepContext) -> ProvenanceID {
        let d = ctx.content.enemies[t.kind]
        let rec = ctx.record(.defeated, .enemy(t.kind, t.id), actor: actor, place: place, inputs: inputs,
                             tags: Set(d?.tags ?? []))
        if n > 1 { ctx.world.ledger.update(rec) { $0.count = n } }
        ctx.world.combat.kills[t.kind, default: 0] += n
        if ctx.world.clock.phase != .day { ctx.world.combat.night.kills += n }
        for _ in 0..<n {
            for y in d?.drops ?? [] {
                let got: Int = ctx.random(.combat) { r in
                    if let bp = y.basisPoints, r.int(below: 10_000) >= bp { return 0 }
                    return r.int(in: min(y.min, y.max)...max(y.min, y.max))
                }
                guard got > 0 else { continue }
                if let m = y.matter {
                    ctx.addStock(.matter(m), got, to: holder, origin: rec)
                } else if let i = y.item {
                    ctx.addStock(.item(i), got, to: holder, origin: rec)
                }
            }
        }
        return rec
    }

    /// 群れが消える(全部倒れた・帰った)。巣の守りが全部倒れたら巣が壊れる。
    static func remove(_ id: EntityID, _ ctx: inout StepContext, lastRecord: ProvenanceID?) {
        guard let t = ctx.world.combat.threats.removeValue(forKey: id) else { return }
        ctx.changes.mark(.combat)
        guard case .guardNest(let poi) = t.intent, let lastRecord else { return }
        let kind = ctx.world.map.layers[.surface]?.pois[poi]?.kind ?? ""
        let rec = ctx.record(.defeated, .poi(kind, poi), place: t.position, inputs: [lastRecord],
                             tags: Set(ctx.content.enemies[t.kind]?.nestTags ?? []))
        var n = ctx.world.combat.nests[poi] ?? NestState()
        n.destroyed = rec
        n.guardThreat = nil
        ctx.world.combat.nests[poi] = n
        ctx.emit(.nestDestroyed(poi: poi, record: rec))
    }

    /// 蓄えを奪って帰る。
    static func steal(_ id: EntityID, at target: WorldPoint, cause: ProvenanceID?, _ ctx: inout StepContext) {
        guard let t = ctx.world.combat.threats[id] else { return }
        var took: [ItemID: Int] = [:]
        for ing in ctx.content.enemies[t.kind]?.steals ?? [] {
            let want = ing.quantity * t.count
            let have = ctx.world.inventory.entries(.base).filter(ing.matches).reduce(0) { $0 + $1.quantity }
            let n = min(want, have)
            guard n > 0, ctx.takeStock(n, from: .base, where: ing.matches) != nil else { continue }
            took[ing.item ?? "matter", default: 0] += n
        }
        if !took.isEmpty {
            var detail: [String: Value] = [:]
            for (k, v) in took { detail[k.rawValue] = .int(Int64(v)) }
            let rec = ctx.record(.raided, .enemy(t.kind, t.id), place: target, inputs: cause.map { [$0] } ?? [],
                                 detail: detail)
            for (k, v) in took { ctx.world.combat.night.stolen[k, default: 0] += v }
            ctx.emit(.raided(threat: id, record: rec))
        }
        remove(id, &ctx, lastRecord: nil)
    }
}
