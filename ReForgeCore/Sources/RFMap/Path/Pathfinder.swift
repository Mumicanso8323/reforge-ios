import RFKernel

/// 地形ごとの 1 マスの移動コスト(千分の一の体力。10 = 体力 0.01)。表に無い地形は通れない。
/// 斜めは 1.4 倍(端数は四捨五入)。
/// 原作 `MapScreen.GetMoveCost` の値: 整地 0.005・平地 0.01・森 0.02・岩場 0.03・水辺 0.02・遺跡 0.02。
/// R1 の追加: 川の流れは通れない、浅瀬は 0.04。
public struct MoveCostTable: Codable, Equatable, Sendable {
    public private(set) var costs: [Biome: Int]

    public init(_ costs: [Biome: Int]) {
        precondition(!costs.isEmpty, "通れる地形が 1 つは要る")
        precondition(costs.values.allSatisfy { $0 > 0 }, "コストは正の値")
        self.costs = costs
    }

    public static let original = MoveCostTable([
        .cleared: 5, .plain: 10, .forest: 20, .rock: 30, .water: 20, .ruins: 20, .ford: 40,
    ])

    /// まっすぐ入るときのコスト。nil は通れない。
    public func cost(_ b: Biome) -> Int? { costs[b] }

    /// 斜めに入るときのコスト。
    public func diagonalCost(_ b: Biome) -> Int? { cost(b).map(Self.diagonal) }

    static func diagonal(_ c: Int) -> Int { (c * 14 + 5) / 10 }

    /// 通れない地形にする/コストを変える。
    public func with(_ b: Biome, _ c: Int?) -> MoveCostTable {
        var t = self
        t.costs[b] = c
        precondition(!t.costs.isEmpty, "通れる地形が 1 つは要る")
        return t
    }

    var minStraight: Int { costs.values.min()! }
    var minDiagonal: Int { Self.diagonal(minStraight) }

    /// 千分の一の体力を体力に直す。
    public static func stamina(_ milli: Int) -> Double { Double(milli) / 1000 }

    // 保存は地形の鍵(文字列)で。Biome の並び順に依らない
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: Int].self)
        var c: [Biome: Int] = [:]
        for (k, v) in raw { if let b = Biome(key: k) { c[b] = v } }
        self.init(c)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(Dictionary(uniqueKeysWithValues: costs.map { ($0.key.key, $0.value) }))
    }
}

/// 見つかった経路。
public struct MapPath: Codable, Equatable, Sendable {
    /// 歩くマス(出発点を含まず、目的地を含む)。
    public var steps: [GridPoint]
    /// 合計コスト(千分の一の体力)。霧の先のマスは仮定のコストで数える。
    public var cost: Int

    public init(steps: [GridPoint], cost: Int) {
        self.steps = steps
        self.cost = cost
    }

    /// 合計の体力コスト。
    public var stamina: Double { MoveCostTable.stamina(cost) }
}

/// 経路探索の結果。
public enum PathOutcome: Equatable, Sendable {
    /// 見たことのあるマスだけで目的地まで届く(既定のコスト)。
    case known(MapPath)
    /// 霧の先(未踏のマス)を仮定のコストで通る。歩いて霧が晴れるたびに引き直す。
    /// `firstUnknownStep` は steps の中で最初に未踏のマスの番号。
    case throughFog(MapPath, firstUnknownStep: Int)
    /// 届かない(知っている範囲の通れない地形・塞がれたマスで閉じている)。
    case blocked

    /// 歩く経路(届かなければ nil)。
    public var path: MapPath? {
        switch self {
        case .known(let p), .throughFog(let p, _): return p
        case .blocked: return nil
        }
    }

    public var isBlocked: Bool { self == .blocked }
}

/// 霧(未踏のマス)の扱い。
public enum FogPolicy: Equatable, Sendable {
    /// 未踏のマスは通れない。
    case knownOnly
    /// 未踏のマスはこの地形とみなして通れると仮定する(プレイヤーのタップ用の既定。平地)。
    case assume(Biome)
    /// 霧を見ない(記録済みの地形で探す。生成の検査・仲間の自動行動など)。
    case ignore
}

/// 何を「見たことがある」とみなすか。
public enum PathKnowledge: Sendable {
    /// 層の視界(ノアの既知)。
    case layerVisibility
    /// 別の視界(仲間の既知など)を外から渡す。
    case visibility(VisibilityLayer)
    /// 既知のマスの集合を外から渡す。
    case cells(Set<GridPoint>)
}

/// 経路探索の条件。
public struct PathOptions: Sendable {
    public var fog: FogPolicy
    public var knowledge: PathKnowledge
    /// 避ける地形(UI の「安全な道」なら [.forest])。
    public var avoid: Set<Biome>
    /// 通れないマス(建物・柵など、呼び出し側の事情)。
    public var blocked: Set<GridPoint>
    /// これ以下のマス数の地図は全体を探す(最短が保証される)。
    public var fullSearchCellLimit: Int
    /// 大きい地図では出発点と目的地を囲む長方形をこれだけ広げた範囲で探す。
    public var windowMargin: Int

    public init(fog: FogPolicy = .assume(.plain), knowledge: PathKnowledge = .layerVisibility,
                avoid: Set<Biome> = [], blocked: Set<GridPoint> = [],
                fullSearchCellLimit: Int = 512 * 512, windowMargin: Int = 64) {
        self.fog = fog
        self.knowledge = knowledge
        self.avoid = avoid
        self.blocked = blocked
        self.fullSearchCellLimit = fullSearchCellLimit
        self.windowMargin = windowMargin
    }

    /// プレイヤーのタップ(既定): 霧の先は平地と仮定して歩き、晴れるたびに引き直す。
    public static let tap = PathOptions()
    /// 見たことのあるマスだけ。
    public static let knownOnly = PathOptions(fog: .knownOnly)
    /// 記録済みの地形で(霧を見ない)。
    public static let truth = PathOptions(fog: .ignore)
}

/// 探索の作業領域。何度も探すとき(仲間の経路など)に配列を使い回す。1 つのスレッドの中で使うこと。
public final class PathWorkspace {
    var generation: UInt32 = 0
    var seen: [UInt32] = []      // g と parent が有効な世代
    var closedAt: [UInt32] = []  // 閉じた世代
    var costAt: [UInt32] = []    // コストの取得済みの世代
    var g: [Int] = []
    var parent: [Int32] = []
    var stepCost: [Int32] = []   // -1 = 通れない
    var unknown: [Bool] = []
    var heap = MinHeap()

    public init() {}

    /// 確保済みの大きさ(マス数)。
    public var capacity: Int { g.count }

    func prepare(_ n: Int) {
        if g.count < n {
            seen = [UInt32](repeating: 0, count: n)
            closedAt = seen
            costAt = seen
            g = [Int](repeating: 0, count: n)
            parent = [Int32](repeating: -1, count: n)
            stepCost = [Int32](repeating: 0, count: n)
            unknown = [Bool](repeating: false, count: n)
            generation = 0
        }
        generation &+= 1
        if generation == 0 {   // 一周したら印を消す
            for i in seen.indices { seen[i] = 0; closedAt[i] = 0; costAt[i] = 0 }
            generation = 1
        }
        heap.removeAll()
    }
}

/// A* の経路探索(原作 `Pathfinder`)。8 方向、斜め 1.4 倍、地形ごとのコスト。
/// 通れないマスが斜めに 2 つ並んだ間は斜めに抜けない(角を切らない)。
/// 原作は探索 500 ノードで打ち切っていたが、ここでは探索範囲を地図全体(大きい地図は窓)に限って最後まで探す。
public enum Pathfinder {
    /// マスの見え方(通れない / 既知の地形 / 未踏で仮定した地形)。
    public enum Cell: Equatable, Sendable {
        case impassable
        case known(Biome)
        case assumed(Biome)
    }

    /// 層の上の経路探索。
    public static func route(in layer: MapLayer, from start: GridPoint, to goal: GridPoint,
                             costs: MoveCostTable = .original, options: PathOptions = .tap,
                             workspace: PathWorkspace? = nil) -> PathOutcome {
        let terrain = layer.terrain
        let isKnown: (GridPoint) -> Bool
        switch options.knowledge {
        case .layerVisibility:
            let v = layer.visibility
            isKnown = { v.isKnown($0) }
        case .visibility(let v):
            isKnown = { v.isKnown($0) }
        case .cells(let set):
            isKnown = { set.contains($0) }
        }
        let fog = options.fog, avoid = options.avoid, blocked = options.blocked
        return route(size: layer.size, from: start, to: goal, costs: costs, options: options, workspace: workspace) { p in
            if !blocked.isEmpty && blocked.contains(p) { return .impassable }
            switch fog {
            case .ignore:
                break
            case .knownOnly:
                if !isKnown(p) { return .impassable }
            case .assume(let b):
                if !isKnown(p) { return avoid.contains(b) ? .impassable : .assumed(b) }
            }
            guard let b = terrain.biome(at: p), !avoid.contains(b) else { return .impassable }
            return .known(b)
        }
    }

    /// マスの見え方を返す関数の上での経路探索。
    public static func route(size: MapSize, from start: GridPoint, to goal: GridPoint,
                             costs: MoveCostTable = .original, options: PathOptions = .tap,
                             workspace: PathWorkspace? = nil, cellAt: (GridPoint) -> Cell) -> PathOutcome {
        guard size.contains(start), size.contains(goal) else { return .blocked }
        if start == goal { return .known(MapPath(steps: [], cost: 0)) }
        func enterCost(_ c: Cell) -> Int? {
            switch c {
            case .impassable: return nil
            case .known(let b), .assumed(let b): return costs.cost(b)
            }
        }
        guard enterCost(cellAt(goal)) != nil else { return .blocked }

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
        let ws = workspace ?? PathWorkspace()
        ws.prepare(w * h)
        let gen = ws.generation

        @inline(__always) func idx(_ x: Int, _ y: Int) -> Int { (y - lo.y) * w + (x - lo.x) }
        let minS = costs.minStraight, minD = costs.minDiagonal
        @inline(__always) func heuristic(_ x: Int, _ y: Int) -> Int {
            let dx = abs(x - goal.x), dy = abs(y - goal.y)
            let d = min(dx, dy)
            return (max(dx, dy) - d) * minS + d * minD
        }
        // マスのコスト(窓の中で 1 度だけ引く)。-1 = 通れない
        func stepCost(_ x: Int, _ y: Int, _ i: Int) -> Int32 {
            if ws.costAt[i] == gen { return ws.stepCost[i] }
            let c = cellAt(GridPoint(x, y))
            let v: Int32 = enterCost(c).map { Int32($0) } ?? -1
            if case .assumed = c { ws.unknown[i] = true } else { ws.unknown[i] = false }
            ws.stepCost[i] = v
            ws.costAt[i] = gen
            return v
        }
        @inline(__always) func inWindow(_ x: Int, _ y: Int) -> Bool { x >= lo.x && y >= lo.y && x <= hi.x && y <= hi.y }

        let si = idx(start.x, start.y), gi = idx(goal.x, goal.y)
        ws.g[si] = 0
        ws.parent[si] = -1
        ws.seen[si] = gen
        ws.heap.push(heuristic(start.x, start.y), si)

        let dirs = GridPoint.directions8
        while let (_, cur) = ws.heap.pop() {
            if ws.closedAt[cur] == gen { continue }
            ws.closedAt[cur] = gen
            if cur == gi { break }
            let cx = lo.x + cur % w, cy = lo.y + cur / w
            let cg = ws.g[cur]
            for k in 0..<8 {
                let d = dirs[k]
                let nx = cx + d.x, ny = cy + d.y
                guard inWindow(nx, ny) else { continue }
                let ni = idx(nx, ny)
                if ws.closedAt[ni] == gen { continue }
                let sc = stepCost(nx, ny, ni)
                if sc < 0 { continue }
                var step = Int(sc)
                if k >= 4 {
                    // 角を切らない: 縦横の 2 マスがどちらも通れなければ斜めに抜けない
                    let aOK = inWindow(nx, cy) && stepCost(nx, cy, idx(nx, cy)) >= 0
                    let bOK = inWindow(cx, ny) && stepCost(cx, ny, idx(cx, ny)) >= 0
                    if !aOK && !bOK { continue }
                    step = MoveCostTable.diagonal(step)
                }
                let ng = cg + step
                if ws.seen[ni] != gen || ng < ws.g[ni] {
                    ws.seen[ni] = gen
                    ws.g[ni] = ng
                    ws.parent[ni] = Int32(cur)
                    ws.heap.push(ng + heuristic(nx, ny), ni)
                }
            }
        }

        guard ws.closedAt[gi] == gen else { return .blocked }
        var steps: [GridPoint] = []
        var unknownFlags: [Bool] = []
        var c = gi
        while c != si {
            steps.append(GridPoint(lo.x + c % w, lo.y + c / w))
            unknownFlags.append(ws.unknown[c])
            c = Int(ws.parent[c])
        }
        steps.reverse()
        unknownFlags.reverse()
        let path = MapPath(steps: steps, cost: ws.g[gi])
        if let first = unknownFlags.firstIndex(of: true) {
            return .throughFog(path, firstUnknownStep: first)
        }
        return .known(path)
    }

    /// 地形を返す関数の上での経路探索(nil は通れない)。霧は無いものとして扱う。
    public static func findPath(size: MapSize, from start: GridPoint, to goal: GridPoint,
                                costs: MoveCostTable = .original, options: PathOptions = .truth,
                                workspace: PathWorkspace? = nil,
                                biomeAt: (GridPoint) -> Biome?) -> MapPath? {
        let avoid = options.avoid, blocked = options.blocked
        return route(size: size, from: start, to: goal, costs: costs, options: options, workspace: workspace) { p in
            if blocked.contains(p) { return .impassable }
            guard let b = biomeAt(p), !avoid.contains(b) else { return .impassable }
            return .known(b)
        }.path
    }

    /// 経路の合計コスト(出発点から順に歩いたとき)。通れないマス・飛び石・角の切り抜けがあれば nil。
    public static func cost(of steps: [GridPoint], from start: GridPoint, costs: MoveCostTable = .original,
                            biomeAt: (GridPoint) -> Biome?) -> Int? {
        func passable(_ p: GridPoint) -> Bool { biomeAt(p).flatMap { costs.cost($0) } != nil }
        var total = 0
        var prev = start
        for p in steps {
            let dx = p.x - prev.x, dy = p.y - prev.y
            guard max(abs(dx), abs(dy)) == 1, let b = biomeAt(p), let c = costs.cost(b) else { return nil }
            if dx != 0 && dy != 0 {
                guard passable(GridPoint(prev.x + dx, prev.y)) || passable(GridPoint(prev.x, prev.y + dy)) else { return nil }
                total += MoveCostTable.diagonal(c)
            } else {
                total += c
            }
            prev = p
        }
        return total
    }
}

/// (優先度, 番号) の二分ヒープ。同じ優先度は番号の小さい順(決定的)。
struct MinHeap {
    private var items: [(Int, Int)] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func removeAll() { items.removeAll(keepingCapacity: true) }

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
