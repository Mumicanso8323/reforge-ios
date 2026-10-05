import RFContent
import RFExploration
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// 足元カードの行為: 同じ行為は最寄りの 1 つだけ・使い切りは出さない・止まった印は日が変われば消える。
final class ReviewFootCardTests: XCTestCase {
    let id: InteractionID = "interaction.pick_sticks"

    func setup() throws -> (FrameBuilder, WorldState, GridPoint) {
        let r = try TestRig.publicOnly()
        let b = FrameBuilder(content: r.content)
        var w = r.factory.newWorld(seed: 1)
        let c = w.map.spawn.point
        var bits = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
        for p in [GridPoint(1, 0), GridPoint(-1, 0), GridPoint(0, 1), GridPoint(0, 0)] { bits[c + p] = true }
        w.knowledge.mapKnown[.surface] = bits
        for p in [GridPoint(1, 0), GridPoint(-1, 0), GridPoint(0, 1)] { w.map[.surface]?.setTerrain("forest", at: c + p) }
        return (b, w, c)
    }

    func testSameActionOnSeveralNeighboursIsOfferedOnceAtTheNearest() throws {
        let (b, w, c) = try setup()
        let actions = try XCTUnwrap(b.footCard(w, at: c)).actions
        XCTAssertEqual(actions.filter { $0.id == id }.count, 1)
        XCTAssertEqual(Set(actions.map(\.id)).count, actions.count, "ID が重ならない")
        XCTAssertEqual(Set(actions.map(\.key)).count, actions.count)
        let pick = try XCTUnwrap(actions.first { $0.id == id })
        XCTAssertEqual(pick.target, c + GridPoint(-1, 0), "同じ距離なら x・y の順で決まる")
        XCTAssertEqual(pick.at.point, pick.target, "ボタンと対象がずれない")
    }

    func testExhaustedActionIsNotOffered() throws {
        let (b, w0, c) = try setup()
        var content = b.content
        content.interactions[id]?.limit = 1
        let b2 = FrameBuilder(content: content)
        var w = w0
        XCTAssertTrue(try XCTUnwrap(b2.footCard(w, at: c + GridPoint(1, 0))).actions.contains { $0.id == id })
        w.exploration.interactionCounts[ExplorationState.countKey(id, poi: nil, at: WorldPoint(.surface, c + GridPoint(1, 0)))] = 1
        XCTAssertFalse(try XCTUnwrap(b2.footCard(w, at: c + GridPoint(1, 0))).actions.contains { $0.id == id },
                       "使い切ったマスには押せないボタンを出さない")
    }

    func testNothingNearbyClearsOnANewDay() throws {
        let (b, w0, c) = try setup()
        var w = w0
        w.exploration.continueStop = ContinueStop(interaction: id, at: WorldPoint(.surface, c), day: w.clock.day)
        XCTAssertEqual(b.footCard(w, at: c)?.nothingNearby, true)
        w.clock.day += 1
        XCTAssertEqual(b.footCard(w, at: c)?.nothingNearby, false)
    }
}
