/// 決定的な乱数(SplitMix64)。同じ状態からは常に同じ列が出る。
/// 確率の判定はすべてこれを使い、標準ライブラリの乱数 API(実装が版で変わり得る)は使わない。
public struct SeededRandom: RandomNumberGenerator, Equatable, Hashable, Codable, Sendable {
    public private(set) var state: UInt64

    public init(state: UInt64) { self.state = state }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<n の整数。
    public mutating func int(below n: Int) -> Int {
        precondition(n > 0, "n は正の値")
        return Int(next() % UInt64(n))
    }

    /// lo...hi の整数。
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(below: range.count)
    }

    /// percent% の確率で true。
    public mutating func chance(percent: Int) -> Bool { int(below: 100) < percent }

    /// 万分率の確率で true。
    public mutating func chance(basisPoints: Int) -> Bool { int(below: 10_000) < basisPoints }

    /// [0, 1) の実数(53 bit)。地図の生成(ノイズ)だけが使う。世界状態の判定には使わない。
    public mutating func unit() -> Double { Double(next() >> 11) * 0x1.0p-53 }
}

/// 乱数の流れの名前。システムごとに別の流れを使うので、あるシステムが引く回数を変えても
/// 他のシステムの結果は変わらない(並行実装でテストの期待値が互いに壊れない)。
public struct RandomStreamID: Hashable, Comparable, Codable, Sendable, CodingKeyRepresentable, ExpressibleByStringLiteral {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public init(stringLiteral value: String) { self.raw = value }
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public var codingKey: CodingKey { Key(stringValue: raw) }
    public init?<T: CodingKey>(codingKey: T) { raw = codingKey.stringValue }

    // 既定の流れ。システムを足すときはここに 1 行足す(名前を変えるとセーブの乱数がずれる)。
    public static let mapgen: Self = "mapgen"
    public static let time: Self = "time"
    public static let survival: Self = "survival"
    public static let invention: Self = "invention"
    public static let production: Self = "production"
    public static let logistics: Self = "logistics"
    public static let crew: Self = "crew"
    public static let exploration: Self = "exploration"
    public static let base: Self = "base"
    public static let combat: Self = "combat"
    public static let research: Self = "research"
    public static let abilities: Self = "abilities"
    public static let narrative: Self = "narrative"
    public static let failure: Self = "failure"
}

/// 世界が持つ乱数の流れの束。seed と流れの名前から初期状態が決まる。
public struct RandomStreams: Codable, Equatable, Sendable {
    public let seed: UInt64
    public private(set) var states: [RandomStreamID: UInt64]

    public init(seed: UInt64) {
        self.seed = seed
        self.states = [:]
    }

    /// 流れの初期状態。seed と名前の FNV-1a で決める(Swift の hashValue は起動ごとに変わるので使わない)。
    public static func initialState(seed: UInt64, stream: RandomStreamID) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in stream.raw.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        var r = SeededRandom(state: seed ^ h)
        return r.next()
    }

    /// 流れを 1 つ借りて使い、使った後の状態を書き戻す。
    public mutating func use<T>(_ stream: RandomStreamID, _ body: (inout SeededRandom) throws -> T) rethrows -> T {
        var rng = SeededRandom(state: states[stream] ?? Self.initialState(seed: seed, stream: stream))
        defer { states[stream] = rng.state }
        return try body(&rng)
    }
}
