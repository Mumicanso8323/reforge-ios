import RFKernel

/// 時計。持ち主: RFTime。
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

    public init() {}
}
