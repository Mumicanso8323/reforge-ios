/// 地形ごとの 1 マスの移動コスト(千分の一の体力。10 = 体力 0.01)。nil の地形は通れない。
/// 斜めは 1.4 倍(端数は四捨五入)。原作 `MapScreen.GetMoveCost` の値: 整地 0.005・平地 0.01・森 0.02・岩場 0.03・水辺 0.02・遺跡 0.02。
public struct MoveCostTable: Codable, Equatable, Sendable {
    /// Biome の rawValue の順。
    private var straight: [Int?]

    public init(_ costs: [Biome: Int?]) {
        straight = Biome.allCases.map { costs[$0] ?? nil }
        precondition(straight.contains { $0 != nil }, "通れる地形が 1 つは要る")
        precondition(straight.allSatisfy { ($0 ?? 1) > 0 }, "コストは正の値")
    }

    public static let original = MoveCostTable([
        .cleared: 5, .plain: 10, .forest: 20, .rock: 30, .water: 20, .ruins: 20,
    ])

    /// まっすぐ入るときのコスト。
    public func cost(_ b: Biome) -> Int? { straight[Int(b.rawValue)] }

    /// 斜めに入るときのコスト。
    public func diagonalCost(_ b: Biome) -> Int? { cost(b).map { ($0 * 14 + 5) / 10 } }

    /// 通れない地形にする/コストを変える。
    public func with(_ b: Biome, _ c: Int?) -> MoveCostTable {
        var t = self
        t.straight[Int(b.rawValue)] = c
        return t
    }

    var minStraight: Int { straight.compactMap { $0 }.min()! }
    var minDiagonal: Int { Biome.allCases.compactMap { diagonalCost($0) }.min()! }

    /// 千分の一の体力を体力に直す。
    public static func stamina(_ milli: Int) -> Double { Double(milli) / 1000 }
}

/// 見つかった経路。
public struct MapPath: Codable, Equatable, Sendable {
    /// 歩くマス(出発点を含まず、目的地を含む)。
    public var steps: [GridPoint]
    /// 合計コスト(千分の一の体力)。
    public var cost: Int

    public init(steps: [GridPoint], cost: Int) {
        self.steps = steps
        self.cost = cost
    }

    /// 合計の体力コスト。
    public var stamina: Double { MoveCostTable.stamina(cost) }
}

/// 経路探索の条件。
public struct PathOptions: Sendable {
    /// 見たことのあるマス(既知・視界内)だけを通る。原作の「開放済みブロックのみ通行」に当たる。
    public var knownOnly: Bool
    /// 通れないマス(建物・柵など、呼び出し側の事情)。
    public var blocked: Set<GridPoint>
    /// これ以下のマス数の地図は全体を探す(最短が保証される)。
    public var fullSearchCellLimit: Int
    /// 大きい地図では出発点と目的地を囲む長方形をこれだけ広げた範囲で探す。
    public var windowMargin: Int

    public init(knownOnly: Bool = true, blocked: Set<GridPoint> = [],
                fullSearchCellLimit: Int = 512 * 512, windowMargin: Int = 64) {
        self.knownOnly = knownOnly
        self.blocked = blocked
        self.fullSearchCellLimit = fullSearchCellLimit
        self.windowMargin = windowMargin
    }
}

/// A* の経路探索(原作 `Pathfinder`)。8 方向、斜め 1.4 倍、地形ごとのコスト。
/// 原作は探索 500 ノードで打ち切っていたが、ここでは探索範囲を地図全体(大きい地図は窓)に限って最後まで探す。
public enum Pathfinder {
    /// 層の上で from から to への最小コストの経路。届かなければ nil。
    public static func findPath(in layer: MapLayer, from start: GridPoint, to goal: GridPoint,
                                costs: MoveCostTable = .original, options: PathOptions = PathOptions()) -> MapPath? {
        let terrain = layer.terrain
        let vis = layer.visibility
        let knownOnly = options.knownOnly
        let blocked = options.blocked
        return findPath(size: layer.size, from: start, to: goal, costs: costs, options: options) { p in
            if knownOnly && !vis.isKnown(p) { return nil }
            if !blocked.isEmpty && blocked.contains(p) { return nil }
            return terrain.biome(at: p)
        }
    }

    /// 地形を返す関数の上での経路探索(nil を返すマスは通れない)。
    public static func findPath(size: MapSize, from start: GridPoint, to goal: GridPoint,
                                costs: MoveCostTable = .original, options: PathOptions = PathOptions(),
                                biomeAt: (GridPoint) -> Biome?) -> MapPath? {
        guard size.contains(start), size.contains(goal) else { return nil }
        if start == goal { return MapPath(steps: [], cost: 0) }
        guard let gb = biomeAt(goal), costs.cost(gb) != nil else { return nil }

        // 探す範囲(窓)
        let lo: GridPoint, hi: GridPoint
        if size.cellCount <= options.fullSearchCellLimit {
            lo = GridPoint(0, 0)
            hi = GridPoint(size.width - 1, size.height - 1)
        } else {
            let m = options.windowMargin
            lo = GridPoint(max(0, min(start.x, goal.x) - m), max(0, min(start.y, goal.y) - m))
            hi = GridPoint(min(size.width - 1, max(start.x, goal.x) + m), min(size.height - 1, max(start.y, goal.y) + m))
        }
        let w = hi.x - lo.x + 1, h = hi.y - lo.y + 1
        let n = w * h
        @inline(__always) func idx(_ p: GridPoint) -> Int { (p.y - lo.y) * w + (p.x - lo.x) }
        @inline(__always) func pt(_ i: Int) -> GridPoint { GridPoint(lo.x + i % w, lo.y + i / w) }

        let minS = costs.minStraight, minD = costs.minDiagonal
        @inline(__always) func heuristic(_ p: GridPoint) -> Int {
            let dx = abs(p.x - goal.x), dy = abs(p.y - goal.y)
            let d = min(dx, dy)
            return (max(dx, dy) - d) * minS + d * minD
        }

        // 地形のコストを窓の中で 1 度だけ引く(-1 = 未取得、-2 = 通れない)
        var straightCost = [Int](repeating: -1, count: n)
        var g = [Int](repeating: Int.max, count: n)
        var parent = [Int32](repeating: -1, count: n)
        var closed = [Bool](repeating: false, count: n)
        var heap = MinHeap()

        let si = idx(start), gi = idx(goal)
        g[si] = 0
        heap.push(heuristic(start), si)

        while let (_, cur) = heap.pop() {
            if closed[cur] { continue }
            closed[cur] = true
            if cur == gi { break }
            let cp = pt(cur)
            let cg = g[cur]
            for (k, d) in GridPoint.directions8.enumerated() {
                let np = cp + d
                guard np.x >= lo.x, np.y >= lo.y, np.x <= hi.x, np.y <= hi.y else { continue }
                let ni = idx(np)
                if closed[ni] { continue }
                var sc = straightCost[ni]
                if sc == -1 {
                    sc = biomeAt(np).flatMap { costs.cost($0) } ?? -2
                    straightCost[ni] = sc
                }
                if sc == -2 { continue }
                let step = k >= 4 ? (sc * 14 + 5) / 10 : sc
                let ng = cg + step
                if ng < g[ni] {
                    g[ni] = ng
                    parent[ni] = Int32(cur)
                    heap.push(ng + heuristic(np), ni)
                }
            }
        }

        guard g[gi] != Int.max else { return nil }
        var steps: [GridPoint] = []
        var c = gi
        while c != si {
            steps.append(pt(c))
            c = Int(parent[c])
        }
        steps.reverse()
        return MapPath(steps: steps, cost: g[gi])
    }

    /// 経路の合計コスト(出発点から順に歩いたとき)。通れないマスや飛び石があれば nil。
    public static func cost(of steps: [GridPoint], from start: GridPoint, costs: MoveCostTable = .original,
                            biomeAt: (GridPoint) -> Biome?) -> Int? {
        var total = 0
        var prev = start
        for p in steps {
            let dx = abs(p.x - prev.x), dy = abs(p.y - prev.y)
            guard max(dx, dy) == 1, let b = biomeAt(p) else { return nil }
            guard let c = (dx == 1 && dy == 1) ? costs.diagonalCost(b) : costs.cost(b) else { return nil }
            total += c
            prev = p
        }
        return total
    }
}

/// (優先度, 番号) の二分ヒープ。同じ優先度は番号の小さい順(決定的)。
struct MinHeap {
    private var items: [(Int, Int)] = []

    var isEmpty: Bool { items.isEmpty }

    @inline(__always) private static func less(_ a: (Int, Int), _ b: (Int, Int)) -> Bool {
        a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
    }

    mutating func push(_ priority: Int, _ value: Int) {
        items.append((priority, value))
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if Self.less(items[i], items[p]) { items.swapAt(i, p); i = p } else { break }
        }
    }

    mutating func pop() -> (Int, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            let n = items.count
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < n && Self.less(items[l], items[m]) { m = l }
                if r < n && Self.less(items[r], items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}
