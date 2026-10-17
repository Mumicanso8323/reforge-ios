import Foundation
import RFContent
import RFKernel
import RFPerception
import XCTest

final class ForbiddenLanguageTests: XCTestCase {
    func testWordMatcherUsesLanguageAppropriateBoundaries() {
        XCTAssertFalse(WordMatcher.contains("more", word: "ore", language: .en))
        XCTAssertTrue(WordMatcher.contains("Ore.", word: "ore", language: .en))
        XCTAssertTrue(WordMatcher.contains("ore's", word: "ore", language: .en))
        XCTAssertTrue(WordMatcher.contains("iron  ore", word: "iron ore", language: .en))
        XCTAssertTrue(WordMatcher.contains("か\u{3099}", word: "が", language: .ja))
        XCTAssertTrue(WordMatcher.contains("zorb을", word: "zorb", language: .ko))
        XCTAssertTrue(WordMatcher.contains("zorb文", word: "zorb", language: .zhHans))
        XCTAssertTrue(WordMatcher.contains("⟦zorb・⟧", word: "zorb", language: .pseudo))
    }

    func testEnglishInternalIDRecognitionIsNarrow() {
        XCTAssertTrue(ForbiddenAudit.looksLikeInternalID("ui.title", language: .en))
        XCTAssertTrue(ForbiddenAudit.looksLikeInternalID("a_b", language: .en))
        XCTAssertFalse(ForbiddenAudit.looksLikeInternalID("Iron ore.", language: .en))
        XCTAssertFalse(ForbiddenAudit.looksLikeInternalID("e.g. this", language: .en))
        XCTAssertFalse(ForbiddenAudit.looksLikeInternalID("It's fine", language: .en))
    }

    func testAuditUsesOnlyTheLanguageOwnTextTableAndChecksReleasedLanguages() {
        var db = ContentDB()
        db.textTables.tables[.ja] = ["text.test.shared": "zorb", "text.test.ja": "zorb"]
        db.textTables.tables[.en] = ["text.test.shared": "glim"]
        db.forbidden = [ForbiddenRule(id: "rule.test", words: LanguageWords(byLanguage: [.ja: ["zorb"], .en: ["glim"]]), until: .not(.always))]
        XCTAssertEqual(ForbiddenAudit.audit(db, language: .ja).filter { $0.rule == "rule.test" }.count, 2)
        XCTAssertEqual(ForbiddenAudit.audit(db, language: .en).filter { $0.rule == "rule.test" }.count, 1)
        XCTAssertEqual(Set(ForbiddenAudit.auditAll(db).keys), [.ja, .en])
        db.forbidden[0].languageWords[.en] = []
        XCTAssertTrue(ContentValidator.validate(db, released: [.ja, .en]).contains { $0.rule == "forbidden.languages" && $0.level == .error })
        XCTAssertFalse(ContentValidator.validate(db, released: [.ja]).contains { $0.rule == "forbidden.languages" && $0.level == .error })
    }

    func testScopeHasSameStaticAndRuntimeMeaning() throws {
        var db = ContentDB()
        db.texts = ["text.test.a": "zorb", "text.test.n": "zorb", "text.test.b": "zorb", "text.test.other": "zorb"]
        db.latinAllowed = ["zorb"]
        try ContentLoader.apply(json: Data("{\"scenes\":[{\"id\":\"scene.test\",\"lines\":[{\"speaker\":\"person.test.a\",\"text\":\"text.test.a\"},{\"text\":\"text.test.n\"},{\"speaker\":\"person.test.b\",\"text\":\"text.test.b\"}]}],\"hints\":[]}".utf8), to: &db)
        db.forbidden = [ForbiddenRule(id: "rule.test", words: ["zorb"], until: .not(.always))]
        db.forbidden[0].scope = ForbiddenScope(speakers: ["person.test.a"], narration: true)
        XCTAssertEqual(Set(ForbiddenAudit.audit(db).filter { $0.rule == "rule.test" }.map(\.origin)), ["text.test.a", "text.test.n"])
        let auditor = PerceptionAuditor()
        let perceiver = Perceiver(content: db, known: [], auditor: auditor)
        _ = perceiver.text("text.test.a")
        _ = perceiver.text("text.test.b")
        _ = perceiver.text("text.test.other")
        XCTAssertEqual(auditor.violations.filter { $0.rule == "rule.test" }.count, 1)
        db.forbidden[0].scope?.other = true
        XCTAssertEqual(ForbiddenAudit.audit(db).filter { $0.rule == "rule.test" }.count, 3)
        db.forbidden[0].scope = ForbiddenScope()
        XCTAssertTrue(ContentValidator.validate(db).contains { $0.rule == "forbidden.scope.empty" && $0.level == .error })
        db.forbidden[0].scope = ForbiddenScope(speakers: ["person.test.none"])
        XCTAssertTrue(ContentValidator.validate(db).contains { $0.rule == "forbidden.scope" && $0.level == .warning })
    }

    func testPronounRulesStaySeparateFromForbiddenAudit() {
        var db = ContentDB()
        db.textTables.tables[.ja] = ["text.test.review": "zorb"]
        db.textTables.tables[.en] = ["text.test.ok": "they are", "text.test.error": "misname", "text.test.star": "reviewword"]
        db.textAbout = ["text.test.review": ["person.test.a"], "text.test.ok": ["person.test.a"], "text.test.error": ["person.test.a"], "text.test.star": ["*"]]
        db.pronounRules = [PronounRule(id: "pronoun.test", about: "person.test.a", error: LanguageWords(byLanguage: [.en: ["misname"]]), review: LanguageWords(byLanguage: [.ja: ["zorb"], .en: ["reviewword"]]))]
        let english = PronounAudit.check(db, language: .en)
        XCTAssertFalse(english.contains { $0.text == "text.test.ok" })
        XCTAssertTrue(english.contains { $0.text == "text.test.error" && $0.severity == .error })
        XCTAssertTrue(english.contains { $0.text == "text.test.star" && $0.severity == .error })
        XCTAssertTrue(PronounAudit.check(db, language: .ja).contains { $0.text == "text.test.review" && $0.severity == .review })
        XCTAssertFalse(ForbiddenAudit.audit(db).contains { $0.rule == "pronoun.test" })
    }
}
