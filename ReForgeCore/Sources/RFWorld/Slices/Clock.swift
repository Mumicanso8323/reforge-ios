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
    /// 最初の行為まで時計を止めている(W-01・OPEN-O2)。断られなかった最初のコマンドで false になり、戻らない。
    /// 止めている間は昼の実時間を進めない(Simulation.advance)。
    public var held: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey { case now, day, phase, dayStartedAt, realCarry, sleeping, held }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        now = try c.decode(GameTime.self, forKey: .now)
        day = try c.decode(Int.self, forKey: .day)
        phase = try c.decode(DayPhase.self, forKey: .phase)
        dayStartedAt = try c.decode(GameTime.self, forKey: .dayStartedAt)
        realCarry = try c.decode(Int64.self, forKey: .realCarry)
        sleeping = try c.decode(Bool.self, forKey: .sleeping)
        held = try c.decodeIfPresent(Bool.self, forKey: .held) ?? false
    }

    /// 夜明けからの経過。
    public var sinceDawn: GameDuration { now - dayStartedAt }
    /// 夜か(日没・夜作業・寝ている間)。視界の半径・夜だけの出来事が読む。
    public var isNight: Bool { phase != .day }
}
