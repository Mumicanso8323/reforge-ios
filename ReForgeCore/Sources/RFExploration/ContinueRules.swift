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
/// 3. それも無ければ、起点(from)から半径以内の、同じ行為が採れて、いま見えている(知っている)マス。歩いて移る。
/// 4. どれも無ければ nil(止まる)。
/// 候補が複数なら (歩く距離, y, x) の小さい順の 1 つ。歩く距離は、いる所(standing)からのチェビシェフ距離で数える
/// (経路は RFCrew の持ち物で、ここからは引かない。平らな所では歩数と同じ)。
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
        // 3. 起点から半径以内(いま見えている所だけ)
        for dy in -radius...radius {
            for dx in -radius...radius {
                consider(GridPoint(from.point.x + dx, from.point.y + dy), layer: from.layer, reachOnly: false)
            }
        }
        return best?.at
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
