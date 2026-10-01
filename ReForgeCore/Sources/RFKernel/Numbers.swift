/// 世界状態の数値は整数で持つ(浮動小数の丸めが端末・版で変わってセーブや走行の再現が崩れないように)。

/// 純度。万分率(0...10000 = 0.00%...100.00%)。物質の担当の Purity をここに移した(形・意味は同じ)。
public struct Purity: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public static let scale = 10_000
    public let basisPoints: Int

    public static let zero = Purity(basisPoints: 0)
    public static let full = Purity(basisPoints: 10000)

    /// 範囲外は 0...10000 に丸める。
    public init(basisPoints: Int) { self.basisPoints = min(Self.scale, max(0, basisPoints)) }
    /// 百分率で作る(例: Purity(percent: 30) = 30.00%)。
    public init(percent: Int, hundredths: Int = 0) { self.init(basisPoints: percent * 100 + hundredths) }

    public static func + (a: Purity, b: Purity) -> Purity { Purity(basisPoints: a.basisPoints + b.basisPoints) }

    public var percent: Double { Double(basisPoints) / 100 }
    public var description: String {
        let r = basisPoints % 100
        return "\(basisPoints / 100).\(r < 10 ? "0" : "")\(r)%"
    }
    public static func < (a: Self, b: Self) -> Bool { a.basisPoints < b.basisPoints }

    /// 保存・コンテンツから読むときは範囲外を丸めずにエラーにする(壊れたデータで始めない)。
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let v = try c.decode(Int.self)
        guard (0...Self.scale).contains(v) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "純度は 0...10000 の万分率(\(v))")
        }
        self.init(basisPoints: v)
    }
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
