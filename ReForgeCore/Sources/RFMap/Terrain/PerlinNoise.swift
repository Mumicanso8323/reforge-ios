import RFKernel

/// 2D Perlin ノイズ(原作 `PerlinNoise`)。256 の置換表を SeededRandom で混ぜる。出力は [0, 1]。
/// 原作は .NET の `Random(seed)` で表を混ぜていたが、端末と版で同じ列になるよう SplitMix64 に置き換えた。
public struct PerlinNoise: Equatable, Sendable {
    private let perm: [UInt8]   // 512

    public init(seed: UInt64) {
        var p = (0..<256).map { UInt8($0) }
        var rng = SeededRandom(state: seed)
        var i = 255
        while i > 0 {
            let j = rng.int(below: i + 1)
            p.swapAt(i, j)
            i -= 1
        }
        perm = p + p
    }

    /// (x, y) のノイズ。戻り値は [0, 1]。
    public func sample(_ x: Double, _ y: Double) -> Double {
        let fx = x.rounded(.down), fy = y.rounded(.down)
        let xi = Int(fx) & 255
        let yi = Int(fy) & 255
        let xf = x - fx
        let yf = y - fy
        let u = Self.fade(xf)
        let v = Self.fade(yf)

        let aa = Int(perm[Int(perm[xi]) + yi])
        let ab = Int(perm[Int(perm[xi]) + yi + 1])
        let ba = Int(perm[Int(perm[xi + 1]) + yi])
        let bb = Int(perm[Int(perm[xi + 1]) + yi + 1])

        let x1 = Self.lerp(Self.grad(aa, xf, yf), Self.grad(ba, xf - 1, yf), u)
        let x2 = Self.lerp(Self.grad(ab, xf, yf - 1), Self.grad(bb, xf - 1, yf - 1), u)
        let raw = Self.lerp(x1, x2, v)
        return min(1, max(0, raw * 0.5 + 0.5))
    }

    @inline(__always) private static func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    @inline(__always) private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + t * (b - a) }
    @inline(__always) private static func grad(_ hash: Int, _ x: Double, _ y: Double) -> Double {
        switch hash & 3 {
        case 0: return x + y
        case 1: return -x + y
        case 2: return x - y
        default: return -x - y
        }
    }
}
