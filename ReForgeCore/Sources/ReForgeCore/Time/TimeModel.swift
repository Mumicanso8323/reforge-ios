/// 時間の進み方(§5.3、REQ-09)。OPEN-01 の仮値はここの定数だけで差し替える。
///
/// ロジックは壁時計を読まない(REQ-13)。昼の経過は UI が tick(deltaSeconds:) で渡し、
/// アプリが非アクティブの間は呼ばれない(DEC-03)。
public protocol TimeModel: Sendable {
    /// 昼の間、UI のタイマーから呼ばれる。消費・生産を deltaSeconds 分進め、
    /// 昼の残り秒が 0 になったら phase を .dusk にする。
    func tick(_ s: GameState, deltaSeconds: Double, rng: inout SeededRandom) -> GameState
    /// 「寝る」。その日の残り全部をまとめて適用し、翌朝(.day、day+1、行動ポイント回復)にする。
    func sleep(_ s: GameState, rng: inout SeededRandom) -> GameState
    /// 「夜作業をする」。phase を .night にし、夜の行動ポイントを与える。
    func startNightWork(_ s: GameState) -> GameState
    /// 昼の実時間(秒)。
    var daySeconds: Double { get }
    /// 夜のゲーム内時間。消費・生産の配分に効く。
    var nightGameHours: Double { get }
    /// 1 日のゲーム内時間(この星では 26 時間)。
    var gameHoursPerDay: Double { get }
    var dayActionBudget: Int { get }
    var nightActionBudget: Int { get }
    var balance: Balance { get }
    func isAllowed(_ a: Action, in phase: Phase) -> Bool
}

extension TimeModel {
    public var gameSecondsPerDay: Int { Int((gameHoursPerDay * 3600).rounded()) }
    /// 昼のぶんのゲーム内秒(26 時間のうち夜を除いた時間)。
    public var dayGameSeconds: Int { gameSecondsPerDay - Int((nightGameHours * 3600).rounded()) }

    /// 昼の残り(0...1)。時計バーの表示用。
    public func dayRemainingFraction(_ s: GameState) -> Double {
        guard s.phase == .day, daySeconds > 0 else { return 0 }
        return max(0, min(1, 1 - s.dayElapsedSeconds / daySeconds))
    }

    /// 既定の「その時間帯にできること」(OPEN-01 (c) の仮値)。
    /// 昼: 全部。日没: 寝る(休む)だけ。夜: 作る・休む(携行食も「作る」の 1 つ)。
    public func isAllowed(_ a: Action, in phase: Phase) -> Bool {
        switch phase {
        case .day: true
        case .dusk: a == .rest
        case .night: !a.isOutdoor
        case .dawn: false
        }
    }

    /// 昼の経過を進める共通処理。
    func advanceDay(_ s: GameState, deltaSeconds: Double) -> GameState {
        guard s.isActive, s.phase == .day, deltaSeconds > 0, deltaSeconds.isFinite, daySeconds > 0 else { return s }
        var s = s
        let elapsed = min(daySeconds, s.dayElapsedSeconds + deltaSeconds)
        let ended = elapsed >= daySeconds
        let target = ended ? dayGameSeconds : min(dayGameSeconds, Int((elapsed / daySeconds * Double(dayGameSeconds)).rounded(.down)))
        s = DayFlow.advance(s, to: target, gameSecondsPerDay: gameSecondsPerDay, balance: balance)
        s.dayElapsedSeconds = elapsed
        if ended {
            s.phase = .dusk
            s.actionPointsLeft = 0
        }
        return s
    }

    /// 「寝る」の共通処理: その日の残りを一括適用 → 日を締める → 翌朝。
    func sleepThroughNight(_ s: GameState) -> GameState {
        guard s.isActive, s.phase != .dawn else { return s }
        var s = DayFlow.advance(s, to: gameSecondsPerDay, gameSecondsPerDay: gameSecondsPerDay, balance: balance)
        SurvivalResolver.closeDay(&s)
        let report = DawnReport(endedDay: s.day, tally: s.today,
                                daysWithoutFood: s.daysWithoutFood, daysWithoutWater: s.daysWithoutWater)
        s.lastDawn = report
        s.appendLog(.dawn(report), limit: balance.logLimit)
        s.day += 1
        s.phase = .day
        s.dayElapsedSeconds = 0
        s.dayProgressGameSeconds = 0
        s.actionPointsLeft = dayActionBudget
        s.actionBudget = dayActionBudget
        s.today = DayTally()
        return s
    }
}

/// DEC-04 の混合型: 昼はリアルタイム、夜は「夜作業」か「寝る」。MVP の既定。
public struct MixedDayNightTimeModel: TimeModel {
    public let daySeconds: Double
    public let nightGameHours: Double
    public let gameHoursPerDay: Double
    public let dayActionBudget: Int
    public let nightActionBudget: Int
    public let balance: Balance

    /// 既定値は OPEN-01 の仮値(昼 180 秒、夜 18 時間 / 1 日 26 時間、昼 10 行動、夜 4 行動)。
    public init(daySeconds: Double = 180, nightGameHours: Double = 18, gameHoursPerDay: Double = 26,
                dayActionBudget: Int = 10, nightActionBudget: Int = 4, balance: Balance = .mvp) {
        precondition(daySeconds > 0 && nightGameHours >= 0 && nightGameHours < gameHoursPerDay)
        self.daySeconds = daySeconds
        self.nightGameHours = nightGameHours
        self.gameHoursPerDay = gameHoursPerDay
        self.dayActionBudget = dayActionBudget
        self.nightActionBudget = nightActionBudget
        self.balance = balance
    }

    public func tick(_ s: GameState, deltaSeconds: Double, rng: inout SeededRandom) -> GameState {
        advanceDay(s, deltaSeconds: deltaSeconds)
    }

    public func sleep(_ s: GameState, rng: inout SeededRandom) -> GameState {
        sleepThroughNight(s)
    }

    public func startNightWork(_ s: GameState) -> GameState {
        guard s.isActive, s.phase == .dusk, s.hasFire, nightActionBudget > 0 else { return s }
        var s = s
        s.phase = .night
        s.actionPointsLeft = nightActionBudget
        s.actionBudget = nightActionBudget
        return s
    }
}

/// 比較・自動走行用: 昼に時計は無く(行動だけで進む)、夜作業もない。消費と生産は同じ関数で適用されるので、
/// 1 日を通した結果は MixedDayNightTimeModel と等価(§5.3)。
public struct DayTurnTimeModel: TimeModel {
    public let daySeconds: Double = 0
    public let nightGameHours: Double
    public let gameHoursPerDay: Double
    public let dayActionBudget: Int
    public let nightActionBudget: Int = 0
    public let balance: Balance

    public init(nightGameHours: Double = 18, gameHoursPerDay: Double = 26, dayActionBudget: Int = 10,
                balance: Balance = .mvp) {
        self.nightGameHours = nightGameHours
        self.gameHoursPerDay = gameHoursPerDay
        self.dayActionBudget = dayActionBudget
        self.balance = balance
    }

    public func tick(_ s: GameState, deltaSeconds: Double, rng: inout SeededRandom) -> GameState { s }

    public func sleep(_ s: GameState, rng: inout SeededRandom) -> GameState {
        sleepThroughNight(s)
    }

    public func startNightWork(_ s: GameState) -> GameState { s }
}
