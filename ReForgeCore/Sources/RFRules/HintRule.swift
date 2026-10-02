import RFContent
import RFKernel
import RFWorld

/// 気配の規則(W-07・HNT-17)。答え(解放の条件)は飛ばさず、「ある」「名前がある」ことだけを先に見せる。
public enum HintRule {
    /// 半分の気配: 費用の品をすべて一度手にしていて(knowledge.heldItems)、拠点の蓄え+ノアの持ち物が
    /// 費用の合計の半分以上。物質で書いた材料は、いま 1 つでも持っていれば見たとみなす。
    /// 費用が空なら false(気配を出す理由が無い)。
    public static func halfway(cost: [Ingredient], world w: WorldState) -> Bool {
        let total = cost.reduce(0) { $0 + max(0, $1.quantity) }
        guard total > 0 else { return false }
        var have = 0
        for ing in cost {
            let n = ConditionEvaluator.stockCount(ing, w)
            if let i = ing.item {
                guard w.knowledge.heldItems.contains(i) else { return false }
            } else if n == 0 {
                return false
            }
            have += min(n, max(0, ing.quantity))
        }
        return have * 2 >= total
    }
}
