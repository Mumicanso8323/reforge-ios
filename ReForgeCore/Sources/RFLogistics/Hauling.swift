import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld

/// 運び手が経路の物を運ぶ(量で進める。歩く絵は RFCrew が経路の path で描く)。
enum Hauling {
    /// 人の作業の速さ(千分率)。U4 の survival.work が境界に入ったらそこを読む。それまでは 1000。
    static func workSpeed(_ p: PersonID, _ w: WorldState) -> Int { 1000 }

    /// 経路に配属された一員(表示用。人の並び順)。
    static func dedicated(_ route: EntityID, _ w: WorldState) -> [PersonID] {
        w.people.members.filter { pid in
            guard let ps = w.people[pid] else { return false }
            return (ps.override?.assignment ?? ps.assignment) == .haul(route: route)
        }
    }

    /// いまこの経路で運んでいる人(activity == .carrying(route:))。専任も、配属の無い一員(共同の手)も、
    /// RFCrew が昼に経路を受け持たせて carrying にする。夜に眠っている人・戦っている人・上書きで連れて行かれた人は数えない。
    static func carriers(_ route: EntityID, _ w: WorldState) -> [PersonID] {
        w.people.order.filter { pid in
            guard let ps = w.people[pid], ps.presence.isMember, ps.presence.isAlive else { return false }
            return ps.activity == .carrying(route: route)
        }
    }

    /// 配属の無い一員(運搬が既定の役割。RFCrew が昼に経路へ割り振る)。見込みの表示用。
    static func pool(_ w: WorldState) -> [PersonID] {
        let live = Set(w.logistics.routes.keys)
        return w.people.members.filter { pid in
            guard pid != .noah, let ps = w.people[pid] else { return false }
            switch ps.override?.assignment ?? ps.assignment {
            case .idle: return true
            case .haul(let r): return !live.contains(r)
            default: return false
            }
        }
    }

    /// 1 人が昼のあいだ運び続けて HaulRules.perPersonPerDay 個になる速さで、運んでいる人の数だけ進める。
    static func step(_ ctx: inout StepContext) {
        let ids = ctx.world.logistics.sortedRouteIDs
        guard !ids.isEmpty else { return }
        let day = max(1, ctx.content.clock.dayGameSeconds)
        for id in ids {
            guard var r = ctx.world.logistics.routes[id] else { continue }
            let assigned = dedicated(id, ctx.world)
            if r.haulers != assigned { r.haulers = assigned }
            guard r.distance != nil else {
                ctx.world.logistics.routes[id] = r
                continue
            }
            let crewMilli = carriers(id, ctx.world).reduce(0) { $0 + workSpeed($1, ctx.world) }
            let waiting = pending(r, ctx.world, limit: 1) > 0
            if crewMilli == 0 {
                r.blocked = waiting ? HaulRules.noHaulers : nil
                ctx.world.logistics.routes[id] = r
                continue
            }
            r.blocked = nil
            guard waiting else {
                ctx.world.logistics.routes[id] = r
                continue
            }
            r.carryMicro += Int64(crewMilli) * HaulRules.perPersonPerDay * Int64(r.factorPermille) * SimStep.gameSeconds / day
            let n = Int(r.carryMicro / 1_000_000)
            ctx.world.logistics.routes[id] = r
            guard n > 0 else { continue }
            let moved = move(id, upTo: n, &ctx)
            guard var after = ctx.world.logistics.routes[id] else { continue }
            after.carryMicro = min(after.carryMicro - Int64(moved) * 1_000_000, 1_000_000)
            after.movedToday += moved
            ctx.world.logistics.routes[id] = after
        }
    }

    /// いま運べる数(limit で打ち切る)。
    static func pending(_ r: HaulRoute, _ w: WorldState, limit: Int) -> Int {
        switch (r.from, r.to) {
        case (.placement(let a), .placement(let b)):
            guard let am = w.placements.items[a]?.module, let bm = w.placements.items[b]?.module else { return 0 }
            var n = 0
            for e in am.output where n < limit { n += min(e.quantity, bm.room(for: e.stuff)) }
            return n
        case (.placement(let a), .base):
            return w.placements.items[a]?.module?.outputCount ?? 0
        case (.base, .placement(let b)):
            guard let bm = w.placements.items[b]?.module else { return 0 }
            return bm.auxShortfall.reduce(0) { $0 + min($1.missing, w.inventory.quantity($1.item, in: .base)) }
        case (.base, .base):
            return 0
        }
    }

    /// 経路の物を n 個まで運ぶ。運んだ数を返す。
    static func move(_ id: EntityID, upTo n: Int, _ ctx: inout StepContext) -> Int {
        guard let r = ctx.world.logistics.routes[id] else { return 0 }
        var moved = 0
        switch (r.from, r.to) {
        case (.placement(let a), .placement(let b)):
            guard let am = ctx.world.placements.items[a]?.module else { return 0 }
            for e in am.output where moved < n {
                guard let room = ctx.world.placements.items[b]?.module?.room(for: e.stuff), room > 0 else { continue }
                for piece in ModuleRuntime.take(min(room, n - moved), from: &ctx.world.placements.items[a]!.module!.output,
                                                where: { $0.stuff == e.stuff && $0.unique == e.unique }) {
                    ModuleRuntime.put(piece, into: &ctx.world.placements.items[b]!.module!.input)
                    moved += piece.quantity
                }
            }
            ctx.world.placements.items[a]?.module?.today.sent += moved
            ctx.world.placements.items[b]?.module?.today.received += moved
        case (.placement(let a), .base):
            let pieces = ModuleRuntime.take(n, from: &ctx.world.placements.items[a]!.module!.output, where: { _ in true })
            for piece in pieces {
                toBase(piece, &ctx)
                moved += piece.quantity
            }
            ctx.world.placements.items[a]?.module?.today.sent += moved
        case (.base, .placement(let b)):
            guard let bm = ctx.world.placements.items[b]?.module else { return 0 }
            for (item, missing) in bm.auxShortfall where moved < n {
                let k = min(missing, n - moved, ctx.world.inventory.quantity(item, in: .base))
                guard k > 0, let origins = ctx.takeStock(k, from: .base, where: { $0.unique == nil && $0.stuff == .item(item) })
                else { continue }
                ModuleRuntime.put(StockEntry(stuff: .item(item), quantity: k, origins: origins),
                                  into: &ctx.world.placements.items[b]!.module!.input)
                moved += k
            }
            ctx.world.placements.items[b]?.module?.today.received += moved
        case (.base, .base):
            break
        }
        if moved > 0 { ctx.changes.mark(.placements) }
        return moved
    }

    /// 蓄えへ入れる(物質は並びの最後の規則で冷える。生産の Placing.toBase と同じ規則)。
    static func toBase(_ e: StockEntry, _ ctx: inout StepContext) {
        var stuff = e.stuff
        if case .matter(let m) = stuff { stuff = .matter(ProcessChain.finish(m, rules: ctx.content.ruleBook).matter) }
        if e.unique != nil || e.durability != nil {
            var piece = e
            piece.stuff = stuff
            ctx.world.inventory.holders[.base, default: []].append(piece)
            ctx.changes.mark(.inventory)
            return
        }
        var rest = e.quantity
        for (o, k) in e.origins.sorted(by: { $0.key < $1.key }) where k > 0 && rest > 0 {
            let q = min(k, rest)
            ctx.addStock(stuff, q, to: .base, origin: o)
            rest -= q
        }
        if rest > 0 { ctx.addStock(stuff, rest, to: .base) }
    }
}

/// 画面とボットが読む運搬の見え方。
public enum LogisticsQueries {
    /// 経路の 1 日の流量の見込み(専任と、配属の無い一員を経路の数で等分した手、と距離から。昼のあいだ運ぶとして)。
    public static func perDay(_ route: EntityID, world w: WorldState) -> Int {
        guard let r = w.logistics.routes[route], let d = r.distance else { return 0 }
        let routes = max(1, w.logistics.routes.count)
        let crew = Hauling.dedicated(route, w).reduce(0) { $0 + Hauling.workSpeed($1, w) }
            + Hauling.pool(w).reduce(0) { $0 + Hauling.workSpeed($1, w) } / routes
        return HaulRules.perDay(crewMilli: crew, distance: d)
    }

    /// 間を空けて置いたときの見込み(照準の点線の横に出す): 距離・落ち・n 人で 1 日に運べる数。
    public static func preview(from a: GridPoint, to b: GridPoint, layer: LayerID = .surface, haulers: Int,
                               world w: WorldState, content: ContentDB) -> (distance: Int, perDay: Int)? {
        guard let l = w.map[layer] else { return nil }
        let d: Int
        if a == b { d = 0 } else {
            guard let steps = RFMapPathFinder().path(on: l, terrains: content.terrains, from: a, to: b, blocked: [])
            else { return nil }
            d = steps.count
        }
        return (d, HaulRules.perDay(crewMilli: haulers * 1000, distance: d))
    }
}
