import RFContent
import RFKernel
import RFRules
import RFWorld

/// 研究・スキル・解禁(CORE-13)。研究机に付いた仲間が昼の間に進める、研究パッケージの完了で解禁と効果、
/// スキル(道筋を増やす選択)。
///
/// 書いてよい切れ端: research。乱数の流れ: .research。受けるコマンド: .research(...)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct ResearchSystem: SimSystem {
    public let name = "research"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
