import Foundation
import RFContent
import RFExploration
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// A-05: 採った後のクールダウン中の森のマスは、字(∴)と色(地面の暗い色)の両方で見分けられる。
final class SpentTilesTests: XCTestCase {
    var rig: TestRig!
    var builder: FrameBuilder!
    let pick: InteractionID = "interaction.pick_sticks"

    override func setUpWithError() throws {
        rig = try TestRig.publicOnly()
        builder = FrameBuilder(content: rig.content)
    }

    /// 森のマスが 2 つ(隣り合う)と、そばにいるノアの世界。
    func forestWorld() -> (w: WorldState, cell: GridPoint, other: GridPoint) {
        var w = rig.factory.newWorld(seed: 1)
        let cell = w.map.spawn.point + GridPoint(1, 0)
        let other = cell + GridPoint(0, 1)
        w.map[.surface]?.setTerrain("forest", at: cell)
        w.map[.surface]?.setTerrain("forest", at: other)
        var bits = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
        bits[cell] = true
        bits[other] = true
        w.knowledge.mapKnown[.surface] = bits
        w.people[.noah]?.position = WorldPoint(.surface, w.map.spawn.point)
        w.people[.noah]?.motion = nil
        return (w, cell, other)
    }

    /// 行為を送って終わるまで進める。
    @discardableResult
    func pickAt(_ w: inout WorldState, _ cell: GridPoint) -> (report: StepReport, rejection: Rejection?) {
        var all = StepReport()
        let r = rig.simulation.apply(.exploration(.interact(interaction: pick, at: WorldPoint(.surface, cell), holding: true)), to: &w)
        all.merge(r)
        if let rej = r.rejection { return (all, rej) }
        var n = 0
        while w.exploration.active[.noah] != nil && n < 2000 {
            all.merge(rig.simulation.runSteps(1, &w))
            n += 1
        }
        return (all, nil)
    }

    /// 日が 1 つ変わるまで進める。
    func advanceOneDay(_ w: inout WorldState) -> StepReport {
        var all = StepReport()
        let start = w.clock.day
        var n = 0
        while w.clock.day == start && n < 200_000 {
            if w.clock.phase == .day {
                all.merge(rig.simulation.advance(&w, realSeconds: 1))
            } else {
                all.merge(rig.simulation.runSteps(100, &w))
            }
            n += 1
        }
        return all
    }

    // 1 + 2
    func testPickingMakesTheTileSpentAndOnlyThatChunkRises() throws {
        var (w, cell, other) = forestWorld()
        let f0 = builder.build(w, revision: 1, previous: nil, report: nil)
        let before = builder.tile(w, at: cell)
        let otherBefore = builder.tile(w, at: other)
        XCTAssertNotEqual(before.glyph, TilePalette.spentGlyph)
        XCTAssertEqual(before.tint, "terrain.forest")

        let (report, rej) = pickAt(&w, cell)
        XCTAssertNil(rej)
        let after = builder.tile(w, at: cell)
        XCTAssertEqual(after.glyph, TilePalette.spentGlyph)
        XCTAssertEqual(after.tint, "terrain.forest.spent")
        XCTAssertEqual(builder.tile(w, at: other), otherBefore, "隣の森のマスは変わらない")
        XCTAssertTrue(report.changes.dirtyTiles.contains(WorldPoint(.surface, cell)), "採った時にマスへ印を付ける")

        // 区画の版: 採った印だけで、そのマスの区画だけが上がる(世界はほかを動かさない形にして比べる)
        var w2 = forestWorld().w
        w2.exploration.harvestedDay[ExplorationState.countKey(pick, poi: nil, at: WorldPoint(.surface, cell))] = w2.clock.day
        var marked = StepReport()
        marked.changes.markTile(WorldPoint(.surface, cell))
        let f1 = builder.build(w2, revision: 2, previous: f0, report: marked)
        let ci = try XCTUnwrap(f1.map.chunkIndex(of: cell))
        for i in 0..<f1.map.chunkRevisions.count {
            if i == ci {
                XCTAssertEqual(f1.map.chunkRevisions[i], 2)
            } else {
                XCTAssertEqual(f1.map.chunkRevisions[i], f0.map.chunkRevisions[i], "ほかの区画は上がらない")
            }
        }
    }

    // 3
    func testSpentTileReturnsAfterCooldown() throws {
        var (w, cell, _) = forestWorld()
        pickAt(&w, cell)
        let cd = try XCTUnwrap(rig.content.interactions[pick]?.cooldownDays)
        XCTAssertEqual(cd, 5)
        let harvested = try XCTUnwrap(w.exploration.harvestedDay.values.first)
        var rev = 1
        var f = builder.build(w, revision: rev, previous: nil, report: nil)
        while w.clock.day - harvested < cd - 1 {
            let r = advanceOneDay(&w)
            rev += 1
            f = builder.build(w, revision: rev, previous: f, report: r)
        }
        XCTAssertEqual(w.clock.day - harvested, 4)
        XCTAssertEqual(builder.tile(w, at: cell).glyph, TilePalette.spentGlyph, "4 日後はまだ使い切り")

        let ci = try XCTUnwrap(f.map.chunkIndex(of: cell))
        let revBefore = f.map.chunkRevisions[ci]
        let r = advanceOneDay(&w)
        XCTAssertEqual(w.clock.day - harvested, cd)
        XCTAssertTrue(r.changes.dirtyTiles.contains(WorldPoint(.surface, cell)), "明けた日にマスへ印を付ける")
        rev += 1
        let f2 = builder.build(w, revision: rev, previous: f, report: r)
        XCTAssertNotEqual(builder.tile(w, at: cell).glyph, TilePalette.spentGlyph)
        XCTAssertEqual(builder.tile(w, at: cell).tint, "terrain.forest")
        XCTAssertGreaterThan(f2.map.chunkRevisions[ci], revBefore)
    }

    // 4
    func testViewAgreesWithCheckLimits() throws {
        var (w, cell, other) = forestWorld()
        pickAt(&w, cell)
        XCTAssertEqual(builder.tile(w, at: cell).glyph, TilePalette.spentGlyph)
        XCTAssertEqual(pickAt(&w, cell).rejection?.reason, "reason.explore.cooldown", "使い切りのマスは断られる")
        XCTAssertNil(builder.footCard(w, at: cell)?.actions.first { $0.id == pick }, "拾えないマスにボタンは出さない")
        XCTAssertNotEqual(builder.tile(w, at: other).glyph, TilePalette.spentGlyph)
        XCTAssertNotNil(builder.footCard(w, at: other)?.actions.first { $0.id == pick })
        XCTAssertNil(pickAt(&w, other).rejection, "使い切りでないマスは通る")
    }

    // 5
    func testSpentSurvivesSaveAndLoad() throws {
        var (w, cell, other) = forestWorld()
        pickAt(&w, cell)
        let restored = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(builder.tile(restored, at: cell), builder.tile(w, at: cell))
        XCTAssertEqual(builder.tile(restored, at: cell).glyph, TilePalette.spentGlyph)
        XCTAssertEqual(builder.tile(restored, at: other), builder.tile(w, at: other))
    }

    // 6
    func testPaletteAndGlyphDiffer() throws {
        let terrains = rig.content.terrains
        let forest = TilePalette.style("terrain.forest", terrains: terrains)
        let spent = TilePalette.style("terrain.forest.spent", terrains: terrains)
        XCTAssertNotEqual(forest.foreground, spent.foreground)
        XCTAssertNil(spent.background)
        let ground = TilePalette.style("terrain.ground", terrains: terrains).foreground
        XCTAssertEqual(spent.foreground, ground.map { $0.scaled(0.6) })
        let (w, cell, other) = forestWorld()
        XCTAssertNotEqual(builder.tile(w, at: cell).glyph, TilePalette.spentGlyph)
        XCTAssertNotEqual(builder.tile(w, at: other).glyph, TilePalette.spentGlyph)
    }

    // A-06: 使い切りのマスの呼び名
    func testSpentTileNamesFollowTheSpentVariant() throws {
        var (w, cell, other) = forestWorld()
        let plain = builder.footCard(w, at: cell)?.title
        XCTAssertEqual(plain, "森")
        pickAt(&w, cell)
        let spentTitle = try XCTUnwrap(builder.footCard(w, at: cell)?.title)
        XCTAssertNotEqual(spentTitle, plain)
        XCTAssertEqual(builder.inspect(w, at: cell)?.title, spentTitle)
        XCTAssertEqual(builder.footCard(w, at: other)?.title, plain, "元のマスは元の名前")
        XCTAssertEqual(builder.inspect(w, at: other)?.title, plain)
        let harvested = try XCTUnwrap(w.exploration.harvestedDay.values.first)
        while w.clock.day - harvested < 5 { _ = advanceOneDay(&w) }
        XCTAssertEqual(builder.footCard(w, at: cell)?.title, plain, "明けたら元に戻る")
        XCTAssertEqual(builder.inspect(w, at: cell)?.title, plain)
    }

    func testNoSpentVariantKeepsTheName() throws {
        var content = rig.content
        content.perception[Subject.terrain(TerrainID(rawValue: "forest.spent"))] = nil
        let b = FrameBuilder(content: content)
        var (w, cell, _) = forestWorld()
        pickAt(&w, cell)
        XCTAssertEqual(b.footCard(w, at: cell)?.title, "森")
        XCTAssertEqual(b.inspect(w, at: cell)?.title, "森")
        XCTAssertEqual(b.tile(w, at: cell).glyph, TilePalette.spentGlyph, "見た目の字は名前と別")
    }

    // 鍵の往復
    func testPointFromKeyInvertsCountKey() {
        let at = WorldPoint(.surface, GridPoint(7, -3))
        let back = ExplorationState.point(fromKey: ExplorationState.countKey(pick, poi: nil, at: at))
        XCTAssertEqual(back?.interaction, pick)
        XCTAssertEqual(back?.at, at)
        XCTAssertNil(ExplorationState.point(fromKey: ExplorationState.countKey(pick, poi: EntityID(3), at: at)))
    }
}
