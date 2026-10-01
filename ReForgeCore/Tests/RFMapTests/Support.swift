import XCTest
@testable import RFMap

/// テストで使い回す地図(生成は 1 回ずつ)。
enum MapFixture {
    static let r1Seed7 = WorldMap.generate(seed: 7)
    static let r1Seeds: [WorldMap] = (0..<100).map { WorldMap.generate(seed: UInt64($0)) }
}

/// 経路探索の検算用の素朴なダイクストラ(本体の A* と独立に書く)。
func referenceDijkstra(size: MapSize, from s: GridPoint, to g: GridPoint, costs: MoveCostTable,
                       biomeAt: (GridPoint) -> Biome?) -> Int? {
    var dist = [Int](repeating: Int.max, count: size.cellCount)
    var done = [Bool](repeating: false, count: size.cellCount)
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
                guard size.contains(q), let b = biomeAt(q) else { continue }
                let c: Int?
                if dx != 0 && dy != 0 {
                    c = costs.cost(b).map { Int((Double($0) * 1.4).rounded()) }
                } else {
                    c = costs.cost(b)
                }
                guard let step = c else { continue }
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

/// 線分上のマス(ブレゼンハム)。テスト側で独立に持つ。
func lineCells(_ a: GridPoint, _ b: GridPoint) -> [GridPoint] {
    var out: [GridPoint] = []
    var x = a.x, y = a.y
    let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
    let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
    var err = dx + dy
    while true {
        out.append(GridPoint(x, y))
        if x == b.x && y == b.y { break }
        let e2 = 2 * err
        if e2 >= dy { err += dy; x += sx }
        if e2 <= dx { err += dx; y += sy }
    }
    return out
}
