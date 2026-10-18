import XCTest
import SwiftUI
import ReForgeEngine
@testable import ReForge

/// L-12: 行ごとの読み上げの言語。`[ja]` の印のある文だけ日本語の属性が付く。macOS の CI で回す。
@MainActor
final class SpokenTextTests: XCTestCase {
    func testMarkedStringCarriesJapaneseSpeechLanguageAndKeepsTheText() {
        let attributed = SpokenString.attributed("[ja]abc")
        XCTAssertEqual(SpokenString.spokenLanguage(of: attributed), "ja")
        XCTAssertEqual(String(attributed.characters), "[ja]abc")
        XCTAssertEqual(attributed[AttributeScopes.FoundationAttributes.LanguageIdentifierAttribute.self], "ja")
    }

    func testPlainStringHasNoSpeechLanguage() {
        XCTAssertNil(SpokenString.spokenLanguage(of: AttributedString("abc")))
    }
}
