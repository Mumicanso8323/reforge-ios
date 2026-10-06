import RFContent
import RFKernel
import RFRules
import RFWorld

/// 時間(CORE-08)。昼はリアルタイム、日没で止まり、夜は夜作業(行為ごとの時間)か寝る(夜明けまで一括)。
/// 内部の 1 日は昼 + 夜(既定 8 + 18 = 26 時間)。画面には時間数を出さない(認識の層が「妙に長い夜」とだけ言う)。
///
/// - 時計は固定ステップ(SimStep.gameSeconds)ごとに進む。昼の実時間をステップ数に直すのは本体(Simulation.advance)で、
///   端数は clock.realCarry に整数で繰り越す。だから昼をどんな刻みで進めても、寝るで一括にしても、同じ世界になる。
/// - 壁時計は読まない(アプリを閉じている間は進まない)。
/// - 季節(R2)は暦(survival.stats の wrap つきの値。RFSurvival が進める)から決める。ここは日と相の切り替えだけ。
///
/// 書いてよい切れ端: clock。乱数の流れ: .time(今は使わない)。受けるコマンド: .time。
public struct TimeSystem: SimSystem {
    public let name = "time"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .time(let c) = command else { return .notMine }
        let clock = ctx.world.clock
        switch c {
        case .startNightWork:
            guard clock.phase == .dusk else { return .rejected(Rejection("reason.time.not_dusk")) }
            ctx.world.clock.phase = .nightWork
            ctx.emit(.phaseChanged(to: .nightWork, day: clock.day))
            ctx.changes.mark(.clock)
            return .done
        case .sleep:
            guard clock.phase != .day else { return .rejected(Rejection("reason.time.still_day")) }
            ctx.world.clock.sleeping = true
            ctx.dropNoahSteer()
            ctx.changes.mark(.clock)
            return .accepted(time: Self.untilDawn(clock, ctx.content.clock))
        }
    }

    public func step(_ ctx: inout StepContext) {
        let def = ctx.content.clock
        ctx.world.clock.now = ctx.world.clock.now + SimStep.duration
        let sinceDawn = ctx.world.clock.sinceDawn.seconds
        if ctx.world.clock.phase == .day, sinceDawn >= def.dayGameSeconds {
            ctx.world.clock.phase = .dusk
            ctx.world.clock.realCarry = 0
            ctx.emit(.phaseChanged(to: .dusk, day: ctx.world.clock.day))
            ctx.changes.mark(.clock)
        }
        if sinceDawn >= Self.dayLength(def).seconds {
            ctx.world.clock.day += 1
            ctx.world.clock.phase = .day
            ctx.world.clock.sleeping = false
            ctx.world.clock.realCarry = 0
            ctx.world.clock.dayStartedAt = ctx.world.clock.now
            ctx.emit(.dawn(day: ctx.world.clock.day))
            ctx.emit(.phaseChanged(to: .day, day: ctx.world.clock.day))
            ctx.changes.mark(.clock)
        }
    }

    // MARK: - 問い合わせ(画面・他のシステム向け。時間数は返さない)

    /// 内部の 1 日の長さ(昼 + 夜)。
    public static func dayLength(_ def: ClockDef) -> GameDuration {
        GameDuration(seconds: def.dayGameSeconds + def.nightGameSeconds)
    }

    /// 次の夜明けまでの時間。
    public static func untilDawn(_ c: ClockState, _ def: ClockDef) -> GameDuration {
        (c.dayStartedAt + dayLength(def)) - c.now
    }

    /// 昼の残りの割合(千分率。昼の始め 1000 → 日没 0。夜は 0)。上の帯の「昼の残り」に使う(時間数は出さない)。
    public static func dayRemainingPermille(_ c: ClockState, _ def: ClockDef) -> Int {
        guard c.phase == .day, def.dayGameSeconds > 0 else { return 0 }
        let left = max(0, def.dayGameSeconds - c.sinceDawn.seconds)
        return Int(left * 1000 / def.dayGameSeconds)
    }

    /// 昼の残りの実秒(リアルタイムの昼の何秒ぶんか。切り上げ)。
    public static func dayRemainingRealSeconds(_ c: ClockState, _ def: ClockDef) -> Int {
        guard c.phase == .day, def.dayGameSeconds > 0 else { return 0 }
        let left = max(0, def.dayGameSeconds - c.sinceDawn.seconds)
        return Int((left * Int64(def.dayRealSeconds) + def.dayGameSeconds - 1) / def.dayGameSeconds)
    }
}
