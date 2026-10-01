import Foundation
import XCTest
@testable import RFMap

/// 層(地下などを後から足せる)・配置物・保存。
final class LayerAndCodableTests: XCTestCase {
    func testWorldMapRoundTripAfterPlay() throws {
        var m = MapFixture.r1Seed7
        var rng = SeededRandom(state: 4)
        m.updateVision(at: m.landmarks.farWreck, isNight: true, hasTorch: true)
        _ = m.extract(.outcrop, rng: &rng)
        var layer = m.surface
        layer.placements.update(.homeWreck) { $0.remainingUses = 3 }
        m.surface = layer
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(WorldMap.self, from: data)
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.surface.placements[.homeWreck]?.remainingUses, 3)
        XCTAssertEqual(back.visibility(at: m.landmarks.farWreck), .visible)
        // R1 の地図の保存の大きさ(目安)
        XCTAssertLessThan(data.count, 200_000, "保存が大きすぎる: \(data.count) bytes")
        print("RFMap: R1 の地図の保存 \(data.count) bytes")
    }

    func testProceduralRoundTrip() throws {
        let m = WorldMap.generate(seed: 21, config: .original)
        let back = try JSONDecoder().decode(WorldMap.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.biome(at: GridPoint(4321, 1234)), m.biome(at: GridPoint(4321, 1234)))
    }

    func testAddUndergroundLayer() {
        var m = MapFixture.r1Seed7
        let id = MapLayerID.underground(1)
        XCTAssertEqual(id.rawValue, "underground.1")
        // 地下の層: 地表と同じ大きさで、全部岩場の下地(地下の生成そのものは R2)
        let field = BiomeField(seed: 1, size: m.size,
                               thresholds: BiomeThresholds(ruinsContamination: 2, rockGeology: -1, waterMoisture: 2,
                                                           forestTemperature: 2, forestMoisture: 2))
        var under = MapLayer(id: id, terrain: TerrainGrid(field: field, denseCellLimit: 1 << 20))
        under.deposits.add(Deposit(id: DepositID("deep.0"), position: GridPoint(3, 3), category: .coal,
                                   appearanceVariant: 0, composition: [DepositComponent(.carbon, .percent(70))], extractions: 5))
        m.addLayer(under)
        XCTAssertEqual(m.layerIDs, [.surface, id])
        XCTAssertEqual(m.biome(at: GridPoint(3, 3), layer: id), .rock)
        // 層ごとに視界と経路は独立
        XCTAssertEqual(m.visibility(at: GridPoint(3, 3), layer: id), .unseen)
        m.updateVision(at: GridPoint(3, 3), isNight: true, hasTorch: false, layer: id)
        XCTAssertEqual(m.visibility(at: GridPoint(3, 3), layer: id), .visible)
        XCTAssertNotNil(m.findPath(from: GridPoint(3, 3), to: GridPoint(5, 5), layer: id))
        var rng = SeededRandom(state: 1)
        XCTAssertNotNil(m.extract(DepositID("deep.0"), layer: id, rng: &rng))
        XCTAssertEqual(m[layer: id]?.deposits[DepositID("deep.0")]?.remainingExtractions, 4)
        XCTAssertEqual(MapLocation(id, GridPoint(3, 3)).layer, id)
    }

    func testPlacementOverlapAndFootprints() {
        let l = TileFootprint(mask: "#.\n##")
        XCTAssertEqual(l.offsets, [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 1)])
        XCTAssertEqual(l.width, 2)
        XCTAssertEqual(l.height, 2)
        // 原作の TileLabel(全角スペースは空き)
        let label = TileFootprint(tileLabel: "炉\u{3000}\n台台")
        XCTAssertEqual(label.offsets, [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 1)])

        var layer = PlacementLayer()
        XCTAssertTrue(layer.place(MapPlacement(id: PlacementID("a"), kind: .module, templateID: "furnace",
                                               anchor: GridPoint(5, 5), footprint: l)))
        XCTAssertFalse(layer.canPlace(.single, at: GridPoint(6, 6)))
        XCTAssertTrue(layer.canPlace(.single, at: GridPoint(6, 5)), "L 字の空きには置ける")
        XCTAssertFalse(layer.place(MapPlacement(id: PlacementID("b"), kind: .module, templateID: "x",
                                                anchor: GridPoint(5, 6))))
        XCTAssertEqual(layer.placement(at: GridPoint(5, 6))?.id, PlacementID("a"))
        XCTAssertNotNil(layer.remove(PlacementID("a")))
        XCTAssertTrue(layer.canPlace(l, at: GridPoint(5, 5)))
    }

    func testIDsOnlyNoDisplayNames() throws {
        // 公開する型は真実の ID だけを持つ(表示名は Perception 層)。保存の JSON に日本語が入らない
        let json = String(decoding: try JSONEncoder().encode(MapFixture.r1Seed7), as: UTF8.self)
        XCTAssertNil(json.range(of: "[\\p{Script=Han}\\p{Script=Hiragana}\\p{Script=Katakana}]", options: .regularExpression))
    }
}
