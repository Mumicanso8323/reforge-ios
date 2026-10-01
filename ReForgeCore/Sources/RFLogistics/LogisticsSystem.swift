import RFContent
import RFKernel
import RFRules
import RFWorld

/// 運搬(CORE-04)。離れたモジュールの間を仲間が実際に歩いて運ぶ(1 人 1 日の量・距離で落ちる)。
/// 流量とボトルネックの集計。電力網(R2)。
///
/// 書いてよい切れ端: logistics。乱数の流れ: .logistics。受けるコマンド: .logistics(...)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct LogisticsSystem: SimSystem {
    public let name = "logistics"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
