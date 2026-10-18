import RFKernel
import RFPresent
import XCTest

final class SpeechLanguageTests: XCTestCase {
    func testMarkedLineIsJapanese() {
        for lang in LanguageID.shipped + [.pseudo] {
            XCTAssertEqual(SpeechLanguage.identifier(for: lang, text: "[ja]abc"), "ja")
        }
    }

    func testOtherLinesFollowEffective() {
        XCTAssertEqual(SpeechLanguage.identifier(for: .ko, text: "abc"), "ko")
        XCTAssertEqual(SpeechLanguage.identifier(for: .zhHans, text: ""), "zh-Hans")
        XCTAssertEqual(SpeechLanguage.identifier(for: .zhHant, text: "x [ja]"), "zh-Hant")
        XCTAssertEqual(SpeechLanguage.identifier(for: .en, text: "abc"), "en")
        XCTAssertEqual(SpeechLanguage.identifier(for: .ja, text: "a"), "ja")
    }

    func testPseudoSpeaksJapanese() {
        XCTAssertEqual(SpeechLanguage.identifier(for: .pseudo, text: "abc"), "ja")
        XCTAssertEqual(SpeechLanguage.base(.pseudo), "ja")
    }

    func testComposedLineWithMarkAnywhereIsJapanese() {
        XCTAssertEqual(SpeechLanguage.identifier(for: .en, composed: "▤ [ja]abc"), "ja")
        XCTAssertEqual(SpeechLanguage.identifier(for: .ko, composed: "[ja]a, [ja]b"), "ja")
        XCTAssertEqual(SpeechLanguage.identifier(for: .ko, composed: "▤ abc"), "ko")
        XCTAssertEqual(SpeechLanguage.identifier(for: .pseudo, composed: "abc"), "ja")
        XCTAssertTrue(SpeechLanguage.isMarked("x[ja]"))
        XCTAssertFalse(SpeechLanguage.isMarked("ja"))
    }

    func testNoMarkKeepsBaseForEveryShippedLanguage() {
        for lang in LanguageID.shipped {
            XCTAssertEqual(SpeechLanguage.identifier(for: lang, composed: "abc"), SpeechLanguage.base(lang))
        }
    }
}
