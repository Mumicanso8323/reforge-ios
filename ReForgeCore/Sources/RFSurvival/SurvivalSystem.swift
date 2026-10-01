import RFContent
import RFKernel
import RFRules
import RFWorld

/// 生存の圧(CORE-07)。食料・水の消費、空腹・脱水、精神力(外で減り、シェルターで戻る)、拠点全体の数値
/// (内訳と合計。見せない値を含む)、天候と季節(R2)。範囲の効果の bodyPerHour / statPerHour を足す。
///
/// 書いてよい切れ端: survival。乱数の流れ: .survival。受けるコマンド: .survival(.consume)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct SurvivalSystem: SimSystem {
    public let name = "survival"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
