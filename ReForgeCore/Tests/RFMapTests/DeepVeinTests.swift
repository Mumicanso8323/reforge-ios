import RFKernel
import XCTest
@testable import RFMap

/// U19 の受け入れテスト(HNT-14 の目印): 岩山の奥に希少の鉱脈を 1 つ必ず置く。設定が無ければ置かず、地図は変わらない。
final class DeepVeinTests: XCTestCase {
    func config(_ rule: DeepVeinRule?) -> MapGenerationConfig {
        var c = MapGenerationConfig.r1
        c.deepVein = rule
        return c
    }

    func testDeepVeinPlacedInMountainFarthestFromBase() throws {
        for seed in UInt64(0)..<30 {
            var rng = SeededRandom(state: seed)
            let m = try WorldMap.generate(config: config(DeepVeinRule()), rng: &rng)
            let d = try XCTUnwrap(m.layers[.surface]!.deposits[.deepVein], "seed \(seed)")
            XCTAssertEqual(d.category, .rare)
            XCTAssertEqual(m.layers[.surface]!.terrain.biome(at: d.position), .rock, "seed \(seed)")
            let lm = m.lm
            XCTAssertLessThanOrEqual(d.position.chebyshev(to: lm.mountainCenter), lm.mountainRadius + 1)
            let o = lm.base.center
            func dist2(_ p: GridPoint) -> Int { (p.x - o.x) * (p.x - o.x) + (p.y - o.y) * (p.y - o.y) }
            let fixed: [DepositID] = [.outcrop, .clayBank, "deposit.mountain.0", "deposit.mountain.1"]
            for other in m.layers[.surface]!.deposits.all where fixed.contains(other.id) {
                XCTAssertGreaterThanOrEqual(other.position.chebyshev(to: d.position), 2, "seed \(seed) \(other.id)")
            }
            XCTAssertGreaterThan(dist2(d.position), dist2(lm.mountainCenter), "seed \(seed): 奥 = 岩山の中心より遠い")
            XCTAssertGreaterThan(dist2(d.position), dist2(lm.outcrop), "seed \(seed): 露頭より遠い")
        }
    }

    func testNoRuleLeavesMapUnchanged() throws {
        var r1 = SeededRandom(state: 7), r2 = SeededRandom(state: 7)
        let a = try WorldMap.generate(config: config(nil), rng: &r1)
        let b = try WorldMap.generate(config: .r1, rng: &r2)
        XCTAssertEqual(a, b)
        XCTAssertNil(a.layers[.surface]!.deposits[.deepVein])
        var r3 = SeededRandom(state: 7)
        let c = try WorldMap.generate(config: config(DeepVeinRule(category: .copper)), rng: &r3)
        XCTAssertEqual(c.layers[.surface]!.deposits[.deepVein]?.category, .copper)
        XCTAssertEqual(c.landmarks, a.landmarks, "目印の位置は変えない")
    }
}
