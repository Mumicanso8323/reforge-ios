import RFContent
import RFKernel
import RFTestSupport
import XCTest

final class TestTextSupportTests: XCTestCase {
    func testRenderUsesTableArgumentsAndLanguagesUseAvailableReleasedTables() throws {
        var content = try TestContent.publicOnly()
        content.textTables.tables[.ja]?["test.support.args"] = "{count}個"
        let rendered = TestText.render("test.support.args", ["count": .int(2)], content: content, language: .ja)
        XCTAssertEqual(rendered, "2個") // ja-table
        XCTAssertEqual(TestText.languages(for: content), [.ja, .pseudo])
    }

    func testMechanismExpectationSurvivesJapaneseTableReplacement() throws {
        var content = try TestContent.publicOnly()
        content.textTables.tables[.ja]?["test.support.replace"] = "最初{count}"
        let ref = TextRef("test.support.replace", ["count": .int(3)])
        content.textTables.tables[.ja]?["test.support.replace"] = "差し替え{count}"
        XCTAssertEqual(TestText.render(ref.id, ref.args, content: content),
                       TestText.render(ref.id, ref.args, content: content, language: .ja))
    }

    func testPseudoCheckFindsOnlyUnwrappedLocalizedText() {
        XCTAssertEqual(PseudoCheck.unwrapped(["⟦表の文⟧"]), []) // ja-table
        XCTAssertEqual(PseudoCheck.unwrapped(["表の文"]), ["表の文"]) // ja-table
        XCTAssertEqual(PseudoCheck.unwrapped(["reason.test", "字", "？"]), [])
    }
}
