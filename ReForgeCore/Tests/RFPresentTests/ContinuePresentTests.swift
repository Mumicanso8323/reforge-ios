import RFContent
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// PT-B1 の画面側: 足元カードの進み・止まった印・焚き火の見込み、日没の帯の見込み。
final class ContinuePresentTests: XCTestCase {
    func rig() throws -> TestRig { try TestRig.publicOnly() }

    func know(_ w: inout WorldState, _ pts: [GridPoint]) {
        var bits = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
        for p in pts { bits[p] = true }
        w.knowledge.mapKnown[.surface] = bits
    }

    func withCampfire(_ w: inout WorldState, at c: GridPoint, fuelSeconds: Int, pile: Int = 0) {
        let id = w.newEntityID()
        var p = Placement(id: id, kind: .structure("structure.campfire"), at: WorldPoint(.surface, c), facing: .north,
                          origin: ProvenanceLedger.unknownOrigin, status: .running)
        var rt = StructureRuntime()
        rt.hearth = HearthState(fuel: fuelSeconds * 1000, lit: fuelSeconds > 0, pile: pile)
        p.structure = rt
        w.placements.items[id] = p
    }

    /// 続けて採る行為の足元カードは押し続けるボタンで、進みは押している間だけ出る。止まった印も出る。
    func testFootCardProgressAndStopMark() throws {
        let r = try rig()
        var content = r.content
        content.interactions["interaction.pick_sticks"]?.continues = true
        let b = FrameBuilder(content: content)
        var w = r.factory.newWorld(seed: 1)
        let cell = w.map.spawn.point + GridPoint(2, 0)
        w.map[.surface]?.setTerrain("forest", at: cell)
        know(&w, [cell])
        let card = try XCTUnwrap(b.footCard(w, at: cell))
        let action = try XCTUnwrap(card.actions.first { $0.id == "interaction.pick_sticks" })
        XCTAssertTrue(action.hold, "continues の行為は押し続ける")
        XCTAssertNil(action.progressPermille)
        XCTAssertFalse(card.nothingNearby)

        let seconds = Int64(try XCTUnwrap(content.interactions["interaction.pick_sticks"]).seconds)
        var active = ActiveInteraction(interaction: "interaction.pick_sticks", at: WorldPoint(.surface, cell), poi: nil,
                                       part: nil, holding: true, spent: [], startedAt: w.clock.now)
        active.progress = 30
        w.exploration.active[.noah] = active
        let mid = try XCTUnwrap(b.footCard(w, at: cell)?.actions.first { $0.id == "interaction.pick_sticks" })
        XCTAssertEqual(mid.progressPermille, Int(30 * 1000 / seconds))
        w.exploration.active[.noah]?.holding = false
        XCTAssertNil(b.footCard(w, at: cell)?.actions.first { $0.id == "interaction.pick_sticks" }?.progressPermille,
                     "押していないときは nil")

        w.exploration.active[.noah] = nil
        w.exploration.continueStop = ContinueStop(interaction: "interaction.pick_sticks", at: WorldPoint(.surface, cell))
        XCTAssertEqual(b.footCard(w, at: cell)?.nothingNearby, true)
    }

    /// continues の無い行為の足元カードは今までどおり(押し続けるのは hold の行為だけ)。
    func testFootCardUnchangedWithoutContinues() throws {
        let r = try rig()
        let b = FrameBuilder(content: r.content)
        var w = r.factory.newWorld(seed: 1)
        let cell = w.map.spawn.point + GridPoint(2, 0)
        w.map[.surface]?.setTerrain("forest", at: cell)
        know(&w, [cell])
        let a = try XCTUnwrap(b.footCard(w, at: cell)?.actions.first { $0.id == "interaction.pick_sticks" })
        XCTAssertFalse(a.hold)
    }

    /// 焚き火の足元カードに火の見込み(今と、1 本くべた後)。焚き火でないマスには出ない。
    func testCampfireFootCardShowsOutlook() throws {
        let r = try rig()
        let b = FrameBuilder(content: r.content)
        var w = r.factory.newWorld(seed: 1)
        let c = w.map.spawn.point + GridPoint(3, 3)
        withCampfire(&w, at: c, fuelSeconds: 14_400)
        w.clock.now = GameTime(seconds: 20_000)
        know(&w, [c, w.map.spawn.point])
        let fire = try XCTUnwrap(b.footCard(w, at: c)?.fire)
        XCTAssertEqual(fire.now, .midnight)
        let order: [FireOutlook] = [.untilEvening, .midnight, .beforeDawn, .throughNight]
        XCTAssertGreaterThanOrEqual(order.firstIndex(of: fire.afterOneMore)!, order.firstIndex(of: fire.now)!)
        XCTAssertNil(b.footCard(w, at: w.map.spawn.point)?.fire)
        // 見込みは世界を変えない
        let before = w
        _ = b.footCard(w, at: c)
        XCTAssertEqual(w, before)
    }

    /// 日没の帯に、薪の置き場の本数を入れた見込み。昼は出さない。
    func testDuskBandShowsOutlookWithPile() throws {
        let r = try rig()
        let b = FrameBuilder(content: r.content)
        var w = r.factory.newWorld(seed: 1)
        let c = w.map.spawn.point + GridPoint(3, 3)
        withCampfire(&w, at: c, fuelSeconds: 14_400, pile: 4)
        XCTAssertNil(b.build(w, revision: 1, previous: nil, report: nil).clock.fireOutlook, "昼は出さない")
        w.clock.phase = .dusk
        w.clock.now = GameTime(seconds: 28_800)
        let withPile = try XCTUnwrap(b.build(w, revision: 2, previous: nil, report: nil).clock.fireOutlook)
        w.placements.items[w.placements.sortedIDs[0]]?.structure?.hearth?.pile = 0
        let without = try XCTUnwrap(b.build(w, revision: 3, previous: nil, report: nil).clock.fireOutlook)
        let order: [FireOutlook] = [.untilEvening, .midnight, .beforeDawn, .throughNight]
        XCTAssertGreaterThan(order.firstIndex(of: withPile)!, order.firstIndex(of: without)!)
    }
}
