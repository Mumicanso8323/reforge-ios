import RFContent
import RFKernel
import RFPresent
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// 区切りの門(fence)が研究を待たせている間、研究の表は選ぶ物を出さない印を立てる(見せて禁じない。Z1)。
final class ResearchHeldTests: XCTestCase {
    private func content(holdsResearch: Bool) throws -> ContentDB {
        var db = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(#"""
        {
          "trialGate": {
            "when": { "counter": { "id": "counter.test.trial.gate", "cmp": "ge", "value": 1 } },
            "mode": "fence",
            "holds": { "research": \#(holdsResearch ? "true" : "false"), "events": [], "failures": [] }
          }
        }
        """#.utf8), to: &db, name: "research-held-test")
        return db
    }

    private func held(_ c: ContentDB, closed: Bool, fullGame: Bool) -> Bool {
        var w = TestRig(content: c).factory.newWorld(seed: 7)
        if closed { w.narrative.counters["counter.test.trial.gate"] = 1 }
        var builder = FrameBuilder(content: c)
        builder.entitlements = Entitlements(fullGame: fullGame)
        return builder.research(w).held
    }

    func testResearchIsHeldOnlyWhileTheFenceHoldsIt() throws {
        let holding = try content(holdsResearch: true)
        XCTAssertTrue(held(holding, closed: true, fullGame: false), "門が閉じて研究を待たせている間は印が立つ")
        XCTAssertFalse(held(holding, closed: false, fullGame: false), "門に届く前は立たない")
        XCTAssertFalse(held(holding, closed: true, fullGame: true), "権利があれば立たない")
        XCTAssertFalse(held(try content(holdsResearch: false), closed: true, fullGame: false), "研究を待たせない門では立たない")
        XCTAssertFalse(FrameBuilder(content: try TestContent.publicOnly()).research(
            TestRig(content: try TestContent.publicOnly()).factory.newWorld(seed: 7)).held, "門の無い束では立たない")
    }
}
