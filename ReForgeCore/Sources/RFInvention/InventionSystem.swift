import RFContent
import RFKernel
import RFRules
import RFWorld

/// 発明(CORE-02)。試作(手持ちの材料を実際に使い、RFMatter の ProcessChain で計算)、実験ノート(所見・
/// 出典つきの書き留め・図鑑)、ヒント(仲間の関係ランクと条件)、ライン札。工程表は設計画面と同じ部品で開く。
///
/// 書いてよい切れ端: invention / notebook。乱数の流れ: .invention。受けるコマンド: .invention(.trial / .makeDesign / .discardDesign)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct InventionSystem: SimSystem {
    public let name = "invention"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
