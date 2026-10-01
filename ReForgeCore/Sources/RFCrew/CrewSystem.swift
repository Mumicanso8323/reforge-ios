import RFContent
import RFKernel
import RFRules
import RFWorld

/// 人(CORE-09・17)。ノアと仲間は地図上の実体: 経路(RFMap)で歩き、配属(運搬・モジュール・見張り・建造・採取)を
/// 自分で実行し、夜は焚き火で話す。関係ランク、思想の傾きによる賛否(来歴の印 × 思想の重み)、記憶、
/// 配属の上書き(出来事・範囲の効果 drawTowardSource)、合流・離脱・死、視界と地図の既知(knowledge.mapKnown)。
///
/// 書いてよい切れ端: people。乱数の流れ: .crew。受けるコマンド: .crew(...)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct CrewSystem: SimSystem {
    public let name = "crew"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
