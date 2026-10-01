/// 世界状態の数値は整数で持つ(浮動小数の丸めが端末・版で変わってセーブや走行の再現が崩れないように)。

/// 純度。万分率(0...10000 = 0.00%...100.00%)。
public struct Purity: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public static let scale = 10_000
    public let basisPoints: Int

    public init(basisPoints: Int) { self.basisPoints = min(Self.scale, max(0, basisPoints)) }
    public init(percent: Int) { self.init(basisPoints: percent * 100) }

    public var percent: Double { Double(basisPoints) / 100 }
    public var description: String {
        let r = basisPoints % 100
        return "\(basisPoints / 100).\(r < 10 ? "0" : "")\(r)%"
    }
    public static func < (a: Self, b: Self) -> Bool { a.basisPoints < b.basisPoints }

    public init(from decoder: Decoder) throws { self.init(basisPoints: try decoder.singleValueContainer().decode(Int.self)) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(basisPoints)
    }
}

/// 千分の 1 単位の固定小数(体力・精神力・大気・関係の点など)。
public struct Milli: Hashable, Comparable, Codable, Sendable, AdditiveArithmetic, CustomStringConvertible {
    public var raw: Int64

    public init(raw: Int64) { self.raw = raw }
    public init(_ whole: Int) { self.raw = Int64(whole) * 1000 }

    public static let zero = Milli(raw: 0)
    public static func + (a: Self, b: Self) -> Self { Milli(raw: a.raw + b.raw) }
    public static func - (a: Self, b: Self) -> Self { Milli(raw: a.raw - b.raw) }
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }

    public var whole: Int { Int(raw / 1000) }
    public var description: String { "\(Double(raw) / 1000)" }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(Int64.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}
