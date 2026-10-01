import RFContent
import RFKernel
import RFRules
import RFWorld

/// 脅威と戦闘(CORE-11)。夜の灯りの外から来る獣、柵・罠・見張り、1 次元の自動戦闘(6 マスの帯。
/// プレイヤーは方針と撤退だけ選ぶ)、武器の強さ = 素材の純度と硬さ、勝ち負けの結果と来歴。
///
/// 書いてよい切れ端: combat。乱数の流れ: .combat。受けるコマンド: .combat(...)。
/// 骨組み(中身は担当が入れる)。受け入れテストは docs/architecture/F-work-units.md。
public struct CombatSystem: SimSystem {
    public let name = "combat"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        .notMine
    }

    public func step(_ ctx: inout StepContext) {}

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}
