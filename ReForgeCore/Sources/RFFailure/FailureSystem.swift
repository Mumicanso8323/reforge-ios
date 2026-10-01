import RFContent
import RFKernel
import RFRules
import RFWorld

/// 失敗の判定(CORE-12)。コンテンツの失敗の規則(FailureRuleDef)を毎ステップ調べ、成り立ったら周回を失敗にする。
/// 期限も日数でなく値の規則として書く。餓死・脱水も規則(survival の日数の数値)で書く。
///
/// もう 1 つの役目: 巻き戻し・失って続けるは本体の外(Recovery)で世界を作り直すので、その直後の最初のステップで
/// `run.resumeNotice` を出来事 `runResumed` にして配る(仲間の「前にも」の一言・日誌の引き金)。
public struct FailureSystem: SimSystem {
    public let name = "failure"
    public init() {}

    public func step(_ ctx: inout StepContext) {
        guard ctx.world.run.isActive else { return }
        if let notice = ctx.world.run.resumeNotice {
            ctx.world.run.resumeNotice = nil
            let act = ctx.world.ledger.record(notice)?.act ?? .rewound
            ctx.emit(.runResumed(act: act, record: notice))
            ctx.changes.mark(.run)
        }
        if let (id, rule) = Self.firstHolding(&ctx) {
            let rec = ctx.record(.failed, .none, detail: ["cause": .string(rule.cause.rawValue),
                                                         "rule": .string(id.rawValue)])
            ctx.world.run.outcome = .failed(cause: rule.cause, record: rec)
            ctx.emit(.runFailed(cause: rule.cause))
            ctx.changes.mark(.run)
        }
    }

    /// いま成り立っている最初の失敗の規則(ID の昇順で調べる。決定的)。
    static func firstHolding(_ ctx: inout StepContext) -> (FailureRuleID, FailureRuleDef)? {
        for (id, rule) in ctx.content.failureRules.sorted(by: { $0.key < $1.key })
        where ConditionEvaluator.evaluate(rule.when, &ctx) {
            return (id, rule)
        }
        return nil
    }

    /// 乱数を進めずに、成り立っている規則を全部(4 択の「選べるか」の判定用。chance は成り立たない扱い)。
    public static func holdingRules(world: WorldState, content: ContentDB) -> [FailureRuleID] {
        content.failureRules.sorted(by: { $0.key < $1.key }).compactMap { id, rule in
            ConditionEvaluator.evaluatePure(rule.when, world: world, content: content) == true ? id : nil
        }
    }
}
