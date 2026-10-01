/// 決定的な乱数(SplitMix64)。同じ状態からは常に同じ列が出る(REQ-04)。
/// 行動の確率判定はすべてこれを使い、標準ライブラリの乱数 API(実装が版で変わり得る)は使わない。
public struct SeededRandom: RandomNumberGenerator, Equatable, Sendable {
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

    /// percent% の確率で true。
    public mutating func chance(percent: Int) -> Bool {
        int(below: 100) < percent
    }
}
