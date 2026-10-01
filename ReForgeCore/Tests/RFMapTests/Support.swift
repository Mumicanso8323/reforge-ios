import RFKernel
import XCTest
@testable import RFMap

/// テストで使い回す地図(生成は 1 回ずつ)。
enum MapFixture {
    // swiftlint:disable force_try
    static let r1Seed7 = try! WorldMap.generate(seed: 7)
    static let r1Seeds: [WorldMap] = (0..<100).map { try! WorldMap.generate(seed: UInt64($0)) }
    // swiftlint:enable force_try
}

extension WorldMap {
    /// 生成した地図の目印(テストでは必ずある)。
    var lm: Landmarks { landmarks! }
}

/// 経路探索の検算用の素朴なダイクストラ(本体の A* と独立に書く)。
/// 斜めは (c*14+5)/10。通れない 2 マスの間の角を斜めに抜けない。
func referenceDijkstra(size: MapSize, from s: GridPoint, to g: GridPoint, costs: MoveCostTable,
                       biomeAt: (GridPoint) -> Biome?) -> Int? {
    let n = size.width * size.height
    var dist = [Int](repeating: Int.max, count: n)
    var done = [Bool](repeating: false, count: n)
    var heap: [(Int, Int)] = []
    func push(_ d: Int, _ i: Int) {
        heap.append((d, i))
        var c = heap.count - 1
        while c > 0 {
            let p = (c - 1) / 2
            if heap[c].0 < heap[p].0 { heap.swapAt(c, p); c = p } else { break }
        }
    }
    func pop() -> (Int, Int)? {
        guard !heap.isEmpty else { return nil }
        let top = heap[0]
        let last = heap.removeLast()
        if !heap.isEmpty {
            heap[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < heap.count && heap[l].0 < heap[m].0 { m = l }
                if r < heap.count && heap[r].0 < heap[m].0 { m = r }
                if m == i { break }
                heap.swapAt(i, m)
                i = m
            }
        }
        return top
    }
    func passable(_ q: GridPoint) -> Bool {
        size.contains(q) && biomeAt(q).flatMap { costs.cost($0) } != nil
    }
    let si = s.y * size.width + s.x
    dist[si] = 0
    push(0, si)
    while let (d, i) = pop() {
        if done[i] { continue }
        done[i] = true
        let p = GridPoint(i % size.width, i / size.width)
        if p == g { return d }
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let q = GridPoint(p.x + dx, p.y + dy)
                guard size.contains(q), let b = biomeAt(q), let c = costs.cost(b) else { continue }
                if dx != 0 && dy != 0 {
                    guard passable(GridPoint(p.x + dx, p.y)) || passable(GridPoint(p.x, p.y + dy)) else { continue }
                }
                let step = dx != 0 && dy != 0 ? (c * 14 + 5) / 10 : c
                let qi = q.y * size.width + q.x
                if d + step < dist[qi] {
                    dist[qi] = d + step
                    push(d + step, qi)
                }
            }
        }
    }
    return nil
}

/// 地図の真実の地形で、拠点からの最小コスト経路(霧を見ない)。
func truthPath(_ m: WorldMap, from a: GridPoint, to b: GridPoint, avoid: Set<Biome> = []) -> MapPath? {
    m.findPath(from: a, to: b, options: PathOptions(fog: .ignore, avoid: avoid))
}

/// 中心線までの距離。
func distanceToRiver(_ m: WorldMap, _ p: GridPoint) -> Double {
    m.lm.river.map { Double(($0.x - p.x) * ($0.x - p.x) + ($0.y - p.y) * ($0.y - p.y)).squareRoot() }.min()!
}

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// FNV-1a 64(ゴールデンテスト用。テスト側で独立に持つ)。
struct FNV1a {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325
    mutating func add(_ x: Int) {
        var v = UInt64(bitPattern: Int64(x))
        for _ in 0..<8 {
            value ^= v & 0xff
            value = value &* 0x0000_0100_0000_01b3
            v >>= 8
        }
    }
    mutating func add(_ p: GridPoint) { add(p.x); add(p.y) }
}
