import Foundation
import XCTest
import RFKernel
@testable import RFMap

/// 層(地下などを後から足せる)・配置物・保存。
final class LayerAndCodableTests: XCTestCase {
    func testWorldMapRoundTripAfterPlay() throws {
        var m = MapFixture.r1Seed7
        var rng = SeededRandom(state: 4)
        m.updateVision(at: m.lm.farWreck, isNight: true, hasTorch: true)
        _ = m.extract(.outcrop, rng: &rng)
        var layer = m.surface
        layer.placements.update(.homeWreck) { $0.remainingUses = 3 }
        m.surface = layer
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(WorldMap.self, from: data)
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.surface.placements[.homeWreck]?.remainingUses, 3)
        // 保存の形に小数が無い(RFKernel の Value にそのまま入る)
        XCTAssertNoThrow(try JSONDecoder().decode(Value.self, from: data))
        XCTAssertEqual(try JSONDecoder().decode(MapGenerationConfig.self, from: JSONEncoder().encode(m.config)), m.config)
        XCTAssertEqual(back.visibility(at: m.lm.farWreck), .visible)
        // R1 の地図の保存の大きさ(目安)
        XCTAssertLessThan(data.count, 200_000, "保存が大きすぎる: \(data.count) bytes")
        print("RFMap: R1 の地図の保存 \(data.count) bytes")
    }

    func testProceduralRoundTrip() throws {
        let m = try WorldMap.generate(seed: 21, config: .original)
        let back = try JSONDecoder().decode(WorldMap.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
        XCTAssertEqual(back.biome(at: GridPoint(4321, 1234)), m.biome(at: GridPoint(4321, 1234)))
    }

    func testLayerConnections() throws {
        var m = MapFixture.r1Seed7
        let under = MapLayerID.underground(1)
        m.addLayer(MapLayer(id: under, terrain: TerrainGrid(size: m.size, cells: Array(repeating: .rock, count: m.size.count))))
        let entrance = m.lm.outcrop
        m.connect(MapLocation(.surface, entrance), MapLocation(under, GridPoint(10, 10)), kind: .entrance, id: "cave.0")
        let c = try XCTUnwrap(m.surface.connections(at: entrance).first)
        XCTAssertEqual(c.kind, .entrance)
        XCTAssertEqual(c.to, MapLocation(under, GridPoint(10, 10)))
        XCTAssertFalse(c.isDiscovered)
        XCTAssertEqual(m[under]?.connections(at: GridPoint(10, 10)).first?.to, MapLocation(.surface, entrance))
        // 見えたら発見済み
        m.updateVision(at: entrance, isNight: false, hasTorch: false)
        XCTAssertTrue(m.surface.connections(at: entrance).first!.isDiscovered)
        // 保存しても残る
        let back = try JSONDecoder().decode(WorldMap.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back, m)
    }

    func testUnknownKindsDecode() throws {
        // 版をまたいで未知の種類(配置物・接続)も読める
        let p = MapPlacement(id: PlacementID("x"), kind: PlacementKind("futureKind"), templateID: "t", anchor: GridPoint(1, 1))
        let back = try JSONDecoder().decode(MapPlacement.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.kind.rawValue, "futureKind")
        XCTAssertFalse(PlacementKind.known.contains(back.kind))
        let c = LayerConnection(id: "a", kind: ConnectionKind("ladder"), at: GridPoint(0, 0), to: MapLocation(.surface, GridPoint(1, 1)))
        XCTAssertEqual(try JSONDecoder().decode(LayerConnection.self, from: JSONEncoder().encode(c)), c)
    }

    func testHandMadeMapAndEntities() throws {
        // 手で作る地図(平らな試験用)は目印を持たず、保存できる
        let flat = MapLayer(size: GridSize(width: 8, height: 6), palette: ["grass"], terrain: Array(repeating: 0, count: 48))
        let m = WorldMap(layers: [.surface: flat], baseArea: nil, spawn: WorldPoint(.surface, GridPoint(4, 3)))
        XCTAssertNil(m.landmarks)
        XCTAssertNil(m.generationReport)
        XCTAssertEqual(m.biome(at: GridPoint(0, 0)), .plain)
        XCTAssertEqual(try JSONDecoder().decode(WorldMap.self, from: JSONEncoder().encode(m)), m)
        // 小さい地図(設定の距離を縮める)でも保存で往復して同じ
        for side in [5, 33, 47] {
            let small = WorldMap(layers: [.surface: MapLayer(size: GridSize(width: side, height: side), palette: ["grass"],
                                                              terrain: Array(repeating: 0, count: side * side))],
                                 baseArea: nil, spawn: WorldPoint(.surface, GridPoint(0, 0)))
            XCTAssertEqual(try JSONDecoder().decode(WorldMap.self, from: JSONEncoder().encode(small)), small, "\(side)")
        }

        // 生成の約束(MapGenerating)は配置物に世界の実体 ID を振る(決定的)
        var next = 0
        var rng = SeededRandom(state: 7)
        let g = RFMapGenerator().generate(config: MapGenConfig(size: .r1), terrains: [:], rng: &rng) {
            next += 1
            return EntityID(next)
        }
        var mm = try WorldMap.generate(seed: 7)
        var n = 0
        mm.assignEntities { n += 1; return EntityID(n) }
        XCTAssertEqual(g.surface, mm.surface)
        XCTAssertEqual(g.landmarks, mm.landmarks)
        XCTAssertEqual(g.generationReport?.verified, true)
        XCTAssertTrue(g.surface.placements.all.allSatisfy { $0.entity != nil })
        let pois = g.surface.pois
        XCTAssertEqual(pois.count, g.surface.placements.all.count)
        let far = g.surface.placements[.farWreck]!
        XCTAssertEqual(pois[far.entity!]?.at, far.anchor)
        XCTAssertEqual(pois[far.entity!]?.kind, "wreck.far")
    }

    func testAddUndergroundLayer() {
        var m = MapFixture.r1Seed7
        let id = MapLayerID.underground(1)
        XCTAssertEqual(id.rawValue, "layer.underground.1")
        // 地下の層: 地表と同じ大きさで、全部岩場の下地(地下の生成そのものは R2)
        let field = BiomeField(seed: 1, size: m.size,
                               thresholds: BiomeThresholds(ruinsContamination: 2, rockGeology: -1, waterMoisture: 2,
                                                           forestTemperature: 2, forestMoisture: 2))
        var under = MapLayer(id: id, terrain: TerrainGrid(field: field, denseCellLimit: 1 << 20))
        under.deposits.add(Deposit(id: DepositID("deep.0"), position: GridPoint(3, 3), category: .coal,
                                   appearanceVariant: 0, composition: [DepositComponent(.carbon, Purity(percent: 70))], extractions: 5))
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
        XCTAssertEqual(m[id]?.deposits[DepositID("deep.0")]?.remainingExtractions, 4)
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
