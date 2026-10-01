import RFContent
import RFKernel
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class PresentTests: XCTestCase {
    func testFrameBuildsWithPerceivedNames() throws {
        let rig = try TestRig.publicOnly()
        let w = rig.factory.newWorld(seed: 1)
        let f = FrameBuilder(content: rig.content).build(w, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(f.clock.day, 1)
        XCTAssertTrue(f.clock.running)
        XCTAssertEqual(f.map.chunkRevisions.count, 4)
        XCTAssertEqual(f.actors.first?.label, "ノア")
        XCTAssertEqual(f.status.first?.label, "空気")
    }

    /// 工程表は記録(SheetDef)も同じ形で開ける。条件が成り立つまで開けない。
    func testProcessSheetFromRecord() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        let b = FrameBuilder(content: rig.content)
        XCTAssertNil(b.sheet(.record("sheet.test.record"), in: w))
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.alpha")
        w = ctx.world
        let s = try XCTUnwrap(b.sheet(.record("sheet.test.record"), in: w))
        XCTAssertEqual(s.title, "試験の記録")
        XCTAssertEqual(s.rows, [ProcessSheet.Row(title: "炉", note: "試験の行")])
    }

    func testHostTicksAndSends() async throws {
        let rig = try TestRig.publicOnly()
        let host = GameHost(simulation: rig.simulation, world: rig.factory.newWorld(seed: 1))
        let (f, r) = await host.tick(realSeconds: 1)
        XCTAssertGreaterThan(r.steps, 0)
        XCTAssertEqual(f.revision, 1)
        let (_, r2) = await host.send(.time(.sleep))
        XCTAssertEqual(r2.rejection?.reason, "reason.time.still_day")
    }
}
