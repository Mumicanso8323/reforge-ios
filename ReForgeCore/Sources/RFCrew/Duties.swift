import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 配属を実際の動きにする(MECH-05)。仲間は役割から「どこにいて、何をするか」を自分で決め、歩き、着いたら働く。
///
/// - 守る配属は override があればそちら(出来事・範囲の効果が上書きしている間はプレイヤーの配属に従わない)。
/// - プレイヤーが動かす人(ノア)は、上書きされても連れて行かれない。足取りが重くなるだけ(BEAT-22)。
/// - 戦っている人(activity = fighting で、その戦闘が続いている)は動かさない(RFCombat が戦闘を終えるまで)。
enum Duties {
    /// 行き先の形。
    struct Station: Equatable {
        var layer: LayerID
        /// 対象のマス(置いた物の占めるマス・地点 1 つ)。
        var target: [GridPoint]
        /// 対象のマスに立つか(false なら隣に立つ)。
        var standOn: Bool
        /// 着いたらすること。
        var activity: Activity
        /// 対象のマスからこれだけ離れていても着いたとみなす(ついて行く・見張りの範囲)。
        var slack: Int = 0
    }

    static func run(_ id: PersonID, _ ctx: inout StepContext, planner: inout PathPlanner) {
        guard let ps = ctx.world.people[id], ps.presence.isMember, let pos = ps.position else { return }
        let now = ctx.world.clock.now

        // 戦っている間は動かさない
        if case .fighting(let b) = ps.activity {
            if ctx.world.combat.battles[b] != nil { return }
            ctx.world.people[id]?.activity = .idle
        }
        // 話している・積み下ろし・届かなかったので待っている間
        if let until = ps.dwellUntil, now < until {
            return
        }
        if ps.dwellUntil != nil {
            ctx.world.people[id]?.dwellUntil = nil
            if case .talking = ps.activity { ctx.world.people[id]?.activity = .idle }
            if case .carrying = ps.activity, ps.motion == nil {
                // 積み下ろしが終わった: 向きを変える
                let leg = ps.haulLeg ?? .pickup
                ctx.world.people[id]?.haulLeg = leg == .pickup ? .dropoff : .pickup
            }
        }
        let fresh = ctx.world.people[id]!

        // プレイヤーが動かす人: 配属が無ければ何もしない(タップで歩く)。上書きでは連れて行かない
        let playerControlled = id == .noah
        let assignment: Assignment = playerControlled ? fresh.assignment : (fresh.override?.assignment ?? fresh.assignment)
        if playerControlled, case .idle = assignment {
            if let m = fresh.motion {
                let to = WorldPoint(pos.layer, m.goal ?? m.path.last ?? pos.point)
                if fresh.activity != .walking(to: to) { ctx.world.people[id]?.activity = .walking(to: to) }
            } else if case .walking = fresh.activity {
                ctx.world.people[id]?.activity = .idle
            } else if case .guarding = fresh.activity {
                ctx.world.people[id]?.activity = .idle
            } else if case .working = fresh.activity {
                ctx.world.people[id]?.activity = .idle
                ctx.world.people[id]?.workSpeed = nil
            }
            return
        }

        guard let station = station(for: id, assignment, fresh, &ctx) else {
            settle(id, activity: idleActivity(ctx.world), &ctx)
            return
        }
        // 着いているか
        if arrived(pos, station) {
            if fresh.motion != nil {
                ctx.world.people[id]?.motion = nil
            }
            arrive(id, station, &ctx)
            return
        }
        // 向かっている途中で、行き先が同じなら続ける
        if let m = fresh.motion, let g = m.goal, station.layer == pos.layer, stillGood(g, station) {
            let a = walkingActivity(station, to: WorldPoint(pos.layer, g))
            if fresh.activity != a { ctx.world.people[id]?.activity = a }
            return
        }
        // 運搬: 経路の道のり(HaulRoute.path)の上にいれば、その道をそのまま歩く(画面の点線と同じ道)
        if case .carrying(let route) = station.activity, let anchor = Walking.anchor(fresh, planner: &planner),
           let seg = HaulPath.segment(route, from: anchor, to: station.target[0], ctx.world, &planner), !seg.isEmpty {
            Walking.start(id, anchor: anchor, path: seg, goal: station.target[0], throughFog: false, &ctx)
            ctx.world.people[id]?.activity = station.activity
            ctx.world.people[id]?.workSpeed = nil
            return
        }
        // 経路を引く
        guard station.layer == pos.layer, let anchor = Walking.anchor(fresh, planner: &planner),
              let r = planner.approach(for: id, layer: pos.layer, from: anchor, target: station.target,
                                       standOn: station.standOn)
        else {
            // 届かない: しばらく待ってからまた探す
            ctx.world.people[id]?.motion = nil
            ctx.world.people[id]?.activity = .idle
            ctx.world.people[id]?.dwellUntil = now + CrewRules.retryDelay
            return
        }
        if r.path.isEmpty && anchor == pos.point {
            arrive(id, station, &ctx)
            return
        }
        Walking.start(id, anchor: anchor, path: r.path, goal: r.goal, throughFog: r.throughFog, &ctx)
        ctx.world.people[id]?.activity = walkingActivity(station, to: WorldPoint(pos.layer, r.goal))
        ctx.world.people[id]?.workSpeed = nil
    }

    /// 行き先へ歩いている間の動作(運搬は運んでいる間ずっと carrying。他は walking)。
    static func walkingActivity(_ s: Station, to: WorldPoint) -> Activity {
        if case .carrying = s.activity { return s.activity }
        return .walking(to: to)
    }

    static func isBusy(_ a: Activity) -> Bool {
        switch a {
        case .fighting, .talking, .interacting: true
        default: false
        }
    }

    static func idleActivity(_ w: WorldState) -> Activity { w.clock.phase == .day ? .idle : .sleeping }

    static func settle(_ id: PersonID, activity: Activity, _ ctx: inout StepContext) {
        guard let ps = ctx.world.people[id] else { return }
        if ps.motion != nil { return }  // 歩き終えてから
        if ps.activity != activity { ctx.world.people[id]?.activity = activity }
        if ps.workSpeed != nil { ctx.world.people[id]?.workSpeed = nil }
    }

    static func arrived(_ pos: WorldPoint, _ s: Station) -> Bool {
        guard pos.layer == s.layer else { return false }
        let d = s.target.map { $0.chebyshev(to: pos.point) }.min() ?? Int.max
        return s.standOn ? d <= s.slack : d <= max(1, s.slack)
    }

    /// 歩いている行き先が、まだその行き先として使えるか(対象が動いていない)。
    static func stillGood(_ goal: GridPoint, _ s: Station) -> Bool {
        let d = s.target.map { $0.chebyshev(to: goal) }.min() ?? Int.max
        return s.standOn ? d <= s.slack : d <= max(1, s.slack)
    }

    static func arrive(_ id: PersonID, _ s: Station, _ ctx: inout StepContext) {
        guard let ps = ctx.world.people[id] else { return }
        var activity = s.activity
        // 採取の進みは RFExploration が書く。同じ行為を続けているなら進みを消さない
        if case .interacting(let i, let at, _) = s.activity, case .interacting(let i2, let at2, _) = ps.activity,
           i == i2, at == at2 {
            activity = ps.activity
        }
        if ps.activity != activity {
            ctx.world.people[id]?.activity = activity
            ctx.changes.mark(.people)
        }
        if case .working(let e) = activity {
            let speed = WorkSpeed.permille(id, at: e, ctx.world, ctx.content)
            if ps.workSpeed != speed { ctx.world.people[id]?.workSpeed = speed }
        } else if ps.workSpeed != nil {
            ctx.world.people[id]?.workSpeed = nil
        }
        // 運搬: 端に着いたら積み下ろしを待つ(RFLogistics が arrived を見て積み下ろす)。
        // 歩いて着いたときは歩く方が arrived を出している。歩かずに着いた(端どうしが隣)ときはここで出す
        if case .carrying = activity, ps.dwellUntil == nil, let pos = ps.position {
            ctx.world.people[id]?.dwellUntil = ctx.world.clock.now + CrewRules.haulDwell
            let announced = ctx.events.contains { if case .arrived(id, _) = $0 { true } else { false } }
            if !announced { ctx.emit(.arrived(person: id, at: pos)) }
        }
    }

    /// 配属から行き先を決める。決められなければ nil(その場で待つ・夜は眠る)。
    static func station(for id: PersonID, _ a: Assignment, _ ps: PersonState, _ ctx: inout StepContext) -> Station? {
        let w = ctx.world
        guard let pos = ps.position else { return nil }
        switch a {
        case .idle:
            // 配属の無い仲間は、昼は運搬の共同の手(運搬が既定の役割。order.md §5.4)。夜は眠る。ノアは含めない
            guard id != .noah, w.clock.phase == .day, let route = HaulPath.sharedRoute(for: id, w) else { return nil }
            return haulStation(id, route, ps, &ctx)
        case .rest:
            if let shelter = nearestStructure(providing: "shelter", from: pos, w, ctx.content) {
                return Station(layer: pos.layer, target: footprint(shelter, w), standOn: true, activity: .sleeping,
                               slack: 1)
            }
            return Station(layer: pos.layer, target: [pos.point], standOn: true, activity: .sleeping)
        case .operate(let e), .build(let e):
            guard let p = w.placements.items[e] else {
                drop(id, &ctx)
                return nil
            }
            if case .build = a, !isUnderConstruction(p) {
                drop(id, &ctx)
                return nil
            }
            let standOn: Bool = if case .module = p.kind { false } else { true }
            return Station(layer: p.at.layer, target: footprint(e, w), standOn: standOn, activity: .working(at: e),
                           slack: standOn ? 1 : 0)
        case .guardArea(let center, let radius):
            if let s = interpose(id, center: center, guardRadius: radius, ps, w, ctx.content) { return s }
            return Station(layer: center.layer, target: [center.point], standOn: true,
                           activity: .guarding(center: center), slack: min(radius, 1))
        case .gather(let interaction, let at):
            return Station(layer: at.layer, target: [at.point], standOn: false,
                           activity: .interacting(interaction: interaction, at: at, progress: 0))
        case .follow(let other):
            guard let op = w.people[other], op.presence.isAlive, let opos = op.position else { return nil }
            // 範囲の効果で引かれているときは中心のすぐそばまで
            let slack = ps.override?.aura != nil ? 1 : CrewRules.followDistance
            return Station(layer: opos.layer, target: [opos.point], standOn: false, activity: idleActivity(w),
                           slack: slack)
        case .haul(let route):
            guard w.logistics.routes[route] != nil else {
                drop(id, &ctx)
                return nil
            }
            return haulStation(id, route, ps, &ctx)
        }
    }

    /// 運搬の行き先: 経路の道のりの端(通れるマス)。道のりが無ければ端の置いた物・拠点の蓄えのそば。
    static func haulStation(_ id: PersonID, _ route: EntityID, _ ps: PersonState, _ ctx: inout StepContext) -> Station? {
        let w = ctx.world
        guard let r = w.logistics.routes[route] else { return nil }
        let leg = ps.haulLeg ?? .pickup
        if ps.haulLeg == nil { ctx.world.people[id]?.haulLeg = .pickup }
        if let tiles = HaulPath.walkable(r, w, ctx.content), let end = leg == .pickup ? tiles.tiles.first : tiles.tiles.last {
            return Station(layer: tiles.layer, target: [end], standOn: true, activity: .carrying(route: route))
        }
        guard let end = endpoint(leg == .pickup ? r.from : r.to, w) else { return nil }
        return Station(layer: end.layer, target: end.cells, standOn: false, activity: .carrying(route: route))
    }

    /// 対象が消えた・建て終わった配属を外す(プレイヤーの配属を、仲間が自分で外す)。
    static func drop(_ id: PersonID, _ ctx: inout StepContext) {
        guard let ps = ctx.world.people[id] else { return }
        if ps.override != nil, ps.override?.aura == nil {
            ctx.world.people[id]?.override = nil
        } else {
            ctx.world.people[id]?.assignment = .idle
            ctx.world.people[id]?.haulLeg = nil
        }
        ctx.world.people[id]?.workSpeed = nil
        ctx.emit(.assigned(person: id, assignment: ctx.world.people.effectiveAssignment(id) ?? .idle))
        ctx.changes.mark(.people)
    }

    static func isUnderConstruction(_ p: Placement) -> Bool {
        if case .underConstruction = p.status { true } else { false }
    }

    /// 運搬の端の場所(置いた物ならその占めるマス、拠点の蓄えなら拠点の範囲の中心)。
    static func endpoint(_ e: HaulEndpoint, _ w: WorldState) -> (layer: LayerID, cells: [GridPoint])? {
        switch e {
        case .placement(let id):
            guard let p = w.placements.items[id] else { return nil }
            return (p.at.layer, footprint(id, w))
        case .base:
            guard let a = w.base.area else { return nil }
            return (.surface, [GridPoint(a.origin.x + a.size.width / 2, a.origin.y + a.size.height / 2)])
        }
    }

    static func footprint(_ e: EntityID, _ w: WorldState) -> [GridPoint] {
        guard let p = w.placements.items[e] else { return [] }
        return p.footprint.map { p.at.point + $0 }
    }

    static func nearestStructure(providing key: String, from pos: WorldPoint, _ w: WorldState, _ c: ContentDB) -> EntityID? {
        var best: (Int, EntityID)?
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id], p.at.layer == pos.layer, case .structure(let k) = p.kind,
                  !isUnderConstruction(p), (c.structures[k]?.provides[key] ?? 0) > 0 else { continue }
            let d = p.at.point.chebyshev(to: pos.point)
            if best == nil || d < best!.0 { best = (d, id) }
        }
        return best?.1
    }

    // MARK: 得意分野の振る舞い

    /// 見張りの途中で、敵と守る人の間に出る(PersonDef.behaviors の interpose。BEAT-19)。
    static func interpose(_ id: PersonID, center: WorldPoint, guardRadius: Int, _ ps: PersonState, _ w: WorldState,
                          _ c: ContentDB) -> Station? {
        for b in c.people[id]?.behaviors ?? [] {
            guard case .interpose(let protect, let radius) = b else { continue }
            let target = protect ?? .noah
            guard target != id, let tp = w.people[target]?.position, tp.layer == center.layer,
                  tp.point.chebyshev(to: center.point) <= guardRadius + radius else { continue }
            // 守る人に一番近い敵
            let threats = w.combat.threats.values
                .filter { $0.position.layer == tp.layer && $0.position.point.chebyshev(to: tp.point) <= radius }
                .sorted { ($0.position.point.chebyshev(to: tp.point), $0.id) < ($1.position.point.chebyshev(to: tp.point), $1.id) }
            guard let t = threats.first else { continue }
            let step = stepToward(tp.point, t.position.point)
            return Station(layer: tp.layer, target: [step], standOn: true, activity: .interposing(threat: t.id))
        }
        return nil
    }

    /// a から b へ 1 マス進んだマス(a == b なら a)。
    static func stepToward(_ a: GridPoint, _ b: GridPoint) -> GridPoint {
        GridPoint(a.x + (b.x - a.x).signum(), a.y + (b.y - a.y).signum())
    }
}

/// 付いた人の作業の速さ(order.md §5.6: 専門一致 +30%、関係ランク 3 以上 +10%。原作 PlacedModule.GetWorkerBonus)
/// + 思想と配属の向き(MECH-05: 思想が配属したときの速さに効く)。
enum WorkSpeed {
    static func permille(_ id: PersonID, at e: EntityID, _ w: WorldState, _ c: ContentDB) -> Int {
        guard let ps = w.people[id] else { return 1000 }
        var v = 1000
        if let need = specialty(of: e, w, c), (c.people[id]?.specialties ?? []).contains(need) {
            v += CrewRules.specialtyBonusPermille
        }
        if id != .noah, ps.relation.rank >= CrewRules.rankBonusAt { v += CrewRules.rankBonusPermille }
        let a = w.people.effectiveAssignment(id) ?? .idle
        let stance = Ideology.stance(ps.ideology, tags: AssignmentTags.tags(for: a, in: w), content: c)
        v += max(-CrewRules.ideologySpeedCap, min(CrewRules.ideologySpeedCap, stance * CrewRules.ideologySpeedPerPoint))
        // 距離の縛り(PersonDef.tether。U16): 縛る人から遠い間は働けない
        if let t = c.people[id]?.tether, !Tethers.holds(t, for: ps, w) { return 0 }
        return max(0, v)
    }

    /// 置いた物の専門(モジュール・建造物の specialty。古い建造物の定義は parameters の "specialty")。
    static func specialty(of e: EntityID, _ w: WorldState, _ c: ContentDB) -> String? {
        guard let p = w.placements.items[e] else { return nil }
        switch p.kind {
        case .module(let k): return c.modules[k]?.specialty
        case .structure(let k): return c.structures[k].flatMap { $0.specialty ?? $0.parameters?["specialty"]?.stringValue }
        }
    }
}

/// 運搬の道のり(RFLogistics の HaulRoute.path。端のマスを含む)を歩く。
enum HaulPath {
    /// 道のりのうち人が立てるマス(置いたモジュールのマス・通れない地形を除く)。つながっていなければ nil。
    static func walkable(_ r: HaulRoute, _ w: WorldState, _ c: ContentDB) -> (layer: LayerID, tiles: [GridPoint])? {
        let layer = r.from.placement.flatMap { w.placements.items[$0]?.at.layer }
            ?? r.to.placement.flatMap { w.placements.items[$0]?.at.layer } ?? .surface
        var blocked = Set<GridPoint>()
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id], p.at.layer == layer, case .module = p.kind else { continue }
            for o in p.footprint { blocked.insert(p.at.point + o) }
        }
        guard let l = w.map[layer] else { return nil }
        let costs = MoveCostTable(terrains: c.terrains)
        let tiles = r.path.filter { p in
            !blocked.contains(p) && l.biome(at: p).map { costs.cost($0) != nil } == true
        }
        guard !tiles.isEmpty else { return nil }
        for (a, b) in zip(tiles, tiles.dropFirst()) where a.chebyshev(to: b) != 1 { return nil }
        return (layer, tiles)
    }

    /// from(道のりの上のマス)から goal(道のりの端)までの、道のりに沿ったマスの並び(from を含まない)。
    /// from が道のりの上に無ければ nil(まず道のりまで経路探索で歩く)。
    static func segment(_ route: EntityID, from: GridPoint, to goal: GridPoint, _ w: WorldState,
                        _ planner: inout PathPlanner) -> [GridPoint]? {
        guard let r = w.logistics.routes[route], let (layer, tiles) = walkable(r, w, planner.content),
              let i = tiles.firstIndex(of: from), let j = tiles.firstIndex(of: goal), i != j else { return nil }
        let seg = i < j ? Array(tiles[(i + 1)...j]) : Array(tiles[j..<i].reversed())
        // 通れなくなったマス(後から置かれたモジュール)があれば使わない
        guard seg.allSatisfy({ planner.passableTruth($0, layer) }) else { return nil }
        return seg
    }

    /// 共同の手の受け持ち: 配属の無い仲間(ノアを除く・人の順)を、道のりのある経路(ID 順)へ順に割り振る。
    /// 運ぶ物が待っている経路(HaulRoute.waiting)があればそれだけに、1 本も無ければ全部の経路に均等に。
    static func sharedRoute(for id: PersonID, _ w: WorldState) -> EntityID? {
        let usable = w.logistics.sortedRouteIDs.filter { w.logistics.routes[$0].map { !$0.path.isEmpty } ?? false }
        let waiting = usable.filter { w.logistics.routes[$0]?.waiting == true }
        let routes = waiting.isEmpty ? usable : waiting
        guard !routes.isEmpty else { return nil }
        let hands = w.people.members.filter { pid in
            guard pid != .noah, let ps = w.people[pid], ps.position != nil, ps.override == nil else { return false }
            return ps.assignment == .idle
        }
        guard let k = hands.firstIndex(of: id) else { return nil }
        return routes[k % routes.count]
    }
}

/// 人の距離の縛り(PersonDef.tether。U16)。
enum Tethers {
    /// その人が縛る人から radius マス以内にいるか(どちらかが地図にいない・別の層なら false)。
    static func holds(_ t: Tether, for ps: PersonState, _ w: WorldState) -> Bool {
        guard let me = ps.position, let other = w.people[t.person]?.position, me.layer == other.layer else { return false }
        return me.point.chebyshev(to: other.point) <= t.radius
    }
}
