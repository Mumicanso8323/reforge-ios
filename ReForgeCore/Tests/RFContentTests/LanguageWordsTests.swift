import Foundation
import RFContent
import RFKernel
import XCTest

final class LanguageWordsTests: XCTestCase {
    func testLegacyArrayAndLanguageObjectRoundTrip() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(LanguageWords.self, from: Data("[\"zorb\"]".utf8)), LanguageWords(["zorb"]))
        let words = try decoder.decode(LanguageWords.self, from: Data("{\"ja\":[\"zorb\"],\"en\":[\"glim\"]}".utf8))
        XCTAssertEqual(words[.ja], ["zorb"])
        XCTAssertEqual(words[.en], ["glim"])
        XCTAssertThrowsError(try decoder.decode(LanguageWords.self, from: Data("{\"x-pseudo\":[\"zorb\"]}".utf8)))
        XCTAssertThrowsError(try decoder.decode(LanguageWords.self, from: Data("{\"unknown\":[\"zorb\"]}".utf8)))
        XCTAssertEqual(try decoder.decode(LanguageWords.self, from: JSONEncoder().encode(words)), words)
    }

    func testLegacyRuleWordsRemainJapanese() throws {
        var rule = ForbiddenRule(id: "rule.test", words: ["zorb"], until: .always)
        XCTAssertEqual(rule.words, ["zorb"])
        rule.words = ["glim"]
        XCTAssertEqual(rule.languageWords[.ja], ["glim"])
        let multilingual = ForbiddenRule(id: "rule.test", words: LanguageWords(byLanguage: [.ja: ["zorb"], .en: ["glim"]]), until: .always)
        XCTAssertEqual(multilingual.words, ["zorb"])
    }

    func testLanguageAllowedWordsMergeAndRemoveAcrossLanguages() throws {
        var db = ContentDB()
        try ContentLoader.apply(json: Data("{\"latinAllowed\":{\"ja\":[\"Zorb\"],\"en\":[\"Glim\"]}}".utf8), to: &db)
        XCTAssertEqual(db.latinAllowed, ["Zorb"])
        XCTAssertEqual(db.latinAllowedByLanguage[.en], ["Glim"])
        try ContentLoader.apply(json: Data("{\"remove\":{\"latinAllowed\":[\"Glim\"]}}".utf8), to: &db)
        XCTAssertTrue(db.latinAllowedByLanguage[.en].isEmpty)
    }

    func testAboutMustBeInTheJapaneseTable() throws {
        var db = ContentDB()
        XCTAssertThrowsError(try ContentLoader.apply(json: Data("{\"language\":\"en\",\"about\":{\"text.test\":[\"*\"]}}".utf8), to: &db))
    }
}
