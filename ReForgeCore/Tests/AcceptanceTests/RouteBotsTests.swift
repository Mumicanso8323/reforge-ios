import ReForgeEngine
import RFTestSupport
import XCTest

/// TEST-R1-04 道筋の複数性(担当 U8): 方針の違う 3 ボット(森の近道 / 川沿い / 遺品優先)が、同じ seed の本物の地図
/// (RFMapGenerator 96×96)を歩いたときの解禁の順序の順位相関(スピアマン)が 0.8 未満。
///
/// - 歩くのは RFCrew の歩行の代わりに、Pathfinder の経路を 1 マス 1 ステップで位置を書いて進める(歩行が入ったら walk に替える)。
/// - 解禁の順序は `.unlocked` の出来事の順。片方にしか無い解禁は、無い側で「最後に同順位」として数える。
/// - 公開の層では試験用の場の表(content/public/exploration.json)で仕組みを確かめる。非公開の層があれば本物の表でも回す。
final class RouteBotsTests: XCTestCase {
    enum Policy: CaseIterable { case forestShortcut, riverside, relicFirst }

    struct Bot {
        let content: ContentDB
        let sim: Simulation
        var world: WorldState
        var unlocks: [String] = []

        init(content: ContentDB, seed: UInt64) {
            self.content = content
            sim = Simulation(content: content)
            world = WorldFactory(content: content, mapGenerator: RFMapGenerator()).newWorld(seed: seed)
        }

        var layer: MapLayer { world.map[.surface]! }
        var here: GridPoint { world.people[.noah]!.position!.point }

        mutating func record(_ r: StepReport) {
            for e in r.events { if case .unlocked(let what) = e, !unlocks.contains(what) { unlocks.append(what) } }
        }

        /// 経路どおりに歩く(届かなければ何もしない)。
        mutating func walk(to goal: GridPoint, avoidForest: Bool) {
            var costs = MoveCostTable(terrains: content.terrains)
            if avoidForest { costs = costs.with(.forest, nil) }
            guard let path = layer.route(from: here, to: goal, costs: costs, options: .truth).path else { return }
            for p in path.steps {
                world.people[.noah]?.position = WorldPoint(.surface, p)
                record(sim.runSteps(1, &world))
            }
        }

        mutating func interact(_ id: InteractionID, at g: GridPoint) {
            record(sim.apply(.exploration(.interact(interaction: id, at: WorldPoint(.surface, g), holding: true)), to: &world))
            var n = 0
            while world.exploration.active[.noah] != nil && n < 500 {
                record(sim.runSteps(1, &world))
                n += 1
            }
        }

        /// 歩ける最寄りのマス(目印が歩けないマスのとき)。
        func walkable(near g: GridPoint) -> GridPoint {
            var best = g
            var bestD = Int.max
            for dy in -4...4 {
                for dx in -4...4 {
                    let p = g + GridPoint(dx, dy)
                    guard let b = layer.biome(at: p), !(b == .river), max(abs(dx), abs(dy)) < bestD else { continue }
                    best = p
                    bestD = max(abs(dx), abs(dy))
                }
            }
            return best
        }

        /// 川岸(shore)の、目印に最も近いマス。
        func shore(near g: GridPoint) -> GridPoint {
            var best = walkable(near: g)
            var bestD = Int.max
            for dy in -8...8 {
                for dx in -8...8 {
                    let p = g + GridPoint(dx, dy)
                    guard layer.biome(at: p) == .water, dx * dx + dy * dy < bestD else { continue }
                    best = p
                    bestD = dx * dx + dy * dy
                }
            }
            return best
        }

        mutating func play(_ policy: Policy) {
            guard let lm = world.map.landmarks else { return }
            let home = here
            let outcrop = walkable(near: lm.outcrop)
            switch policy {
            case .forestShortcut:
                walk(to: outcrop, avoidForest: false)
            case .riverside:
                walk(to: shore(near: lm.clayBank), avoidForest: true)
                walk(to: outcrop, avoidForest: true)
            case .relicFirst:
                let wreck = lm.farWreck
                walk(to: walkable(near: wreck + GridPoint(0, 1)), avoidForest: true)
                interact("interaction.search_far_wreck", at: wreck)
                walk(to: home, avoidForest: true)
                // 遺品で森の危険が下がったので、近道で岩山へ
                walk(to: outcrop, avoidForest: false)
            }
        }
    }

    /// スピアマンの順位相関(和集合で順位を付け、片方に無い物は最後に同順位)。
    static func spearman(_ a: [String], _ b: [String]) -> Double {
        let all = Array(Set(a).union(b)).sorted()
        guard all.count > 1 else { return 1 }
        func ranks(_ order: [String]) -> [Double] {
            let missing = all.filter { !order.contains($0) }.count
            let tail = Double(order.count) + (Double(missing) + 1) / 2
            return all.map { x in order.firstIndex(of: x).map { Double($0 + 1) } ?? tail }
        }
        let ra = ranks(a), rb = ranks(b)
        let ma = ra.reduce(0, +) / Double(ra.count), mb = rb.reduce(0, +) / Double(rb.count)
        var cov = 0.0, va = 0.0, vb = 0.0
        for i in all.indices {
            cov += (ra[i] - ma) * (rb[i] - mb)
            va += (ra[i] - ma) * (ra[i] - ma)
            vb += (rb[i] - mb) * (rb[i] - mb)
        }
        guard va > 0, vb > 0 else { return 1 }
        return cov / (va * vb).squareRoot()
    }

    func testSpearmanHelper() {
        XCTAssertEqual(Self.spearman(["a", "b", "c"], ["a", "b", "c"]), 1, accuracy: 1e-9)
        XCTAssertEqual(Self.spearman(["a", "b", "c"], ["c", "b", "a"]), -1, accuracy: 1e-9)
    }

    private func runRoutes(content base: ContentDB, seeds: Range<UInt64>) -> [String: Double] {
        var content = base
        content.mapGen = MapGenConfig(size: GridSize(width: 96, height: 96))
        var sums: [String: Double] = [:]
        for seed in seeds {
            var orders: [Policy: [String]] = [:]
            for p in Policy.allCases {
                var bot = Bot(content: content, seed: seed)
                bot.play(p)
                orders[p] = bot.unlocks
            }
            if seed == seeds.lowerBound {
                print("TEST-R1-04 seed \(seed): " + Policy.allCases.map { "\($0)=\(orders[$0]!.count)件" }.joined(separator: " "))
            }
            let pairs: [(String, Policy, Policy)] = [("forest~river", .forestShortcut, .riverside),
                                                     ("forest~relic", .forestShortcut, .relicFirst),
                                                     ("river~relic", .riverside, .relicFirst)]
            for (name, a, b) in pairs { sums[name, default: 0] += Self.spearman(orders[a]!, orders[b]!) }
        }
        return sums.mapValues { $0 / Double(seeds.count) }
    }

    /// TEST-R1-04(公開の層の試験用の表)。
    func testRouteDiversityPublicTables() throws {
        let means = runRoutes(content: try TestContent.publicOnly(), seeds: 0..<12)
        print("TEST-R1-04 ρ(公開): \(means.sorted { $0.key < $1.key })")
        for (pair, rho) in means.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThan(rho, 0.8, "解禁の順序が似すぎている: \(pair) ρ=\(rho)")
        }
    }

    /// TEST-R1-04(本物の表)。
    func testRouteDiversityFullContent() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開のコンテンツが無い(公開 CI では飛ばす)")
        let means = runRoutes(content: try TestContent.full(), seeds: 0..<20)
        for (pair, rho) in means.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThan(rho, 0.8, "解禁の順序が似すぎている: \(pair)")
        }
    }
}
