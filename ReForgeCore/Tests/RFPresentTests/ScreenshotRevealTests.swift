import RFContent
import RFCrew
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 撮る起動の世界(時計を止める)でも、地図にいまの視界の地形が載る(既知が空で真っ黒にならない)。
final class ScreenshotRevealTests: XCTestCase {
    private func fogCounts(_ content: ContentDB, _ world: WorldState) -> [TileView.Fog: Int] {
        let builder = FrameBuilder(content: content)
        let frame = builder.build(world, revision: 1, previous: nil, report: nil)
        var out: [TileView.Fog: Int] = [:]
        for chunk in builder.chunks(world, Array(frame.map.chunkRevisions.indices), map: frame.map) {
            for tile in chunk.tiles { out[tile.fog, default: 0] += 1 }
        }
        return out
    }

    func testMarkVisibleKnownPutsTheCurrentViewOnTheMap() throws {
        let content = try TestContent.publicOnly()
        var world = GameBootstrap.newWorld(content: content, seed: 1)
        XCTAssertEqual(fogCounts(content, world)[.remembered, default: 0], 0, "前提: 作った直後の世界は既知が空")
        let visible = Vision.visibleNow(world, content: content, layer: world.map.spawn.layer)
        XCTAssertFalse(visible.isEmpty)
        Vision.markVisibleKnown(&world, content: content)
        let known = try XCTUnwrap(world.knowledge.mapKnown[world.map.spawn.layer])
        for p in visible { XCTAssertTrue(known[p], "\(p) が既知にならない") }
        XCTAssertGreaterThan(fogCounts(content, world)[.remembered, default: 0], 0, "地図の区画に地形が載らない")
    }

    /// 既知にする範囲は、時計を 1 歩進めた時の「見る」と同じ。
    func testMarkVisibleKnownMatchesOneStepOfLooking() throws {
        let content = try TestContent.publicOnly()
        var marked = GameBootstrap.newWorld(content: content, seed: 1)
        Vision.markVisibleKnown(&marked, content: content)
        let layer = marked.map.spawn.layer
        var stepped = GameBootstrap.newWorld(content: content, seed: 1)
        let sim = Simulation(content: content)
        _ = sim.advance(&stepped, realSeconds: 1)
        let a = try XCTUnwrap(marked.knowledge.mapKnown[layer])
        let b = try XCTUnwrap(stepped.knowledge.mapKnown[layer])
        let size = a.size
        for y in 0..<size.height {
            for x in 0..<size.width where b[GridPoint(x, y)] {
                XCTAssertTrue(a[GridPoint(x, y)], "1 歩の見るで知った (\(x),\(y)) を既知にしていない")
            }
        }
    }
}
