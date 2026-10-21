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

/// 仲間の割り当ての札に、同じ字の札が並ばない(押し分けられない札を作らない)。
final class AssignChoiceLabelTests: XCTestCase {
    private func labels(_ view: CrewView) -> [[String]] {
        view.members.map { m in m.choices.map { "\($0.kind)|\($0.target ?? "")" } }
    }

    private func assertNoDuplicates(_ view: CrewView, file: StaticString = #filePath, line: UInt = #line) {
        for list in labels(view) {
            let dup = Dictionary(grouping: list, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
            XCTAssertEqual(dup, [], "同じ字の札が並ぶ", file: file, line: line)
        }
    }

    /// 撮る起動と同じ世界(いまの視界を既知にした種 1)では、近くの残骸が 3 か所あり、前は同じ採取の札が 3 つ並んだ。
    func testGatherChoicesAreOnePerInteraction() throws {
        let content = try TestContent.publicOnly()
        var world = GameBootstrap.newWorld(content: content, seed: 1)
        Vision.markVisibleKnown(&world, content: content)
        let view = FrameBuilder(content: content).crew(world)
        XCTAssertTrue(view.members.contains { m in m.choices.contains { $0.kind == .gather } }, "前提: 採取の札がある")
        assertNoDuplicates(view)
    }

    /// 同じ名前の建物が 2 つあれば、札に通し番号が付き、それぞれ別の物を指す。
    func testSameNamePlacementsGetNumbers() throws {
        let content = try TestContent.publicOnly()
        var world = GameBootstrap.newWorld(content: content, seed: 1)
        let origin = world.map.spawn
        var ctx = StepContext(world: world, content: content)
        for dx in [3, 6] {
            EffectApplier.apply([.placeStructure(structure: "structure.research_desk",
                                                 at: .point(at: WorldPoint(origin.layer, GridPoint(origin.point.x + dx, origin.point.y + 3))),
                                                 built: true)], &ctx, cause: nil)
        }
        world = ctx.world
        let view = FrameBuilder(content: content).crew(world)
        assertNoDuplicates(view)
        let research = try XCTUnwrap(view.members.first { !$0.isNoah }).choices.filter { $0.kind == .research }
        XCTAssertEqual(research.count, 2, "研究机の札が 2 つ")
        XCTAssertNotEqual(research[0].assignment, research[1].assignment)
    }
}
