import RFContent
import RFKernel
import RFWorld

/// システム(RFTime・RFCrew…)の約束。本体(RFSim)は決まった順にこれを呼ぶ(C-engine-ui.md §2)。
///
/// - 状態を持たない(struct・不変)。状態はすべて ctx.world にある。
/// - 自分の切れ端だけを書く。他の切れ端を変えたいときは ctx.queue(コマンド)か ctx.emit(出来事)。
/// - 乱数は ctx.random(自分の流れ) だけ。壁時計・標準の乱数は使わない。
/// - 文章を作らない。ID と来歴だけを残す(文字にするのは RFPerception)。
public protocol SimSystem: Sendable {
    /// 名前(ログと順番の表示用)。
    var name: String { get }
    /// コマンドを受ける。自分の担当でなければ .notMine。
    func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult
    /// 固定ステップ 1 回(SimStep.gameSeconds)。昼のリアルタイムでも夜の一括でも同じ関数が呼ばれる。
    func step(_ ctx: inout StepContext)
    /// 他のシステムの出来事に反応する(同じステップの中で、出た順に)。
    func react(to event: DomainEvent, _ ctx: inout StepContext)
}

extension SimSystem {
    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult { .notMine }
    public func step(_ ctx: inout StepContext) {}
    public func react(to event: DomainEvent, _ ctx: inout StepContext) {}
}

/// コマンドの結果。
public enum CommandResult: Equatable, Sendable {
    case notMine
    /// 受けた。夜作業の行為は time に掛かる時間を返す(本体がその分のステップを進める)。
    case accepted(time: GameDuration?)
    case rejected(Rejection)

    public static let done = CommandResult.accepted(time: nil)
}

/// 断った理由。画面は reason を認識の層で文字にして足元カードに 1 行出す(ダイアログは出さない)。
public struct Rejection: Error, Codable, Equatable, Sendable {
    public var reason: TextID
    public var detail: [String: Value]

    public init(_ reason: TextID, detail: [String: Value] = [:]) {
        self.reason = reason
        self.detail = detail
    }
}
