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

/// 場面の行の条件(`Line.when`)で飛ばした行は、ふきだしの文(`Frame.sceneLines`)に出さない。
/// 同じ枠の言い換え(条件を互いに外した行)を並べた場面で、出た 1 行だけが残る。
final class SceneLinesTests: XCTestCase {
    func content() throws -> ContentDB {
        var db = try TestContent.publicOnly()
        let json = #"""
        {"scenes": [{"id": "scene.test.alt", "lines": [
          {"text": "text.test.alt.0"},
          {"text": "text.test.alt.1b", "when": {"known": {"expr": "fact.test.alpha"}}},
          {"text": "text.test.alt.1", "when": {"not": {"that": {"known": {"expr": "fact.test.alpha"}}}}},
          {"text": "text.test.alt.2"}
        ]}]}
        """#
        try ContentLoader.apply(json: Data(json.utf8), to: &db)
        return db
    }

    func shown(alpha: Bool) throws -> [[String]] {
        let db = try content()
        let rig = TestRig(content: db)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: db)
        if alpha { ctx.learn("fact.test.alpha") }
        EffectApplier.apply([.startScene(scene: "scene.test.alt")], &ctx, cause: nil)
        var w = ctx.world
        var out: [[String]] = []
        while w.narrative.scene != nil {
            out.append(FrameBuilder(content: db).build(w, revision: 0, previous: nil, report: nil).sceneLines)
            _ = rig.simulation.apply(.narrative(.advanceScene), to: &w)
        }
        return out
    }

    func testSkippedAlternativesAreNotShown() throws {
        let db = try content()
        let p = Perceiver(content: db, world: TestRig(content: db).factory.newWorld(seed: 1))
        func t(_ s: String) -> String { p.text(TextID(s)) }
        XCTAssertEqual(try shown(alpha: false), [[t("text.test.alt.0")],
                                                 [t("text.test.alt.0"), t("text.test.alt.1")],
                                                 [t("text.test.alt.0"), t("text.test.alt.1"), t("text.test.alt.2")]])
        XCTAssertEqual(try shown(alpha: true), [[t("text.test.alt.0")],
                                                [t("text.test.alt.0"), t("text.test.alt.1b")],
                                                [t("text.test.alt.0"), t("text.test.alt.1b"), t("text.test.alt.2")]])
    }
}
