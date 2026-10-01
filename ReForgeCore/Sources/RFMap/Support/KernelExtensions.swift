import RFKernel

// RFKernel の型に、地図だけが使う小道具を足す(大きさ・層の別名は公開、計算の小道具は RFMap の中だけ)。
// 座標の演算・距離・8 方向、SeededRandom.unit()、Purity.fraction は RFKernel のものを使う。

/// 地図の大きさ(RFKernel の GridSize)。
public typealias MapSize = GridSize
/// 層の ID(RFKernel の LayerID。地表は "layer.surface")。
public typealias MapLayerID = LayerID
/// 層つきの位置(RFKernel の WorldPoint)。
public typealias MapLocation = WorldPoint

extension GridSize {
    /// R1 の地図(96×96)。
    public static let r1 = GridSize(width: 96, height: 96)
    /// 原作の既定(10000×10000)。
    public static let original = GridSize(width: 10000, height: 10000)
    /// 中央のマス。
    public var center: GridPoint { GridPoint(width / 2, height / 2) }
    var cellCount: Int { count }
}

extension LayerID {
    /// 地下の深さ n の層(R2 以降)。
    public static func underground(_ depth: Int) -> LayerID { LayerID("layer.underground.\(depth)") }
}

extension SeededRandom {
    /// [lo, hi) の実数。
    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// 親の乱数を進めずに、用途ごとに独立した列を作る(チャンクや層ごとの決定的な生成用)。
    static func derived(from seed: UInt64, _ salts: Int...) -> SeededRandom {
        SeededRandom(state: derive(seed, salts))
    }

    /// 用途ごとの 64 bit の種(derived と同じ混ぜ方)。
    static func derivedSeed(from seed: UInt64, _ salts: Int...) -> UInt64 { derive(seed, salts) }

    private static func derive(_ seed: UInt64, _ salts: [Int]) -> UInt64 {
        var h = seed
        for s in salts { h = mix(h ^ (UInt64(bitPattern: Int64(s)) &* 0x9E37_79B9_7F4A_7C15)) }
        return mix(h)
    }

    /// SplitMix64 の仕上げ関数。
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - 保存は整数だけ

/// 保存の形には小数を入れない(RFKernel の Value が小数を受けないため)。
/// 地図の設定の実数は 100 万分の 1 を単位にした整数で書く(小数 6 桁までの値は往復で同じ値に戻る)。
enum Micro {
    static func encode(_ x: Double) -> Int64 { Int64((x * 1_000_000).rounded()) }
    static func decode(_ i: Int64) -> Double { Double(i) / 1_000_000 }
    /// 保存で往復しても変わらない値に丸める(計算で作る設定の値に使う)。
    static func quantize(_ x: Double) -> Double { decode(encode(x)) }
}

extension KeyedEncodingContainer {
    mutating func encodeMicro(_ x: Double, forKey k: Key) throws {
        try encode(Micro.encode(x), forKey: k)
    }

    mutating func encodeMicro(_ r: ClosedRange<Double>, forKey k: Key) throws {
        try encode([Micro.encode(r.lowerBound), Micro.encode(r.upperBound)], forKey: k)
    }
}

extension KeyedDecodingContainer {
    func decodeMicro(_ k: Key) throws -> Double {
        Micro.decode(try decode(Int64.self, forKey: k))
    }

    func decodeMicroRange(_ k: Key) throws -> ClosedRange<Double> {
        let v = try decode([Int64].self, forKey: k)
        guard v.count == 2, v[0] <= v[1] else {
            throw DecodingError.dataCorruptedError(forKey: k, in: self, debugDescription: "範囲は [下限, 上限]")
        }
        return Micro.decode(v[0])...Micro.decode(v[1])
    }
}
