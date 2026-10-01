import RFContent
import RFKernel
import RFRules
import RFWorld

/// ラインと手作業(CORE-04・05)。モジュールを置く(置ける場所の規則)・片付ける(材料は全部戻る)、
/// 隣接と向きでつながる、1 回の処理(RuleBook の 1 工程)、止まった理由、1 日あたりの入出、仲間が付くと速い、
/// 手作業(押し続けて 1 単位)、手作業から T1 への昇格、有限の品を使う/取っておく。
///
/// 書いてよい切れ端: placements(モジュール)。乱数の流れ: .production。受けるコマンド: .production(...)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct ProductionSystem: SimSystem {
    public let name = "production"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
