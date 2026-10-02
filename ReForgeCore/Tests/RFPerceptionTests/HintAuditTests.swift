import Foundation
import RFContent
import RFKernel
import RFPerception
import RFTestSupport
import XCTest

/// U19 の受け入れテスト TEST-O9(気配の監査): 事実ごとの気配の主題がその段で見えていて、見え方に禁止語が無い。
final class HintAuditTests: XCTestCase {
    func testPublicHintsLoadAndPass() throws {
        let c = try TestContent.publicOnly()
        XCTAssertEqual(c.hintThemes["fact.test.revealed"]?.subjects, ["item:test_ore"])
        XCTAssertNotNil(c.hintThemes["fact.test.gamma"]?.none)
        XCTAssertEqual(c.depthHints["HNT-T2"]?.stage, "revealed")
        XCTAssertEqual(HintAudit.audit(c), [])
    }

    /// 非公開の層を重ねても 0 件(層が無ければ公開だけ)。
    func testFullContentHintsPass() throws {
        let problems = HintAudit.audit(try TestContent.full())
        XCTAssertEqual(problems, [], problems.map(\.description).joined(separator: "\n"))
    }

    func testDetectsForbiddenWordInHintSubject() throws {
        var c = try TestContent.publicOnly()
        c.texts["text.item.test_ore.seen"] = "禁句Aの影"
        let p = HintAudit.audit(c)
        XCTAssertEqual(p.count, 1)
        guard case .forbidden(let v)? = p.first?.kind else { return XCTFail("\(p)") }
        XCTAssertEqual(v.rule, "rule.test.a")
        XCTAssertFalse(p[0].description.contains("禁句A"), "語は伏せる")
    }

    func testDetectsInvisibleMissingAndEmpty() throws {
        var c = try TestContent.publicOnly()
        c.texts["text.test.hint.gated"] = "門の向こう"
        c.textGates["text.test.hint.gated"] = TextGate(text: "text.test.hint.gated", gate: .fact("fact.test.revealed"))
        c.scenes["scene.test.gated"] = try JSONDecoder().decode(
            SceneDef.self, from: Data(#"{"id":"scene.test.gated","lines":[{"text":"text.test.hint.gated"}]}"#.utf8))
        c.hintThemes["fact.test.alpha"] = HintTheme(fact: "fact.test.alpha", stage: "start",
                                                     subjects: ["scene:scene.test.gated", "part:part.test.none"])
        c.hintThemes["fact.test.beta"] = HintTheme(fact: "fact.test.beta", stage: "start")
        c.hintThemes["fact.test.gamma"] = HintTheme(fact: "fact.test.gamma", none: " ")
        c.depthHints["HNT-T3"] = DepthHint(hnt: "HNT-T3", what: "試験", stage: "no.such", subjects: ["item:test_ore"])
        let kinds = Dictionary(grouping: HintAudit.audit(c), by: { "\($0.owner)|\($0.subject ?? "")" })
            .mapValues { $0.map(\.kind) }
        XCTAssertEqual(kinds["fact.test.alpha|scene:scene.test.gated"], [.notVisible], "門が閉じている段では見えない")
        XCTAssertEqual(kinds["fact.test.alpha|part:part.test.none"], [.missingSubject])
        XCTAssertEqual(kinds["fact.test.beta|"], [.nothing])
        XCTAssertEqual(kinds["fact.test.gamma|"], [.emptyNone])
        XCTAssertEqual(kinds["HNT-T3|"], [.unknownStage("no.such")])
        // 段を開けると見える
        c.hintThemes["fact.test.alpha"]?.stage = "revealed"
        c.hintThemes["fact.test.alpha"]?.subjects = ["scene:scene.test.gated"]
        XCTAssertFalse(HintAudit.audit(c).contains { $0.owner == "fact.test.alpha" })
    }
}
