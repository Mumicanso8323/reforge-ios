import XCTest
import UIKit
@testable import ReForge

/// L-12: 書体の入口(InkFont)。macOS の CI で回す。
@MainActor
final class InkFontTests: XCTestCase {
    override func tearDown() {
        InkFont.setLanguage("ja")
        super.tearDown()
    }

    private let biz = "BIZUDGothic-Regular"
    private let sc = "PingFangSC-Regular"
    private let tc = "PingFangTC-Regular"
    private let ko = "AppleSDGothicNeo-Regular"

    func testFamilyTable() {
        for id in ["ja", "en", "x-pseudo", "fr", ""] { XCTAssertEqual(InkFont.family(for: id), biz, id) }
        for id in ["zh-Hans", "zh-CN", "zh-SG", "zh", "zh-Hans-CN", "zh_CN"] { XCTAssertEqual(InkFont.family(for: id), sc, id) }
        for id in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh-Hant-TW", "zh_TW"] { XCTAssertEqual(InkFont.family(for: id), tc, id) }
        for id in ["ko", "ko-KR"] { XCTAssertEqual(InkFont.family(for: id), ko, id) }
    }

    func testDefaultLanguageIsJapaneseNotDevice() {
        XCTAssertEqual(InkFont.defaultLanguage, "ja")
    }

    func testSetLanguageChangesBodyFamily() throws {
        InkFont.setLanguage("ko")
        XCTAssertEqual(InkFont.language, "ko")
        let korean = try XCTUnwrap(UIFont(name: ko, size: 15))
        XCTAssertEqual(UIFont(name: InkFont.family(for: InkFont.language), size: 15)?.familyName, korean.familyName)
        InkFont.setLanguage("ja")
        XCTAssertEqual(UIFont(name: InkFont.family(for: InkFont.language), size: 15)?.familyName,
                       UIFont(name: biz, size: 15)?.familyName)
    }
}
