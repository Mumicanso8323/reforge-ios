// RFKernel が入るまでの最小の乱数。b7 の ReForgeCore.SeededRandom と同じ SplitMix64 で、
// 同じ state からは同じ列が出る。設計担当が RFKernel に移すときはこの型を正とする。

/// 決定的な乱数(SplitMix64)。地図の生成と採掘の判定はすべてこれを使う。
public struct SeededRandom: RandomNumberGenerator, Codable, Equatable, Hashable, Sendable {
    public private(set) var state: UInt64

    public init(state: UInt64) {
        self.state = state
    }

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

    /// 範囲内の整数(両端を含む)。
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(below: range.upperBound - range.lowerBound + 1)
    }

    /// percent% の確率で true。
    public mutating func chance(percent: Int) -> Bool {
        int(below: 100) < percent
    }

    /// [0, 1) の実数(53 bit)。
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// [lo, hi) の実数。
    public mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// 親の乱数を進めずに、用途ごとに独立した列を作る(チャンクや層ごとの決定的な生成用)。
    public static func derived(from seed: UInt64, _ salts: Int...) -> SeededRandom {
        SeededRandom(state: derive(seed, salts))
    }

    /// 用途ごとの 64 bit の種(derived と同じ混ぜ方)。
    public static func derivedSeed(from seed: UInt64, _ salts: Int...) -> UInt64 {
        derive(seed, salts)
    }

    private static func derive(_ seed: UInt64, _ salts: [Int]) -> UInt64 {
        var h = seed
        for s in salts {
            h = mix(h ^ (UInt64(bitPattern: Int64(s)) &* 0x9E37_79B9_7F4A_7C15))
        }
        return mix(h)
    }

    /// SplitMix64 の仕上げ関数(64 bit の混ぜ合わせ)。
    @inlinable
    public static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
