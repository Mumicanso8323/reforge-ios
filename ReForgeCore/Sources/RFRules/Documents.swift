import RFContent
import RFKernel
import RFWorld

/// 記録から開ける資料(DocumentDef)の一覧。状態を持たず、条件をその場で評価する。
public enum Documents {
    /// いま記録に載っている資料(order → id の順)。確率の条件は「載らない」とみなす。
    public static func available(in w: WorldState, content: ContentDB) -> [DocumentDef] {
        content.documents.values
            .filter { ConditionEvaluator.evaluatePure($0.when, world: w, content: content) == true }
            .sorted { ($0.order ?? 0, $0.id) < ($1.order ?? 0, $1.id) }
    }
}
