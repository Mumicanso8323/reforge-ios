// RFKernel が入るまでの最小の座標と純度。設計担当が RFKernel に移すときはこの型を正とする。

/// マスの座標(層の中の x, y)。x は右、y は下に増える。
public struct GridPoint: Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public init(x: Int, y: Int) {
        self.init(x, y)
    }

    public static func + (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x - b.x, a.y - b.y) }

    /// 斜めも 1 と数える距離(8 方向に歩いたときの最少歩数)。
    public func chebyshev(to o: GridPoint) -> Int { max(abs(x - o.x), abs(y - o.y)) }

    /// ユークリッド距離。
    public func distance(to o: GridPoint) -> Double {
        let dx = Double(x - o.x), dy = Double(y - o.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// ユークリッド距離の 2 乗(整数)。
    public func distanceSquared(to o: GridPoint) -> Int {
        let dx = x - o.x, dy = y - o.y
        return dx * dx + dy * dy
    }

    /// 8 方向の隣。
    public var neighbors8: [GridPoint] {
        GridPoint.directions8.map { self + $0 }
    }

    /// 上下左右 → 斜めの順(経路探索の展開順を固定して決定的にする)。
    public static let directions8: [GridPoint] = [
        GridPoint(0, -1), GridPoint(0, 1), GridPoint(-1, 0), GridPoint(1, 0),
        GridPoint(-1, -1), GridPoint(1, -1), GridPoint(-1, 1), GridPoint(1, 1),
    ]

    public static func < (a: GridPoint, b: GridPoint) -> Bool { (a.y, a.x) < (b.y, b.x) }

    public var description: String { "(\(x),\(y))" }
}

/// 純度・含有率(万分率。10000 = 100%)。小数の誤差を持ち込まないために整数で持つ。
public struct Purity: Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var basisPoints: Int

    public init(basisPoints: Int) {
        self.basisPoints = basisPoints
    }

    public static func percent(_ p: Int) -> Purity { Purity(basisPoints: p * 100) }
    public static let zero = Purity(basisPoints: 0)
    public static let full = Purity(basisPoints: 10000)

    /// 0.0〜1.0 の割合。
    public var fraction: Double { Double(basisPoints) / 10000 }

    public static func < (a: Purity, b: Purity) -> Bool { a.basisPoints < b.basisPoints }

    public var description: String { "\(basisPoints)bp" }
}
