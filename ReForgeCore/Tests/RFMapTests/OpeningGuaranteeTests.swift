import Foundation
import RFKernel
import XCTest
@testable import RFMap

/// TEST-O12 地図の保証(序盤の設計 v0.4 の W-12): seed 1000 本で、序盤の予算の距離と量の条件をすべて満たす。
/// 生成器の測る関数を使わず、地図をじかに数えて確かめる(経路は Pathfinder)。
final class OpeningGuaranteeTests: XCTestCase {
    struct Stats {
        var attempts: [Int] = []
        var forest: [Int] = []
        var clay: [Int] = []
        var outcrop: [Int] = []
        var iron: [Int] = []
    }

    static func check(_ m: WorldMap, rules r: OpeningRules, seed: UInt64, _ s: inout Stats, verified: Bool = true) {
        let lm = m.lm
        let layer = m.surface
        let biome: (GridPoint) -> Biome? = { m.biome(at: $0) }
        if verified { XCTAssertTrue(m.generationReport?.verified == true, "seed \(seed): 検証済みでない") }
        s.attempts.append(m.generationReport?.attempts ?? 0)
        let ws = PathWorkspace()
        func reach(_ p: GridPoint) -> MapPath? {
            Pathfinder.findPath(size: m.size, from: lm.base.center, to: p, workspace: ws, biomeAt: biome)
        }

        // 残り火のそばの森(残骸の占めるマスからチェビシェフ r 以内)と、拠点の近くの森
        let wreck = layer.placements.all.first { $0.id == .homeWreck }!
        var ember = 0, near = 0
        for y in 0..<m.size.height {
            for x in 0..<m.size.width {
                let p = GridPoint(x, y)
                guard biome(p) == .forest else { continue }
                if wreck.cells.map({ $0.chebyshev(to: p) }).min()! <= r.emberForestRadius { ember += 1 }
                if !lm.base.contains(p), lm.base.ringDistance(p) <= r.forestRing { near += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(ember, r.emberForestMin, "seed \(seed): 残り火のそばの森")
        s.forest.append(near)
        XCTAssertGreaterThanOrEqual(near, r.forestMin, "seed \(seed): 拠点の近くの森")

        // 川岸(粘土)と露頭へ、決めた歩数以内で歩ける
        let clay = reach(lm.clayBank), ore = reach(lm.outcrop)
        s.clay.append(clay?.steps.count ?? -1)
        s.outcrop.append(ore?.steps.count ?? -1)
        XCTAssertLessThanOrEqual(clay?.steps.count ?? .max, r.clayBankSteps, "seed \(seed): 川岸の歩数")
        XCTAssertLessThanOrEqual(ore?.steps.count ?? .max, r.outcropSteps, "seed \(seed): 露頭の歩数")
        // 露頭のそばの森の縁
        let e = r.outcropForestEdge
        var edge = false
        for y in (lm.outcrop.y - e)...(lm.outcrop.y + e) {
            for x in (lm.outcrop.x - e)...(lm.outcrop.x + e) {
                let p = GridPoint(x, y)
                if biome(p) == .forest, p.distanceSquared(to: lm.outcrop) <= e * e { edge = true }
            }
        }
        XCTAssertTrue(edge, "seed \(seed): 露頭のそばに森が無い")

        // 岩山の鉄 2 つ(2 つ目は露頭から幅の内側・見つかっていない)、採掘回数の合計
        guard let first = layer.deposits[.outcrop], let second = layer.deposits[.secondIron] else {
            return XCTFail("seed \(seed): 岩山の鉄が 2 つ無い")
        }
        XCTAssertEqual(second.category, .iron)
        XCTAssertFalse(second.isDiscovered, "seed \(seed): 2 つ目の鉄が最初から見つかっている")
        let d2 = second.position.distanceSquared(to: lm.outcrop)
        XCTAssertTrue(d2 >= r.secondIronMin * r.secondIronMin && d2 <= r.secondIronMax * r.secondIronMax,
                      "seed \(seed): 2 つ目の鉄と露頭の距離")
        s.iron.append(first.remainingExtractions + second.remainingExtractions)
        XCTAssertGreaterThanOrEqual(first.remainingExtractions + second.remainingExtractions, r.ironExtractionsMin,
                                    "seed \(seed): 鉄の採掘回数")
        XCTAssertNotNil(reach(second.position), "seed \(seed): 2 つ目の鉄に届かない")

        // 石炭の鉱脈 1 つ(露頭から幅の内側・岩山の裏・岩場・歩いて行ける)
        guard let coal = layer.deposits[DepositID.coal] else { return XCTFail("seed \(seed): 石炭の鉱脈が無い") }
        XCTAssertEqual(coal.category, .coal)
        let c2 = coal.position.distanceSquared(to: lm.outcrop)
        XCTAssertTrue(c2 >= r.coalFromOutcropMin * r.coalFromOutcropMin && c2 <= r.coalFromOutcropMax * r.coalFromOutcropMax,
                      "seed \(seed): 石炭と露頭の距離")
        let u = lm.mountainCenter - lm.base.center, v = coal.position - lm.mountainCenter
        XCTAssertGreaterThanOrEqual(u.x * v.x + u.y * v.y, 0, "seed \(seed): 石炭が岩山の手前")
        XCTAssertEqual(biome(coal.position), .rock)
        XCTAssertNotNil(reach(coal.position), "seed \(seed): 石炭に届かない")

        // 獣の巣(露頭から幅の内側の森の中)
        guard let nest = layer.placements.all.first(where: { $0.id == .openingNest }) else {
            return XCTFail("seed \(seed): 獣の巣が無い")
        }
        XCTAssertEqual(nest.kind, .nest)
        let n2 = nest.anchor.distanceSquared(to: lm.outcrop)
        XCTAssertTrue(n2 >= r.nestFromOutcropMin * r.nestFromOutcropMin && n2 <= r.nestFromOutcropMax * r.nestFromOutcropMax,
                      "seed \(seed): 巣と露頭の距離")
        XCTAssertTrue(nest.cells.allSatisfy { biome($0) == .forest }, "seed \(seed): 巣が森の中に無い")

        // 遠くの残骸は 45 マス以内
        XCTAssertLessThanOrEqual(lm.farWreck.distance(to: lm.base.center), 45)
    }

    /// 種の数は REFORGE_O12_SEEDS(手元の既定 50。CI は 1000)。
    func testThousandSeedsMeetTheOpeningBudget() throws {
        let n = ProcessInfo.processInfo.environment["REFORGE_O12_SEEDS"].flatMap { Int($0) } ?? 50
        var s = Stats()
        var slowest = (seed: UInt64(0), ms: 0)
        for seed in UInt64(0)..<UInt64(n) {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let m = try WorldMap.generate(seed: seed)
            let ms = Int((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            if ms > slowest.ms { slowest = (seed, ms) }
            Self.check(m, rules: m.config.opening!, seed: seed, &s)
        }
        print("TEST-O12: 種 \(n)、いちばん遅い生成 seed \(slowest.seed) \(slowest.ms) ms、"
              + "作り直し 最大 \(s.attempts.max()!) 平均 \(Double(s.attempts.reduce(0, +)) / Double(n))、"
              + "近くの森 最小 \(s.forest.min()!)、川岸 最大 \(s.clay.max()!) 歩、露頭 最大 \(s.outcrop.max()!) 歩、"
              + "鉄の回数 最小 \(s.iron.min()!)")
    }

    /// 小さい地図(公開の試験用の層の 48×48)でも鉱脈と森の保証が成り立つ。48×48 は目印の保証を満たせず、
    /// 本番の生成(RFMapGenerator)も未検証の地図に落とすので、ここでも未検証のまま測る。
    func testSmallMapsMeetScaledRules() throws {
        var s = Stats()
        for seed in UInt64(0)..<100 {
            var rng = SeededRandom(state: seed)
            var cfg = MapGenerationConfig(size: GridSize(width: 48, height: 48))
            cfg.allowUnverifiedFallback = true
            let m = try WorldMap.generate(config: cfg, rng: &rng)
            Self.check(m, rules: m.config.opening!, seed: seed, &s, verified: false)
        }
    }

    func testSameSeedSameMap() throws {
        for seed in [UInt64(3), 77, 999] {
            XCTAssertEqual(try WorldMap.generate(seed: seed), try WorldMap.generate(seed: seed))
        }
    }

    /// 保証を外した設定(古い保存の設定)では、石炭も巣も足さない。
    func testNoOpeningRulesAddsNothing() throws {
        var c = MapGenerationConfig(size: .r1)
        c.opening = nil
        var rng = SeededRandom(state: 5)
        let m = try WorldMap.generate(config: c, rng: &rng)
        XCTAssertNil(m.surface.deposits[DepositID.coal])
        XCTAssertNil(m.surface.placements.all.first { $0.id == .openingNest })
    }
}
