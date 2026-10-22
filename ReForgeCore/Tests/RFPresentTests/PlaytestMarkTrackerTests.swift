import Foundation
import RFContent
import RFKernel
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest
@testable import RFPresent

/// TEST-B4-3: 節目は成り立ったステップで 1 度だけ返る。追跡の型を書き戻して続けても同じ。
final class PlaytestMarkTrackerTests: XCTestCase {
    private func rig() throws -> TestRig {
        var content = try TestContent.publicOnly()
        content.playtestMarks = [:]
        for m in [
            PlaytestMarkDef(id: "mark.test.b-fact", when: .known(expr: .fact("fact.test.alpha"))),
            PlaytestMarkDef(id: "mark.test.a-first", when: .ledger(query: ProvenanceQuery(act: .crafted), atLeast: 1)),
        ] { content.playtestMarks[m.id] = m }
        return TestRig(content: content)
    }

    func testEachMarkIsReturnedOnceAtTheStepItHolds() throws {
        let rig = try rig()
        var w = rig.factory.newWorld(seed: 1)
        var tracker = PlaytestMarkTracker()
        XCTAssertEqual(tracker.update(w, rig.content), [])

        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.alpha")
        w = ctx.world
        XCTAssertEqual(tracker.update(w, rig.content), ["mark.test.b-fact"])
        XCTAssertEqual(tracker.update(w, rig.content), [])

        var ctx2 = StepContext(world: w, content: rig.content)
        _ = ctx2.record(.crafted, .none)
        w = ctx2.world
        XCTAssertEqual(tracker.update(w, rig.content), ["mark.test.a-first"])
        XCTAssertEqual(tracker.update(w, rig.content), [])
        XCTAssertEqual(Set(tracker.reached.keys), ["mark.test.a-first", "mark.test.b-fact"])
    }

    func testReturnedInIDOrderAndSurvivesCodableRoundTrip() throws {
        let rig = try rig()
        var w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.alpha")
        _ = ctx.record(.crafted, .none)
        w = ctx.world
        var tracker = PlaytestMarkTracker()
        XCTAssertEqual(tracker.update(w, rig.content), ["mark.test.a-first", "mark.test.b-fact"])

        let data = try JSONEncoder().encode(tracker)
        var restored = try JSONDecoder().decode(PlaytestMarkTracker.self, from: data)
        XCTAssertEqual(restored, tracker)
        XCTAssertEqual(restored.update(w, rig.content), [])
    }
}
