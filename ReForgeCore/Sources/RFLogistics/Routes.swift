import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld

/// 運搬の経路を引く・結ぶ・外す。
enum HaulRoutes {
    struct Key: Hashable {
        var from: HaulEndpoint
        var to: HaulEndpoint
    }

    /// 置き場所から要る自動の経路(決まった順)。
    static func desired(_ w: WorldState) -> [Key] {
        var out: [Key] = []
        let manualFrom = Set(w.logistics.routes.values.filter { $0.origin == .manual }.map(\.from))
        let manualTo = Set(w.logistics.routes.values.filter { $0.origin == .manual }.map(\.to))
        for id in w.placements.moduleIDs {
            guard let p = w.placements.items[id], let m = p.module else { continue }
            let me = HaulEndpoint.placement(id)
            let inBase = ModuleTopology.isInBase(id, in: w)
            // 出口: 直結が無く、手で結んだ経路も無ければ、札の次の段へ。次の段も無く離れていれば拠点へ。
            if ModuleTopology.directDownstream(of: id, in: w) == nil, !manualFrom.contains(me) {
                let next = ModuleTopology.nextSteps(of: id, in: w).filter { n in
                    ModuleTopology.directUpstreams(of: n, in: w).isEmpty
                }.min { a, b in
                    let pa = w.placements.items[a]!.at.point.manhattan(to: p.at.point)
                    let pb = w.placements.items[b]!.at.point.manhattan(to: p.at.point)
                    return (pa, a) < (pb, b)
                }
                if let n = next {
                    out.append(Key(from: me, to: .placement(n)))
                } else if !inBase {
                    out.append(Key(from: me, to: .base))
                }
            }
            // 入口: 段に入れる物が要る離れたモジュールへ、拠点から
            let needsAux = m.auxPerUnit.keys.contains { !m.freeItems.contains($0) }
            if needsAux, !inBase, !manualTo.contains(me) {
                out.append(Key(from: .base, to: me))
            }
        }
        return out
    }

    /// 自動の経路を置き場所に合わせて作り直す(同じ端の組の経路は ID・運びかけ・集計を引き継ぐ)。
    static func rebuild(_ ctx: inout StepContext) {
        let w = ctx.world
        func alive(_ e: HaulEndpoint) -> Bool {
            if case .placement(let id) = e { return w.placements.items[id] != nil }  // 建造物も始まりになる(P-12)
            return true
        }
        var keep: [EntityID: HaulRoute] = [:]
        var byKey: [Key: HaulRoute] = [:]
        for id in w.logistics.sortedRouteIDs {
            guard let r = w.logistics.routes[id], alive(r.from), alive(r.to) else { continue }
            if r.origin == .manual { keep[id] = r } else { byKey[Key(from: r.from, to: r.to)] = r }
        }
        for k in desired(w) {
            var r: HaulRoute
            if let old = byKey[k] {
                r = old
            } else {
                r = HaulRoute(id: ctx.world.newEntityID(), from: k.from, to: k.to, origin: .auto)
            }
            survey(&r, ctx.world, ctx.content)
            keep[r.id] = r
        }
        for (id, r) in keep where r.origin == .manual {
            var m = r
            survey(&m, ctx.world, ctx.content)
            keep[id] = m
        }
        ctx.world.logistics.routes = keep
        ctx.world.logistics.builtForTopology = ctx.world.placements.topologyVersion
        ctx.changes.mark(.placements)
    }

    /// 道のり(経路探索)と距離の落ちを測る。
    static func survey(_ r: inout HaulRoute, _ w: WorldState, _ content: ContentDB) {
        let a0 = r.from.placement.flatMap { w.placements.items[$0]?.at }
        let b0 = r.to.placement.flatMap { w.placements.items[$0]?.at }
        guard let a = ModuleTopology.point(of: r.from, near: b0?.point, in: w),
              let b = ModuleTopology.point(of: r.to, near: a0?.point ?? a.point, in: w),
              a.layer == b.layer, let layer = w.map[a.layer]
        else {
            r.distance = nil
            r.path = []
            r.factorPermille = 0
            r.blocked = HaulRules.unreachable
            return
        }
        if a.point == b.point {
            r.distance = 0
            r.path = [a.point]
        } else if let steps = RFMapPathFinder().path(on: layer, terrains: content.terrains, from: a.point, to: b.point,
                                                     blocked: []) {
            r.distance = steps.count
            r.path = [a.point] + steps
        } else {
            r.distance = nil
            r.path = []
            r.factorPermille = 0
            r.blocked = HaulRules.unreachable
            return
        }
        r.factorPermille = HaulRules.factor(distance: r.distance ?? 0, content.hauling)
        if r.blocked == HaulRules.unreachable { r.blocked = nil }
    }

    static func link(_ from: HaulEndpoint, _ to: HaulEndpoint, _ ctx: inout StepContext) -> CommandResult {
        guard from != to else { return .rejected(Rejection(HaulRules.sameEnds)) }
        // 始まりは置いた物(モジュールか、中に物を溜める建造物。P-12)か拠点、終わりはモジュールか拠点
        if case .placement(let id) = from, ctx.world.placements.items[id] == nil {
            return .rejected(Rejection(HaulRules.unknownEnd))
        }
        if case .placement(let id) = to, ctx.world.placements.items[id]?.module == nil {
            return .rejected(Rejection(HaulRules.unknownEnd))
        }
        if let r = ctx.world.logistics.routes.values.first(where: { $0.from == from && $0.to == to }) {
            ctx.world.logistics.routes[r.id]?.origin = .manual
        } else {
            var r = HaulRoute(id: ctx.world.newEntityID(), from: from, to: to, origin: .manual)
            survey(&r, ctx.world, ctx.content)
            ctx.world.logistics.routes[r.id] = r
        }
        // 手で結ぶと自動の経路が変わる(その出口・入口には自動で引かない)
        ctx.world.logistics.builtForTopology = -1
        ctx.changes.mark(.placements)
        return .done
    }

    static func unlink(_ id: EntityID, _ ctx: inout StepContext) -> CommandResult {
        guard let r = ctx.world.logistics.routes[id] else { return .rejected(Rejection(HaulRules.unknownRoute)) }
        guard r.origin == .manual else { return .rejected(Rejection(HaulRules.autoRoute)) }
        ctx.world.logistics.routes[id] = nil
        ctx.world.logistics.builtForTopology = -1
        ctx.changes.mark(.placements)
        return .done
    }
}
