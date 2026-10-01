/// マスの座標(層の中)。左上が (0,0)、x は右、y は下に増える。
public struct GridPoint: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public init(x: Int, y: Int) { self.init(x, y) }

    public var description: String { "(\(x),\(y))" }
    public static func < (a: Self, b: Self) -> Bool { (a.y, a.x) < (b.y, b.x) }

    public func moved(_ d: Direction, by n: Int = 1) -> GridPoint {
        GridPoint(x + d.dx * n, y + d.dy * n)
    }

    /// マンハッタン距離(運搬の距離など)。
    public func manhattan(to o: GridPoint) -> Int { abs(x - o.x) + abs(y - o.y) }
    /// チェビシェフ距離(視界の半径など)。
    public func chebyshev(to o: GridPoint) -> Int { max(abs(x - o.x), abs(y - o.y)) }

    public static func + (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: GridPoint, b: GridPoint) -> GridPoint { GridPoint(a.x - b.x, a.y - b.y) }

    /// ユークリッド距離の 2 乗(整数。視界の円の判定はこちらで)。
    public func distanceSquared(to o: GridPoint) -> Int {
        let dx = x - o.x, dy = y - o.y
        return dx * dx + dy * dy
    }

    /// ユークリッド距離(表示・生成用。世界状態の判定には distanceSquared を使う)。
    public func distance(to o: GridPoint) -> Double { Double(distanceSquared(to: o)).squareRoot() }

    /// 8 方向の隣(directions8 の順)。
    public var neighbors8: [GridPoint] { GridPoint.directions8.map { self + $0 } }

    /// 上下左右 → 斜めの順(経路探索の展開順を固定して決定的にする)。
    public static let directions8: [GridPoint] = [
        GridPoint(0, -1), GridPoint(0, 1), GridPoint(-1, 0), GridPoint(1, 0),
        GridPoint(-1, -1), GridPoint(1, -1), GridPoint(-1, 1), GridPoint(1, 1),
    ]
}

/// 層を含めた位置。層は将来足せる(地表 "layer.surface" から始める)。
public struct WorldPoint: Hashable, Codable, Sendable, CustomStringConvertible {
    public var layer: LayerID
    public var point: GridPoint

    public init(_ layer: LayerID, _ point: GridPoint) {
        self.layer = layer
        self.point = point
    }

    public var description: String { "\(layer)\(point)" }
}

extension LayerID {
    public static let surface: LayerID = "layer.surface"
}

public struct GridSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var count: Int { width * height }
    public func contains(_ p: GridPoint) -> Bool { p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }
    /// 行優先の添字。
    public func index(_ p: GridPoint) -> Int { p.y * width + p.x }
    public func point(at index: Int) -> GridPoint { GridPoint(index % width, index / width) }
}

public struct GridRect: Hashable, Codable, Sendable {
    public var origin: GridPoint
    public var size: GridSize

    public init(origin: GridPoint, size: GridSize) {
        self.origin = origin
        self.size = size
    }

    public func contains(_ p: GridPoint) -> Bool {
        p.x >= origin.x && p.y >= origin.y && p.x < origin.x + size.width && p.y < origin.y + size.height
    }
}

/// 向き(モジュールの向き・ノアの向き)。
public enum Direction: String, Codable, CaseIterable, Sendable {
    case north, east, south, west

    public var dx: Int {
        switch self {
        case .east: 1
        case .west: -1
        default: 0
        }
    }

    public var dy: Int {
        switch self {
        case .south: 1
        case .north: -1
        default: 0
        }
    }

    public var clockwise: Direction {
        switch self {
        case .north: .east
        case .east: .south
        case .south: .west
        case .west: .north
        }
    }

    public var opposite: Direction { clockwise.clockwise }
}

/// 地図の「既知」を持つビット列(層 1 枚ぶん)。巻き戻しで持ち越す。
public struct GridBitset: Codable, Equatable, Sendable {
    public let size: GridSize
    public private(set) var words: [UInt64]

    public init(size: GridSize) {
        self.size = size
        self.words = Array(repeating: 0, count: (size.count + 63) / 64)
    }

    public subscript(p: GridPoint) -> Bool {
        get {
            guard size.contains(p) else { return false }
            let i = size.index(p)
            return words[i >> 6] & (1 << UInt64(i & 63)) != 0
        }
        set {
            guard size.contains(p) else { return }
            let i = size.index(p)
            if newValue { words[i >> 6] |= 1 << UInt64(i & 63) } else { words[i >> 6] &= ~(1 << UInt64(i & 63)) }
        }
    }

    public var countSet: Int { words.reduce(0) { $0 + $1.nonzeroBitCount } }

    public mutating func formUnion(_ o: GridBitset) {
        precondition(o.size == size)
        for i in words.indices { words[i] |= o.words[i] }
    }
}
