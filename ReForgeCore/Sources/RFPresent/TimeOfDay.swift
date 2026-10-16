import RFContent

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

    public static func mark(minutes: Int, _ def: TimeTintDef) -> TimeMark {
        key(at: steppedMinutes(minutes), in: usable(def)).mark
    }

    public static func tint(minutes: Int, _ def: TimeTintDef) -> TimeTint {
        let keys = usable(def)
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

    /// Compatibility for content written before timeTint.  The short boundary
    /// segments preserve the old all-day/day and all-night values.
    public static let defaultDef = TimeTintDef(keys: [
        TimeTintKey(at: 0, mark: .day, brightness: 1000, outside: 420, tint: [0, 0, 0], strength: 0),
        TimeTintKey(at: 479, mark: .day, brightness: 1000, outside: 420, tint: [0, 0, 0], strength: 0),
        TimeTintKey(at: 480, mark: .night, brightness: 750, outside: 420, tint: [0, 0, 0], strength: 0),
        TimeTintKey(at: 1559, mark: .night, brightness: 750, outside: 420, tint: [0, 0, 0], strength: 0),
        TimeTintKey(at: 1560, mark: .dawn, brightness: 1000, outside: 420, tint: [0, 0, 0], strength: 0),
    ])

    /// Whole minutes (floor) of the step head, used only to pick the key interval.
    private static func steppedMinutes(_ minutes: Int) -> Int { step(minutes: minutes) * 15 / 2 }

    private static func usable(_ def: TimeTintDef) -> [TimeTintKey] {
        let keys = def.keys.filter { $0.tint.count == 3 }.sorted { $0.at < $1.at }
        return keys.count >= 2 ? keys : defaultDef.keys
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
