import RFKernel

/// 時計。持ち主: RFTime。
///
/// 内部の 1 日は昼 + 夜(長さはコンテンツの clock)。画面には時間数を出さない。
/// 画面が使うのは phase・day と、昼の残りの割合(RFTime の TimeSystem.dayRemainingPermille)だけ。
public struct ClockState: Codable, Equatable, Sendable {
    /// ゲーム開始からの経過。
    public var now: GameTime = .zero
    /// 何日目か(1 から)。
    public var day: Int = 1
    public var phase: DayPhase = .day
    /// いまの日が始まった時刻(夜明け)。
    public var dayStartedAt: GameTime = .zero
    /// 実時間の端数の繰り越し。単位は「実マイクロ秒 × 昼のゲーム秒」(整数で割り切るため。C-engine-ui.md §3)。
    public var realCarry: Int64 = 0
    /// 「寝る」を選んで夜明けまで一括で進めている間 true(夜明けで false)。仲間の動作・夜の出来事が読む。
    public var sleeping: Bool = false

    public init() {}

    /// 夜明けからの経過。
    public var sinceDawn: GameDuration { now - dayStartedAt }
    /// 夜か(日没・夜作業・寝ている間)。視界の半径・夜だけの出来事が読む。
    public var isNight: Bool { phase != .day }
}
