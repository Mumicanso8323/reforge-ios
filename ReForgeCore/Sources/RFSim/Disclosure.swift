import RFContent
import RFKernel
import RFRules
import RFWorld

/// 表示の開示(W-01)。UIGateDef.latch の付いた門が一度成り立ったら、理由と一緒に
/// KnowledgeState.disclosed に記録する(以後は条件が崩れても開いたまま)。
/// 本体がコマンドとステップの後に呼ぶ。乱数を進めない(条件は純粋に評価する)ので決定性を崩さない。
/// 時計が止まっている間はステップが回らないので、開示も増えない(TEST-O2)。
public enum Disclosure {
    /// 新しく記録したら true。
    @discardableResult
    public static func record(_ world: inout WorldState, _ content: ContentDB) -> Bool {
        var changed = false
        for (id, g) in content.uiGates.sorted(by: { $0.key < $1.key }) {
            guard let kind = g.latch, world.knowledge.disclosed[id] == nil,
                  ConditionEvaluator.evaluatePure(g.when, world: world, content: content) == true else { continue }
            world.knowledge.disclosed[id] = kind
            changed = true
        }
        return changed
    }
}
