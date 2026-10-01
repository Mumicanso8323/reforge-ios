import RFKernel
import XCTest
@testable import RFMap

/// コンテンツが決める場所(MapGenerationConfig.sites。U16)。
final class SiteTests: XCTestCase {
    static let rule = SiteRule(id: "site.test.fort", poi: "site.test.fort", minDistance: 30, maxDistance: 40)

    func config() -> MapGenerationConfig {
        var c = MapGenerationConfig.r1
        c.allowUnverifiedFallback = true
        c.sites = [Self.rule]
        return c
    }

    func generate(_ seed: UInt64, _ c: MapGenerationConfig) throws -> WorldMap {
        var rng = SeededRandom(state: seed)
        return try WorldMap.generate(config: c, rng: &rng)
    }

    /// 40 seed のどれでも、距離の範囲に置かれ、拠点から歩いて行ける。乾いた土地で、拠点の整地に重ならない。
    func testSitePlacedInRangeAndReachable() throws {
        for seed in 0..<40 as Range<UInt64> {
            let m = try generate(seed, config())
            let site = try XCTUnwrap(m.surface.placements.all.first { $0.templateID == "site.test.fort" }, "seed \(seed)")
            let d = site.anchor.distance(to: m.lm.base.center)
            XCTAssertTrue(d >= 30 && d <= 40, "seed \(seed): 距離 \(d)")
            for c in site.cells {
                let b = try XCTUnwrap(m.surface.terrain.biome(at: c))
                XCTAssertFalse(b.isWet)
                XCTAssertFalse(m.lm.base.contains(c))
            }
            XCTAssertNotNil(Pathfinder.route(in: m.surface, from: m.lm.base.center, to: site.anchor, costs: .original,
                                             options: PathOptions(fog: .ignore)).path, "seed \(seed)")
        }
    }

    /// 同じ seed なら同じ場所。sites が無ければ、今までと同じ地図(乱数を余分に引かない)。
    func testDeterministicAndNoSitesUnchanged() throws {
        let a = try generate(5, config()), b = try generate(5, config())
        XCTAssertEqual(a, b)
        var plain = MapGenerationConfig.r1
        plain.allowUnverifiedFallback = true
        let p = try generate(5, plain)
        var withEmpty = plain
        withEmpty.sites = []
        XCTAssertEqual(p.surface, try generate(5, withEmpty).surface)
        // 場所を足しても、地形と他の配置物は変わらない
        XCTAssertEqual(a.surface.terrain, p.surface.terrain)
        let others = a.surface.placements.all.filter { $0.templateID != "site.test.fort" }
        XCTAssertEqual(others.map(\.id), p.surface.placements.all.map(\.id))
    }
}
