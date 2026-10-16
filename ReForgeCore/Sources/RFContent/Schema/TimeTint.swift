/// A named portion of the day for the presentation layer.  The names are keys,
/// not player-facing text; the app supplies the localized labels.
public enum TimeMark: String, Codable, CaseIterable, Equatable, Sendable {
    case dawn
    case day
    case evening
    case night
}

/// One control point for the time-of-day colour treatment.
public struct TimeTintKey: Codable, Equatable, Sendable {
    public var at: Int
    public var mark: TimeMark
    public var brightness: Int
    public var outside: Int?
    public var tint: [Int]
    public var strength: Int

    public init(at: Int, mark: TimeMark, brightness: Int, outside: Int? = nil,
                tint: [Int], strength: Int) {
        self.at = at
        self.mark = mark
        self.brightness = brightness
        self.outside = outside
        self.tint = tint
        self.strength = strength
    }
}

public struct TimeTintDef: Codable, Equatable, Sendable {
    public var keys: [TimeTintKey]

    public init(keys: [TimeTintKey]) { self.keys = keys }
}

/// The reserved-red rule is kept in RFContent because content validation must
/// not depend on RFPresent.  It is equivalent to hue 0 degrees +/- 18 degrees
/// and HSL saturation at least 50%, expressed entirely with integers.
public enum TimeTintPalette {
    public static func isReservedRed(r: Int, g: Int, b: Int) -> Bool {
        let high = max(r, max(g, b))
        let low = min(r, min(g, b))
        let delta = high - low
        guard delta > 0, r == high else { return false }
        let hueNearRed = 10 * abs(g - b) <= 3 * delta
        let lightSpan = 255 - abs(high + low - 255)
        let saturated = 2 * delta >= lightSpan
        return hueNearRed && saturated
    }

    public static func isReservedRed(_ rgb: [Int]) -> Bool {
        guard rgb.count == 3 else { return false }
        return isReservedRed(r: rgb[0], g: rgb[1], b: rgb[2])
    }
}
