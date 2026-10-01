import RFContent
import RFKernel
import RFRules
import RFWorld

/// 特別な力(CORE-15)。R1 は伏線だけ(ノアの手ざわりで純度の見当が付く。性格・勘として流す。
/// 他の人と比べられる仕組みは R1 に置かない)。R3 で体系(名前は認識の層が解禁するまで出さない)。
///
/// 書いてよい切れ端: abilities。乱数の流れ: .abilities。受けるコマンド: .abilities(...)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct AbilitiesSystem: SimSystem {
    public let name = "abilities"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
