import RFContent
import RFKernel

/// The integer presentation values for a particular time-of-day step.
public struct TimeTint: Equatable, Hashable, Sendable {
    public var brightness: Int
    public var outside: Int
    public var tint: RGB
    public var strength: Int
    public var step: Int

    public init(brightness: Int, outside: Int, tint: RGB, strength: Int, step: Int) {
        self.brightness = brightness
        self.outside = outside
        self.tint = tint
        self.strength = strength
        self.step = step
    }

    /// The untinted treatment for chunks which are intentionally empty.
    public static let neutral = TimeTint(brightness: 1000, outside: 1000,
                                         tint: RGB(0, 0, 0), strength: 0, step: 0)

    /// Applies time brightness, then mixes in the lit tint.  Both operations
    /// deliberately use per-mille integer arithmetic.
    public func apply(_ base: RGB, brightness: Int) -> RGB {
        let b = max(0, brightness)
        let s = max(0, min(1000, strength))
        func component(_ base: UInt8, _ tint: UInt8) -> UInt8 {
            let lit = Int(base) * b / 1000
            let tintLit = Int(tint) * b / 1000
            let mixed = (lit * (1000 - s) + tintLit * s + 500) / 1000
            return UInt8(max(0, min(255, mixed)))
        }
        return RGB(component(base.r, tint.r), component(base.g, tint.g), component(base.b, tint.b))
    }
}

/// Pure, stepped interpolation for the map's time-of-day colour treatment.
public enum TimeOfDay {
    /// Seven and a half game minutes per step: 64 daytime and 144 nighttime steps.
    public static func step(minutes: Int) -> Int { max(0, minutes) * 2 / 15 }

    public static func mark(minutes: Int, _ def: TimeTintDef, clock: ClockDef = ClockDef()) -> TimeMark {
        key(at: steppedMinutes(minutes), in: usable(def, clock)).mark
    }

    public static func tint(minutes: Int, _ def: TimeTintDef, clock: ClockDef = ClockDef()) -> TimeTint {
        let keys = usable(def, clock)
        let at = steppedMinutes(minutes)
        let current = key(at: at, in: keys)
        guard let nextIndex = keys.firstIndex(where: { $0.at > at }),
              let currentIndex = keys.lastIndex(where: { $0.at <= at }),
              currentIndex + 1 == nextIndex
        else {
            return make(current, step: step(minutes: minutes))
        }
        let next = keys[nextIndex]
        let distance = next.at - current.at
        guard distance > 0 else { return make(current, step: step(minutes: minutes)) }
        // Half-minute units keep the 7.5-minute step exact (no truncation drift).
        let span = distance * 2
        let offset = max(0, min(span, step(minutes: minutes) * 15 - current.at * 2))
        func interpolate(_ a: Int, _ b: Int) -> Int {
            (a * (span - offset) + b * offset + span / 2) / span
        }
        return TimeTint(
            brightness: interpolate(current.brightness, next.brightness),
            outside: interpolate(current.outside ?? 150, next.outside ?? 150),
            tint: RGB(
                UInt8(interpolate(current.tint[0], next.tint[0])),
                UInt8(interpolate(current.tint[1], next.tint[1])),
                UInt8(interpolate(current.tint[2], next.tint[2]))),
            strength: interpolate(current.strength, next.strength),
            step: step(minutes: minutes))
    }

    /// Compatibility for content written before timeTint, derived from the
    /// content's own clock.  The short boundary segments preserve the old
    /// all-day/day and all-night values.
    public static func defaultDef(dayMinutes: Int, dayLengthMinutes: Int) -> TimeTintDef {
        let total = max(3, dayLengthMinutes)
        let edge = max(1, min(dayMinutes, total - 2))
        func key(_ at: Int, _ mark: TimeMark, _ brightness: Int) -> TimeTintKey {
            TimeTintKey(at: at, mark: mark, brightness: brightness, outside: 420, tint: [0, 0, 0], strength: 0)
        }
        return TimeTintDef(keys: [
            key(0, .day, 1000),
            key(edge - 1, .day, 1000),
            key(edge, .night, 750),
            key(total - 1, .night, 750),
            key(total, .dawn, 1000),
        ])
    }

    public static func defaultDef(_ clock: ClockDef) -> TimeTintDef {
        defaultDef(dayMinutes: clock.dayGameHours * 60,
                   dayLengthMinutes: (clock.dayGameHours + clock.nightGameHours) * 60)
    }

    /// The definition actually used for a content: its own timeTint, else the clock-derived default.
    public static func resolved(_ def: TimeTintDef?, clock: ClockDef) -> TimeTintDef {
        def ?? defaultDef(clock)
    }

    /// Positions of label changes within the daylight bar, in per-mille.
    /// This follows the same table that supplies `mark`, so the marker and
    /// label always change together.
    public static func dayBarDots(_ def: TimeTintDef, clock: ClockDef) -> [Int] {
        let dayMinutes = max(1, clock.dayGameHours * 60)
        var dots: [Int] = []
        var previous: TimeMark?
        for key in usable(def, clock) where key.at < dayMinutes {
            guard key.mark != previous else { continue }
            let dot = max(0, min(1000, key.at * 1000 / dayMinutes))
            if dots.last != dot { dots.append(dot) }
            previous = key.mark
        }
        if dots.first != 0 { dots.insert(0, at: 0) }
        if dots.last != 1000 { dots.append(1000) }
        return dots
    }

    public static func wordID(_ mark: TimeMark) -> TextID {
        switch mark {
        case .dawn: "ui.time.dawn"
        case .day: "ui.time.day"
        case .evening: "ui.time.evening"
        case .night: "ui.time.night"
        }
    }

    /// Whole minutes (floor) of the step head, used only to pick the key interval.
    private static func steppedMinutes(_ minutes: Int) -> Int { step(minutes: minutes) * 15 / 2 }

    private static func usable(_ def: TimeTintDef, _ clock: ClockDef) -> [TimeTintKey] {
        let keys = def.keys.filter { $0.tint.count == 3 }.sorted { $0.at < $1.at }
        return keys.count >= 2 ? keys : defaultDef(clock).keys
    }

    private static func key(at minutes: Int, in keys: [TimeTintKey]) -> TimeTintKey {
        keys.last(where: { $0.at <= minutes }) ?? keys[0]
    }

    private static func make(_ key: TimeTintKey, step: Int) -> TimeTint {
        TimeTint(brightness: key.brightness, outside: key.outside ?? 150,
                 tint: RGB(UInt8(key.tint[0]), UInt8(key.tint[1]), UInt8(key.tint[2])),
                 strength: key.strength, step: step)
    }
}
