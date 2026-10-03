import Foundation
import RFKernel
import XCTest
@testable import RFMap

/// W-23 始まりの置き場と森の保証。種の数は REFORGE_O12_SEEDS(手元の既定 1000)。
final class OpeningSiteTests: XCTestCase {
    static var seeds: Int { ProcessInfo.processInfo.environment["REFORGE_O12_SEEDS"].flatMap { Int($0) } ?? 1000 }

    func testForestAndFireSiteOnEverySeed() throws {
        for seed in UInt64(0)..<UInt64(Self.seeds) {
            let m = try WorldMap.generate(seed: seed)
            let r = m.config.opening!
            let layer = m.surface
            let start = m.lm.base.center
            let reach = start.neighbors8.filter { layer.biome(at: $0) == .forest }.count
            XCTAssertGreaterThanOrEqual(reach, r.startReachForestMin, "seed \(seed): 始まりの隣の森")
            let site = try XCTUnwrap(layer.firstFireSite, "seed \(seed): 火の置き場が無い")
            XCTAssertTrue([Biome.plain, .cleared].contains(layer.biome(at: site)), "seed \(seed): 置き場が乾いた陸でない")
            XCTAssertFalse(layer.placements.isOccupied(site), "seed \(seed): 置き場が塞がっている")
            var light = 0
            for y in (site.y - 2)...(site.y + 2) {
                for x in (site.x - 2)...(site.x + 2) where layer.biome(at: GridPoint(x, y)) == .forest { light += 1 }
            }
            XCTAssertGreaterThanOrEqual(light, r.firstLightForestMin, "seed \(seed): 置き場のまわりの森")
        }
    }

    func testDawnFindSiteOnEverySeed() throws {
        let day = VisionRule.original.radius(isNight: false, hasTorch: false)
        for seed in UInt64(0)..<UInt64(Self.seeds) {
            let m = try WorldMap.generate(seed: seed)
            let r = m.config.opening!
            let layer = m.surface
            let fire = try XCTUnwrap(layer.firstFireSite, "seed \(seed)")
            let site = try XCTUnwrap(layer.dawnFindSite, "seed \(seed): 夜明けの置き場が無い")
            XCTAssertFalse(VisionRule.inCircle(site, center: fire, radius: r.firstNightLightRadius),
                           "seed \(seed): 最初の夜の灯りの中")
            XCTAssertTrue(VisionRule.inCircle(site, center: fire, radius: day), "seed \(seed): 昼の視界の外")
            XCTAssertFalse(m.lm.base.center.neighbors8.contains(site), "seed \(seed): ノアの隣")
            XCTAssertTrue([Biome.plain, .cleared].contains(layer.biome(at: site)), "seed \(seed): 乾いた陸でない")
            XCTAssertFalse(layer.placements.isOccupied(site), "seed \(seed): 塞がっている")
            XCTAssertNotEqual(site, fire)
        }
    }

    func testSitesAreDeterministic() throws {
        for seed in [UInt64(3), 77, 999] {
            let a = try WorldMap.generate(seed: seed).surface, b = try WorldMap.generate(seed: seed).surface
            XCTAssertEqual(a.firstFireSite, b.firstFireSite)
            XCTAssertEqual(a.dawnFindSite, b.dawnFindSite)
        }
    }

    /// 新しい欄が無い層(古い保存)は nil で読め、nil の欄は書き出さない。
    func testOldLayerDecodesAsNilAndNilIsOmitted() throws {
        var m = try WorldMap.generate(seed: 1).surface
        m.firstFireSite = nil
        m.dawnFindSite = nil
        let data = try JSONEncoder().encode(m)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("firstFireSite") || text.contains("dawnFindSite"))
        let back = try JSONDecoder().decode(MapLayer.self, from: data)
        XCTAssertNil(back.firstFireSite)
        XCTAssertNil(back.dawnFindSite)
        m.firstFireSite = GridPoint(1, 2)
        XCTAssertEqual(try JSONDecoder().decode(MapLayer.self, from: JSONEncoder().encode(m)).firstFireSite, GridPoint(1, 2))
    }

    /// 新しい欄が無い設定(古い保存)は既定で読む。
    func testOldRulesDecodeWithDefaults() throws {
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(OpeningRules.r1)) as? [String: Any])
        for k in ["startReachForestMin", "firstLightForestMin", "firstNightLightRadius"] { obj[k] = nil }
        let r = try JSONDecoder().decode(OpeningRules.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(r.startReachForestMin, 1)
        XCTAssertEqual(r.firstLightForestMin, 2)
        XCTAssertEqual(r, OpeningRules.r1)
    }
}
