import Foundation
import RFContent
import RFKernel
import RFPerception
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 決断の問いの文(`EventDef.prompt`)は `Frame.decision.prompt` に文として出る。無い決断は nil。
final class DecisionPromptTests: XCTestCase {
    private func decisionView(prompt: TextID?) throws -> DecisionView {
        var db = try TestContent.publicOnly()
        db.texts["text.test.prompt"] = "テスト用の文"
        db.events["event.test.decision"]?.prompt = prompt
        let rig = TestRig(content: db)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: db)
        ctx.learn("fact.test.alpha")
        var report = StepReport()
        rig.simulation.settle(&ctx, &report)
        let frame = FrameBuilder(content: db).build(ctx.world, revision: 0, previous: nil, report: nil)
        return try XCTUnwrap(frame.decision)
    }

    func testPromptIsShownWhenEventHasOne() throws {
        XCTAssertEqual(try decisionView(prompt: "text.test.prompt").prompt, "テスト用の文")
    }

    func testPromptIsNilWhenEventHasNone() throws {
        XCTAssertNil(try decisionView(prompt: nil).prompt)
    }
}
