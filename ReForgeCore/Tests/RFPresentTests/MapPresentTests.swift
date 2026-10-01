import Foundation
import RFContent
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U13 の受け入れテスト(F-work-units.md): 区画の版が変わった所だけ上がる / 補間の材料 / 霧の 3 状態と手がかり /
/// 視点(ピンチ 3 段・見回し・◎)/ 調べる・足元カード / 上の帯。
final class MapPresentTests: XCTestCase {
    var rig: TestRig!
    var builder: FrameBuilder!

    override func setUpWithError() throws {
        rig = try TestRig.publicOnly()
        builder = FrameBuilder(content: rig.content)
    }

    func world() -> WorldState { rig.factory.newWorld(seed: 1) }

    func know(_ w: inout WorldState, _ pts: [GridPoint]) {
        var bits = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
        for p in pts { bits[p] = true }
        w.knowledge.mapKnown[.surface] = bits
    }

    // MARK: - 区画の版

    /// 地形・既知の変化は、そのマスを含む区画の版だけを上げる(印が付いていなくても中身の指紋で気づく)。
    func testChunkRevisionsRiseOnlyWhereTilesChanged() {
        var w = world()
        let f1 = builder.build(w, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(f1.map.chunkRevisions, [1, 1, 1, 1])

        know(&w, [GridPoint(2, 2)])
        let f2 = builder.build(w, revision: 2, previous: f1, report: StepReport())
        XCTAssertEqual(f2.map.chunkRevisions, [2, 1, 1, 1], "既知が増えた区画だけ")

        w.map[.surface]!.setTerrain("rock", at: GridPoint(20, 20))
        let f3 = builder.build(w, revision: 3, previous: f2, report: StepReport())
        XCTAssertEqual(f3.map.chunkRevisions, [2, 1, 1, 3], "地形が変わった区画だけ")

        let f4 = builder.build(w, revision: 4, previous: f3, report: StepReport())
        XCTAssertEqual(f4.map.chunkRevisions, f3.map.chunkRevisions, "何も変わらなければ上がらない")

        var dirty = StepReport()
        dirty.changes.markTile(WorldPoint(.surface, GridPoint(20, 3)), .fog)
        let f5 = builder.build(w, revision: 5, previous: f4, report: dirty)
        XCTAssertEqual(f5.map.chunkRevisions, [2, 5, 1, 3], "印の付いたマスの区画は上げる")

        var perception = StepReport()
        perception.changes.mark(.perception)
        let f6 = builder.build(w, revision: 6, previous: f5, report: perception)
        XCTAssertEqual(f6.map.chunkRevisions, [6, 6, 6, 6], "知っている事実が変わったら全区画(遡る書き換え)")
    }

    /// 歩いて視界が動くだけでは区画を作り直さない(視界は MapView.vision で別に渡す)。
    func testWalkingMovesVisionWithoutRebuildingChunks() {
        var w = world()
        let f1 = builder.build(w, revision: 1, previous: nil, report: nil)
        let noahVision = f1.map.vision.first { $0.center == GridPoint(16, 16) }
        XCTAssertEqual(noahVision?.radius, 8, "昼の視界は半径 8")
        w.people[.noah]!.position = WorldPoint(.surface, GridPoint(4, 4))
        let f2 = builder.build(w, revision: 2, previous: f1, report: StepReport())
        XCTAssertEqual(f2.map.chunkRevisions, f1.map.chunkRevisions)
        XCTAssertTrue(f2.map.vision.contains { $0.center == GridPoint(4, 4) })
        XCTAssertTrue(f2.map.isVisible(GridPoint(4, 12)))
        XCTAssertFalse(f2.map.isVisible(GridPoint(10, 10)) && !f2.map.vision.contains { $0.center == GridPoint(16, 16) })

        w.clock.phase = .dusk
        let f3 = builder.build(w, revision: 3, previous: f2, report: StepReport())
        XCTAssertEqual(f3.map.vision.first?.radius, 5, "夜の視界は半径 5")
    }

    /// 区画の中身は、画面が引いたときの版と一致し、行優先で並ぶ。
    func testHostServesChunksForChangedRevisions() async throws {
        var w = world()
        know(&w, [GridPoint(17, 1)])
        let host = GameHost(simulation: rig.simulation, world: w)
        let chunks = await host.chunks([1, 99])
        XCTAssertEqual(chunks.count, 1, "範囲外の番号は無視する")
        let c = try XCTUnwrap(chunks.first)
        XCTAssertEqual(c.rect, GridRect(origin: GridPoint(16, 0), size: GridSize(width: 16, height: 16)))
        XCTAssertEqual(c.tiles.count, 256)
        XCTAssertEqual(c.tile(at: GridPoint(17, 1))?.fog, .remembered)
        XCTAssertEqual(c.tile(at: GridPoint(17, 1))?.glyph, "ψ")
        XCTAssertEqual(c.tile(at: GridPoint(18, 1))?.fog, .unknown)
    }

    // MARK: - 霧の 3 状態と手がかりの影

    func testFogStatesAndHintShadow() {
        var w = world()
        _ = w.map[.surface]!.placements.place(MapPlacement(id: "poi.test", kind: .wreck, templateID: "poi.test.wreck",
                                                           anchor: GridPoint(3, 3), footprint: .rect(width: 2, height: 1),
                                                           entity: EntityID(900)))
        XCTAssertEqual(builder.tile(w, at: GridPoint(1, 1)).fog, .unknown, "未踏は黒")
        XCTAssertEqual(builder.tile(w, at: GridPoint(3, 3)).fog, .unknown, "既知から遠い目印は見えない")
        know(&w, [GridPoint(1, 1), GridPoint(2, 2)])
        XCTAssertEqual(builder.tile(w, at: GridPoint(1, 1)).fog, .remembered, "既知は暗い地形だけ")
        let anchor = builder.tile(w, at: GridPoint(3, 3))
        XCTAssertEqual(anchor.fog, .hint, "既知から 2 マス以内の目印は影")
        XCTAssertEqual(anchor.shadow, "？")
        XCTAssertEqual(builder.tile(w, at: GridPoint(4, 3)).shadow, builder.tile(w, at: GridPoint(3, 3)).glyph,
                       "目印のほかのマスは目印の文字の影")
        XCTAssertEqual(builder.tile(w, at: GridPoint(16, 20)).fog, .visible, "視界の中")
        XCTAssertNil(builder.tile(w, at: GridPoint(16, 20)).shadow)
        XCTAssertEqual(builder.tile(w, at: GridPoint(-1, 0)), .void)
    }

    /// 会った人(一員でない)は視界の中だけに描く。一員は視界の外でも描く。
    func testActorsOutsideVision() {
        var w = world()
        w.people[PersonID("person.test_c")]!.presence = .met(at: .zero)
        w.people[PersonID("person.test_c")]!.position = WorldPoint(.surface, GridPoint(1, 1))
        w.people[PersonID("person.test_a")]!.position = WorldPoint(.surface, GridPoint(30, 30))
        let f = builder.build(w, revision: 1, previous: nil, report: nil)
        XCTAssertFalse(f.actors.contains { $0.id == "person.test_c" }, "視界の外の会った人は描かない")
        XCTAssertTrue(f.actors.contains { $0.id == "person.test_a" && $0.isMember })
        w.people[PersonID("person.test_c")]!.position = WorldPoint(.surface, GridPoint(16, 18))
        let f2 = builder.build(w, revision: 2, previous: f, report: nil)
        XCTAssertEqual(f2.actors.first { $0.id == "person.test_c" }?.tint, TilePalette.stranger)
    }

    // MARK: - 主人公・経路・補間

    func testNoahFacingArrowRouteAndInterpolation() throws {
        var w = world()
        w.people[.noah]!.facing = .east
        w.people[.noah]!.motion = Motion(path: [GridPoint(17, 16), GridPoint(18, 16)], progress: 500)
        let f = builder.build(w, revision: 1, previous: nil, report: nil)
        let noah = try XCTUnwrap(f.actors.first { $0.isNoah })
        XCTAssertEqual(noah.glyph, "→")
        XCTAssertEqual(noah.tint, TilePalette.noah)
        XCTAssertEqual(f.route, [GridPoint(17, 16), GridPoint(18, 16)], "点線の経路")
        XCTAssertEqual(f.focus, GridPoint(16, 16))
        XCTAssertEqual(noah.from, GridPoint(16, 16))
        XCTAssertEqual(noah.to, GridPoint(17, 16))
        XCTAssertEqual(noah.position(elapsed: 0).x, 17.0, accuracy: 1e-9, "進み 500 = 半分")
        XCTAssertEqual(noah.position(elapsed: 0.0625).x, 17.25, accuracy: 1e-9, "1 秒 4 マスで先へ")
        XCTAssertEqual(noah.position(elapsed: 5).x, 17.5, accuracy: 1e-9, "次のマスで止まる")
        XCTAssertEqual(noah.position(elapsed: 5).y, 16.5, accuracy: 1e-9)
        XCTAssertTrue(noah.isMoving)
        for d in Direction.allCases { XCTAssertEqual(ActorSprite.arrow(d), ["north": "↑", "east": "→", "south": "↓", "west": "←"][d.rawValue]) }

        w.people[.noah]!.motion = nil
        let still = try XCTUnwrap(builder.build(w, revision: 2, previous: f, report: nil).actors.first { $0.isNoah })
        XCTAssertFalse(still.isMoving)
        XCTAssertEqual(still.position(elapsed: 3), MapPointF(x: 16.5, y: 16.5))
    }

    // MARK: - 視点

    func testCameraSnapsPinchToThreeLevels() {
        XCTAssertEqual(MapCamera.cellSizes, [18, 24, 32])
        XCTAssertEqual(MapCamera.snappedZoom(from: 1, pinchScale: 1.0), 1)
        XCTAssertEqual(MapCamera.snappedZoom(from: 1, pinchScale: 1.1), 1)
        XCTAssertEqual(MapCamera.snappedZoom(from: 1, pinchScale: 1.3), 2)
        XCTAssertEqual(MapCamera.snappedZoom(from: 1, pinchScale: 0.8), 0)
        XCTAssertEqual(MapCamera.snappedZoom(from: 0, pinchScale: 10), 2, "大きく開いても 32pt まで")
        XCTAssertEqual(MapCamera.snappedZoom(from: 2, pinchScale: 0.01), 0)
        XCTAssertEqual(MapCamera.snappedZoom(from: 2, pinchScale: .nan), 2)
    }

    func testCameraTapTargetsPanAndRecenter() {
        let view = ScreenSize(width: 240, height: 480)
        var cam = MapCamera(center: MapPointF(x: 16.5, y: 16.5), zoom: 1)
        XCTAssertEqual(cam.cell(at: ScreenPoint(x: 120, y: 240), in: view), GridPoint(16, 16), "画面の中央はノアのマス")
        XCTAssertEqual(cam.cell(at: ScreenPoint(x: 120 + 24, y: 240 - 24), in: view), GridPoint(17, 15))
        XCTAssertEqual(cam.cell(at: ScreenPoint(x: 120 - 13, y: 240), in: view), GridPoint(15, 16))
        let o = cam.screenOrigin(of: GridPoint(17, 15), in: view)
        XCTAssertEqual(o.x, 132, accuracy: 1e-9)
        XCTAssertEqual(o.y, 204, accuracy: 1e-9)
        let r = cam.visibleCells(in: view)
        XCTAssertEqual(r.origin, GridPoint(11, 6))
        XCTAssertEqual(r.size, GridSize(width: 11, height: 21))

        cam.pan(byScreen: 48, 0, mapSize: GridSize(width: 32, height: 32))
        XCTAssertFalse(cam.following, "見回すと追従が外れる")
        XCTAssertEqual(cam.center.x, 14.5, accuracy: 1e-9)
        cam.follow(MapPointF(x: 20, y: 20))
        XCTAssertEqual(cam.center.x, 14.5, accuracy: 1e-9, "追従が外れている間は動かない")
        cam.pan(byScreen: 10_000, 10_000, mapSize: GridSize(width: 32, height: 32))
        XCTAssertEqual(cam.center, MapPointF(x: 0, y: 0), "地図の外へ行き過ぎない")
        cam.recenter(on: MapPointF(x: 16.5, y: 16.5))
        XCTAssertTrue(cam.following, "◎ で戻る")
        cam.follow(MapPointF(x: 17, y: 16.5))
        XCTAssertEqual(cam.center.x, 17)
    }

    func testVisionAreaIsEuclideanCircleWithRowSpans() {
        let v = VisionArea(center: GridPoint(10, 10), radius: 8)
        XCTAssertTrue(v.contains(GridPoint(18, 10)))
        XCTAssertFalse(v.contains(GridPoint(18, 11)))
        XCTAssertTrue(v.contains(GridPoint(15, 16)), "5² + 6² = 61 ≤ 64")
        XCTAssertFalse(v.contains(GridPoint(16, 16)), "6² + 6² = 72 > 64")
        let spans = v.rowSpans
        XCTAssertEqual(spans.count, 17)
        for s in spans {
            for x in (s.minX - 1)...(s.maxX + 1) {
                XCTAssertEqual(v.contains(GridPoint(x, s.y)), x >= s.minX && x <= s.maxX)
            }
        }
        XCTAssertEqual(VisionRadiusRule().radius(phase: .nightWork, hasLight: true), 9)
    }

    // MARK: - 色と文字

    func testPaletteAndGlyphVariation() {
        let t = rig.content.terrains
        XCTAssertEqual(TilePalette.style(TilePalette.terrain("water"), terrains: t).background, RGB(30, 50, 90), "水辺は青背景")
        XCTAssertNil(TilePalette.style(TilePalette.terrain("grass"), terrains: t).background)
        XCTAssertEqual(TilePalette.style(TilePalette.deposit("iron_ore"), terrains: t).foreground, [RGB(180, 100, 70)])
        XCTAssertEqual(TilePalette.pickGlyph("ψ", at: GridPoint(3, 4)), "ψ")
        var seen = Set<String>()
        for x in 0..<20 { seen.insert(TilePalette.pickGlyph(". ,", at: GridPoint(x, 7))) }
        XCTAssertEqual(seen, [".", ","], "地面は . と , が座標で揺らぐ")
        XCTAssertEqual(TilePalette.pickGlyph(". ,", at: GridPoint(5, 5)), TilePalette.pickGlyph(". ,", at: GridPoint(5, 5)))
        XCTAssertEqual(RGB(100, 200, 50).scaled(0.5), RGB(50, 100, 25))
    }

    // MARK: - 調べる・足元カード

    func contentWithInteractions() throws -> ContentDB {
        var db = rig.content
        // 他の担当が公開の層に足した行為を外し、このテストの行為だけで見る
        db.interactions.removeAll()
        let json = """
        {
          "interactions": [
            { "id": "interaction.test.present.dig", "target": { "deposit": {} }, "seconds": 60, "hold": true, "yields": [] },
            { "id": "interaction.test.present.pick", "target": { "terrain": { "tag": "ground" } }, "seconds": 30,
              "hold": false, "yields": [] },
            { "id": "interaction.test.present.night", "target": { "terrain": { "tag": "ground" } }, "seconds": 30,
              "hold": false, "allowedPhases": ["nightWork"], "yields": [] },
            { "id": "interaction.test.present.gated", "target": { "terrain": { "tag": "ground" } }, "seconds": 30,
              "hold": false, "when": { "known": { "expr": "fact.test.alpha" } }, "yields": [] }
          ],
          "perception": [
            { "subject": "deposit:iron.0", "variants": [ { "when": true, "name": "text.test.present.vein" } ] },
            { "subject": "interaction:interaction.test.present.dig", "variants": [ { "when": true, "name": "text.test.present.dig" } ] },
            { "subject": "interaction:interaction.test.present.pick", "variants": [ { "when": true, "name": "text.test.present.pick" } ] }
          ],
          "texts": { "text.test.present.vein": "試験の岩脈", "text.test.present.dig": "掘る", "text.test.present.pick": "拾う" }
        }
        """
        try ContentLoader.apply(json: Data(json.utf8), to: &db)
        return db
    }

    func testInspectShowsNameRemainingAndTouch() throws {
        let b = FrameBuilder(content: try contentWithInteractions())
        var w = world()
        let vein = GridPoint(18, 16)
        _ = w.map[.surface]!.deposits.add(Deposit(id: DepositID("test.vein"), position: vein, category: .iron,
                                                  appearanceVariant: 0,
                                                  composition: [DepositComponent(.fe2o3, Purity(percent: 31))],
                                                  extractions: 7))
        let i = try XCTUnwrap(b.inspect(w, at: vein))
        XCTAssertEqual(i.title, "草地")
        XCTAssertEqual(i.lines, [.name("試験の岩脈"), .remaining(7)], "見つけるまでは手ざわりが無い")
        w.map[.surface]!.deposits.update(DepositID("test.vein")) { $0.isDiscovered = true }
        XCTAssertEqual(b.inspect(w, at: vein)?.lines.last, .purityTenths(3), "三割くらい")
        XCTAssertEqual(b.inspect(w, at: GridPoint(0, 0)), TileInspection(point: GridPoint(0, 0), title: "？", lines: []),
                       "未踏は「？」だけ")
        XCTAssertNil(b.inspect(w, at: GridPoint(99, 99)))
        XCTAssertEqual(b.tile(w, at: vein).glyph, "晶", "鉱脈の既定の文字")
    }

    func testFootCardListsApplicableActions() throws {
        let b = FrameBuilder(content: try contentWithInteractions())
        var w = world()
        let vein = GridPoint(18, 16)
        _ = w.map[.surface]!.deposits.add(Deposit(id: DepositID("test.vein"), position: vein, category: .iron,
                                                  appearanceVariant: 0,
                                                  composition: [DepositComponent(.fe2o3, Purity(percent: 31))],
                                                  extractions: 7))
        let card = try XCTUnwrap(b.footCard(w, at: vein))
        XCTAssertEqual(card.title, "試験の岩脈")
        XCTAssertEqual(card.actions.map(\.label), ["掘る", "拾う"], "昼だけ・条件の成り立たない行為は出さない")
        XCTAssertTrue(card.actions[0].hold)
        XCTAssertEqual(card.actions[0].start, .exploration(.interact(interaction: "interaction.test.present.dig",
                                                                     at: WorldPoint(.surface, vein), holding: true)))
        XCTAssertEqual(card.actions[0].end, .exploration(.interact(interaction: "interaction.test.present.dig",
                                                                   at: WorldPoint(.surface, vein), holding: false)))
        XCTAssertEqual(b.footCard(w, at: GridPoint(0, 0))?.actions, [], "未踏のマスではできることを出さない")

        var ctx = StepContext(world: w, content: b.content)
        ctx.learn("fact.test.alpha")
        w = ctx.world
        w.clock.phase = .nightWork
        let night = try XCTUnwrap(b.footCard(w, at: GridPoint(16, 17)))
        XCTAssertEqual(night.actions.map(\.id.rawValue),
                       ["interaction.test.present.gated", "interaction.test.present.night", "interaction.test.present.pick"])
        XCTAssertEqual(night.actions.first?.label, "？", "名前の無い行為は英語の ID を出さない")
    }

    // MARK: - 上の帯

    func testBandShowsObjectiveAndTimeChoicesWithoutSheets() {
        var w = world()
        let f = builder.build(w, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(f.objective, "試験の目標")
        XCTAssertEqual(f.clock.bandActions, [])
        XCTAssertGreaterThan(f.clock.dayRemainingPermille, 990)
        w.clock.phase = .dusk
        XCTAssertEqual(builder.build(w, revision: 2, previous: f, report: nil).clock.bandActions, [.startNightWork, .sleep])
        w.clock.phase = .nightWork
        let n = builder.build(w, revision: 3, previous: f, report: nil)
        XCTAssertEqual(n.clock.bandActions, [.sleep])
        XCTAssertTrue(n.clock.isNight)
        XCTAssertEqual(BandAction.sleep.command, .time(.sleep))
        XCTAssertEqual(BandAction.startNightWork.command, .time(.startNightWork))
        w.run.outcome = .failed(cause: "text.test.cause", record: nil)
        XCTAssertTrue(builder.build(w, revision: 4, previous: n, report: nil).runEnded)
    }

    // MARK: - 立ち上げ

    func testBootstrapLoadsBundledContentAndGeneratesMap() throws {
        let content = try GameBootstrap.loadContent(contentDirectory: TestContent.repoRoot.appendingPathComponent("content"),
                                                    key: nil)
        let w = GameBootstrap.newWorld(content: content, seed: 7)
        let l = try XCTUnwrap(w.map[.surface])
        XCTAssertEqual(l.size.width, max(MapGenerationConfig.minimumSide, content.mapGen.size.width), "小さい指定は生成器の最小まで広がる")
        let biomes = Set((0..<l.size.height).flatMap { y in (0..<l.size.width).compactMap { l.biome(at: GridPoint($0, y)) } })
        XCTAssertTrue(biomes.contains(.river), "川がある")
        XCTAssertTrue(biomes.contains(.rock), "岩場がある")
        let spawnTerrain = try XCTUnwrap(l.terrain(at: w.map.spawn.point))
        XCTAssertEqual(content.terrains[spawnTerrain]?.passable, true, "目覚める場所は歩ける地面")
        XCTAssertEqual(content.terrains[spawnTerrain]?.isWater, false)
        XCTAssertEqual(w, GameBootstrap.newWorld(content: content, seed: 7), "同じ seed で同じ世界")
    }

    /// 断られた操作は理由の 1 行になる(ダイアログは出さない)。
    func testPerformReturnsReadableRejection() async throws {
        let host = GameHost(simulation: rig.simulation, world: world())
        let (_, reason) = await host.perform(.time(.sleep))
        XCTAssertEqual(reason, "まだ昼だ")
    }
}
