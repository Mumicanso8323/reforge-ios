import RFContent
import RFKernel
import RFRules
import RFWorld

/// 探索(CORE-06)。マス・POI・置いた物に対する行為(InteractionDef: 漁る・汲む・掘る・観測する)、
/// 押し続ける行為、回数の上限、得られる物、有限の部品(残骸の区画)の取り外し・解体・作り直し、遺品、発見。
///
/// 書いてよい切れ端: exploration。乱数の流れ: .exploration。受けるコマンド: .exploration(.interact)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct ExplorationSystem: SimSystem {
    public let name = "exploration"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
