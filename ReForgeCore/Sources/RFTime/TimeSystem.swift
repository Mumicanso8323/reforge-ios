import RFContent
import RFKernel
import RFRules
import RFWorld

/// 時間(CORE-08)。昼はリアルタイム、日没で止まり、夜は夜作業(行為ごとの時間)か寝る(夜明けまで一括)。
/// 内部の 1 日は昼 + 夜(既定 8 + 18 = 26 時間)。画面には時間数を出さない(認識の層が「妙に長い夜」とだけ言う)。
///
/// 骨組みとして最小の動きを入れてある(時計・日没・夜明け・寝る)。季節・天候(R2)は担当が足す。
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
            return .accepted(time: Self.untilDawn(clock, ctx.content.clock))
        }
    }

    public func step(_ ctx: inout StepContext) {
        let def = ctx.content.clock
        ctx.world.clock.now = ctx.world.clock.now + SimStep.duration
        let sinceDawn = (ctx.world.clock.now - ctx.world.clock.dayStartedAt).seconds
        if ctx.world.clock.phase == .day, sinceDawn >= def.dayGameSeconds {
            ctx.world.clock.phase = .dusk
            ctx.world.clock.realCarry = 0
            ctx.emit(.phaseChanged(to: .dusk, day: ctx.world.clock.day))
            ctx.changes.mark(.clock)
        }
        if sinceDawn >= def.dayGameSeconds + def.nightGameSeconds {
            ctx.world.clock.day += 1
            ctx.world.clock.phase = .day
            ctx.world.clock.dayStartedAt = ctx.world.clock.now
            ctx.emit(.dawn(day: ctx.world.clock.day))
            ctx.emit(.phaseChanged(to: .day, day: ctx.world.clock.day))
            ctx.changes.mark(.clock)
        }
    }

    /// 次の夜明けまでの時間。
    public static func untilDawn(_ c: ClockState, _ def: ClockDef) -> GameDuration {
        let end = c.dayStartedAt + GameDuration(seconds: def.dayGameSeconds + def.nightGameSeconds)
        return end - c.now
    }
}
