import RFContent
import RFKernel
import RFRules
import RFWorld

/// 拠点(CORE-14)。建造物を置き、建てる(仲間が手伝う)、シェルター・灯り・保管・収容、拠点グレード、人口。
///
/// 書いてよい切れ端: placements(建造物) / base。乱数の流れ: .base。受けるコマンド: .base(...)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct BaseSystem: SimSystem {
    public let name = "base"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
