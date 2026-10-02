import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 続けて採る(PT-B1)の「次の場所」を選ぶ純関数。世界を変えない。乱数を使わない。
///
/// 順番(決定的):
/// 1. 同じマス(current)でまだ採れる(回数の上限・クールダウンが残る)なら、同じマス。
/// 2. 採れないなら、手の届く所(いまの届く距離)にある、同じ行為が採れるマス。
/// 3. それも無ければ、起点(from)から歩いて半径(歩数)以内の、同じ行為が採れて、いま見えている(知っている)マス。歩いて移る。
///    歩数は RFMap の Pathfinder で数える。川の向こうなど届かないマスと、回り道が半径を越えるマスは外す。
/// 4. どれも無ければ nil(止まる)。
/// 候補が複数なら (歩数, y, x) の小さい順の 1 つ。1・2 は歩かない所なので、距離はチェビシェフ距離のまま。
public enum ContinueRules {
    public static let defaultRadius = 3

    /// - Parameters:
    ///   - from: 半径の起点。ノアはいる所、仲間は配属の時の場所。
    ///   - current: いま採っている(いた)マス。
    ///   - standing: 歩いている人のいる所(届くか・歩く距離はここから数える)。nil なら from。
    public static func next(interaction def: InteractionDef, from: WorldPoint, world w: WorldState, content: ContentDB,
                            current: WorldPoint? = nil, standing: WorldPoint? = nil) -> WorldPoint? {
        let stand = standing ?? from
        if let c = current, canGather(def, at: c, world: w, content: content, requireKnown: false) { return c }
        let radius = max(0, def.continueRadius ?? defaultRadius)
        var best: (d: Int, y: Int, x: Int, at: WorldPoint)?
        func consider(_ p: GridPoint, layer: LayerID, reachOnly: Bool) {
            let at = WorldPoint(layer, p)
            guard canGather(def, at: at, world: w, content: content, requireKnown: !reachOnly) else { return }
            if reachOnly {
                guard case .success(let t) = Interactions.resolve(def, at: at, world: w, content: content),
                      Interactions.inReach(stand, t) else { return }
            }
            let d = stand.layer == layer ? stand.point.chebyshev(to: p) : Int.max
            if best == nil || (d, p.y, p.x) < (best!.d, best!.y, best!.x) { best = (d, p.y, p.x, at) }
        }
        // 2. 手の届く所
        let r = Interactions.reach
        for dy in -r...r {
            for dx in -r...r { consider(GridPoint(stand.point.x + dx, stand.point.y + dy), layer: stand.layer, reachOnly: true) }
        }
        if let b = best { return b.at }
        // 3. 起点から歩いて半径(歩数)以内の、いま見えている所だけ。歩数は経路で数える
        var router = Router(world: w, content: content, layer: from.layer)
        var walk: (steps: Int, y: Int, x: Int, at: WorldPoint)?
        for dy in -radius...radius {
            for dx in -radius...radius {
                let p = GridPoint(from.point.x + dx, from.point.y + dy)
                let at = WorldPoint(from.layer, p)
                guard canGather(def, at: at, world: w, content: content, requireKnown: true),
                      let n = router.steps(from: from.point, to: p), n <= radius else { continue }
                if walk == nil || (n, p.y, p.x) < (walk!.steps, walk!.y, walk!.x) { walk = (n, p.y, p.x, at) }
            }
        }
        return walk?.at
    }

    /// 歩数を数える(RFCrew の PathPlanner と同じ規則: 見ていないマスは平地と仮定・置いたモジュールは通れない)。
    struct Router {
        let world: WorldState
        let layerID: LayerID
        let costs: MoveCostTable
        let workspace = PathWorkspace()
        let blocked: Set<GridPoint>
        let known: GridBitset?

        init(world w: WorldState, content: ContentDB, layer: LayerID) {
            world = w
            layerID = layer
            costs = MoveCostTable(terrains: content.terrains)
            known = w.knowledge.mapKnown[layer]
            var b = Set<GridPoint>()
            for id in w.placements.sortedIDs {
                guard let p = w.placements.items[id], p.at.layer == layer, case .module = p.kind else { continue }
                for o in p.footprint { b.insert(p.at.point + o) }
            }
            blocked = b
        }

        /// from → 行き先のマス(通れなければ隣の 8 マスのうち一番近く着けるところ)の歩数。届かなければ nil。
        mutating func steps(from: GridPoint, to goal: GridPoint) -> Int? {
            guard let layer = world.map[layerID] else { return nil }
            if goal == from { return 0 }
            let terrain = layer.terrain
            let blocked = self.blocked.subtracting([from])
            let known = self.known
            func route(_ g: GridPoint) -> Int? {
                let outcome = Pathfinder.route(size: layer.size, from: from, to: g, costs: costs, options: .tap,
                                               workspace: workspace) { p in
                    if blocked.contains(p) { return .impassable }
                    if known?[p] != true { return .assumed(.plain) }
                    guard let b = terrain.biome(at: p) else { return .impassable }
                    return .known(b)
                }
                return outcome.path?.steps.count
            }
            func standable(_ p: GridPoint) -> Bool {
                guard layer.size.contains(p), !blocked.contains(p) else { return false }
                if known?[p] != true { return true }
                guard let b = terrain.biome(at: p) else { return false }
                return costs.cost(b) != nil
            }
            if standable(goal) { return route(goal) }
            return goal.neighbors8.filter(standable).compactMap(route).min()
        }
    }

    /// そのマスで、いま同じ行為が始められるか(届くかは見ない)。
    static func canGather(_ def: InteractionDef, at: WorldPoint, world w: WorldState, content: ContentDB,
                          requireKnown: Bool) -> Bool {
        guard let layer = w.map[at.layer], layer.size.contains(at.point) else { return false }
        if requireKnown, w.knowledge.mapKnown[at.layer]?[at.point] != true { return false }
        guard case .success(let target) = Interactions.resolve(def, at: at, world: w, content: content) else { return false }
        if let c = def.when, ConditionEvaluator.evaluatePure(c, world: w, content: content) != true { return false }
        if Interactions.checkLimits(def, at: at, target: target, world: w) != nil { return false }
        if let op = def.partOp, case .failure = Interactions.choosePart(op, at: at, target: target, world: w, content: content) {
            return false
        }
        return true
    }
}
