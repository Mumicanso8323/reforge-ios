import RFContent
import RFKernel
import RFMap
import RFWorld

/// 記録から開ける資料(DocumentDef)の一覧。状態を持たず、条件をその場で評価する。
public enum Documents {
    /// いま記録に載っている資料(order → id の順)。確率の条件は「載らない」とみなす。
    public static func available(in w: WorldState, content: ContentDB) -> [DocumentDef] {
        content.documents.values
            .filter { ConditionEvaluator.evaluatePure($0.when, world: w, content: content) == true }
            .sorted { ($0.order ?? 0, $0.id) < ($1.order ?? 0, $1.id) }
    }

    /// 資料のいまの段(本文・読める割合・修理の段階)。
    public struct Reading: Equatable, Sendable {
        public var body: TextID
        public var readablePermille: Int?
        /// 引いた修理の段階(段の無い資料は nil)。
        public var repairStage: Int?
    }

    public static func reading(_ d: DocumentDef, in w: WorldState) -> Reading {
        guard let st = d.stages else { return Reading(body: d.body, readablePermille: nil, repairStage: nil) }
        let n = RepairStage.of(poiKind: st.poiKind, part: st.part, in: w)
        let step = st.steps.sorted { $0.atLeast < $1.atLeast }.last { $0.atLeast <= n }
        return Reading(body: step?.body ?? d.body, readablePermille: step?.readablePermille, repairStage: n)
    }
}

/// 部品の修理の段階を世界の状態から引く(U19)。
public enum RepairStage {
    /// その種類の POI(どの層でも)の部品の修理の段階のうち最大。無ければ 0。
    public static func of(poiKind: POIKindID, part: String, in w: WorldState) -> Int {
        var best = 0
        for layer in w.map.layers.values {
            for (id, poi) in layer.pois where poi.kind == poiKind {
                best = max(best, w.exploration.poi[id]?.repair[part] ?? 0)
            }
        }
        return best
    }
}
