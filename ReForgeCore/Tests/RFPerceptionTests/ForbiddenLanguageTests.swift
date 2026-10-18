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
        XCTAssertTrue(WordMatcher.contains("か\u{3099}", word: "が", language: .ja)) // ja-table
        XCTAssertTrue(WordMatcher.contains("zorb을", word: "zorb", language: .ko))
        XCTAssertTrue(WordMatcher.contains("zorb文", word: "zorb", language: .zhHans)) // ja-table
        XCTAssertTrue(WordMatcher.contains("⟦zorb・⟧", word: "zorb", language: .pseudo)) // ja-table
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

    func testScopeCoversPerceptionNamesSharedIDsAndRuntimeNarration() throws {
        var db = ContentDB()
        db.texts = ["text.test.p": "zorb", "text.test.both": "zorb", "text.test.n": "zorb"]
        db.latinAllowed = ["zorb"]
        try ContentLoader.apply(json: Data("{\"scenes\":[{\"id\":\"scene.test\",\"lines\":[{\"speaker\":\"person.test.a\",\"text\":\"text.test.both\"},{\"text\":\"text.test.n\"}]}],\"perception\":[{\"subject\":\"stat:stat.test.air\",\"variants\":[{\"when\":true,\"name\":\"text.test.p\"}]}],\"hints\":[]}".utf8), to: &db)
        db.forbidden = [ForbiddenRule(id: "rule.test", words: ["zorb"], until: .not(.always))]
        func origins() -> Set<String> { Set(ForbiddenAudit.audit(db).filter { $0.rule == "rule.test" }.map(\.origin)) }
        // (c) 認識の表の名前に使われた文言は、声が「その他」だけ。話し手と地の文の範囲では当たらない
        db.forbidden[0].scope = ForbiddenScope(speakers: ["person.test.a"], narration: true)
        XCTAssertFalse(origins().contains { $0.hasSuffix("text.test.p") })
        db.forbidden[0].scope = ForbiddenScope(other: true)
        XCTAssertTrue(origins().contains { $0.hasSuffix("text.test.p") })
        // (e) 場面の台詞と別の場所の両方で使う ID は、どちらの範囲でも当たる
        db.forbidden[0].scope = ForbiddenScope(speakers: ["person.test.a"])
        XCTAssertTrue(origins().contains("text.test.both"))
        db.forbidden[0].scope = ForbiddenScope(speakers: ["person.test.b"])
        XCTAssertFalse(origins().contains("text.test.both"))
        // 走行中の検査も地の文を同じに扱う
        db.forbidden[0].scope = ForbiddenScope(narration: true)
        let auditor = PerceptionAuditor()
        let perceiver = Perceiver(content: db, known: [], auditor: auditor)
        _ = perceiver.text("text.test.n")
        _ = perceiver.text("text.test.both")
        XCTAssertEqual(auditor.violations.filter { $0.rule == "rule.test" }.count, 1)
    }

    func testVoicesAreBuiltOncePerAuditAndSkippedWithoutScope() throws {
        var db = ContentDB()
        db.textTables.tables[.ja] = Dictionary(uniqueKeysWithValues: (0..<30).map { (TextID("text.test.\($0)"), "zorb \($0)") })
        db.latinAllowed = ["zorb"]
        db.forbidden = [ForbiddenRule(id: "rule.test", words: ["zorb"], until: .not(.always))]
        var before = TextVoices.buildCount
        XCTAssertEqual(ForbiddenAudit.audit(db).filter { $0.rule == "rule.test" }.count, 30)
        XCTAssertEqual(TextVoices.buildCount, before, "scope が無ければ作らない")
        db.forbidden[0].scope = ForbiddenScope(other: true)
        before = TextVoices.buildCount
        XCTAssertEqual(ForbiddenAudit.audit(db).filter { $0.rule == "rule.test" }.count, 30)
        XCTAssertEqual(TextVoices.buildCount, before + 1, "監査 1 回で 1 度だけ")
        before = TextVoices.buildCount
        _ = ForbiddenAudit.check((0..<30).map { "zorb \($0)" }, content: db, known: [])
        XCTAssertEqual(TextVoices.buildCount, before + 1, "並びの検査も 1 度だけ")
    }

    func testPronounRulesStaySeparateFromForbiddenAudit() {
        var db = ContentDB()
        db.textTables.tables[.ja] = ["text.test.review": "zorb"]
        db.textTables.tables[.en] = ["text.test.ok": "they are", "text.test.error": "misname", "text.test.star": "reviewword",
                                     "text.test.other": "misname", "text.test.enreview": "reviewword"]
        db.textAbout = ["text.test.review": ["person.test.a"], "text.test.ok": ["person.test.a"], "text.test.error": ["person.test.a"],
                        "text.test.star": ["*"], "text.test.other": ["person.test.b"], "text.test.enreview": ["person.test.a"]]
        db.pronounRules = [PronounRule(id: "pronoun.test", about: "person.test.a", error: LanguageWords(byLanguage: [.en: ["misname"]]), review: LanguageWords(byLanguage: [.ja: ["zorb"], .en: ["reviewword"]]))]
        let english = PronounAudit.check(db, language: .en)
        XCTAssertFalse(english.contains { $0.text == "text.test.ok" })
        XCTAssertFalse(english.contains { $0.text == "text.test.other" }, "ほかの人の文言は見ない")
        XCTAssertTrue(english.contains { $0.text == "text.test.enreview" && $0.severity == .review })
        XCTAssertTrue(english.contains { $0.text == "text.test.error" && $0.severity == .error })
        XCTAssertTrue(english.contains { $0.text == "text.test.star" && $0.severity == .error })
        XCTAssertTrue(PronounAudit.check(db, language: .ja).contains { $0.text == "text.test.review" && $0.severity == .review })
        // 禁止語の表に代名詞の規則と同じ語があっても、代名詞の指摘は禁止語の監査に混ざらない(逆も)
        db.forbidden = [ForbiddenRule(id: "rule.test", words: LanguageWords(byLanguage: [.en: ["misname"]]), until: .not(.always))]
        let forbidden = ForbiddenAudit.audit(db, language: .en).filter { $0.text == "misname" }
        XCTAssertEqual(Set(forbidden.map(\.rule)), ["rule.test"])
        XCTAssertEqual(PronounAudit.check(db, language: .en).filter { $0.text == "text.test.error" }.map(\.rule), ["pronoun.test"])
    }

    /// 除く語(allow)は照らす前に文から外す。外した所は空白になり、残りの語は今までどおり当たる。
    func testPronounAllowWordsAreRemovedBeforeMatching() {
        var db = ContentDB()
        db.textTables.tables[.ja] = ["text.test.plural": "zorbsの", "text.test.single": "zorbの", "text.test.both": "zorbsとzorb"]
        db.textTables.tables[.en] = ["text.test.phrase": "the mis kit", "text.test.word": "a mis here"]
        db.textAbout = Dictionary(uniqueKeysWithValues: ["text.test.plural", "text.test.single", "text.test.both", "text.test.phrase", "text.test.word"]
            .map { (TextID($0), Set(["person.test.a"])) })
        db.pronounRules = [PronounRule(id: "pronoun.test", about: "person.test.a",
                                       error: LanguageWords(byLanguage: [.ja: ["zorb"], .en: ["mis"]]),
                                       review: LanguageWords(byLanguage: [:]),
                                       allow: LanguageWords(byLanguage: [.ja: ["zorbs"], .en: ["Mis Kit"]]))]
        XCTAssertEqual(Set(PronounAudit.check(db, language: .ja).map(\.text)), ["text.test.single", "text.test.both"])
        XCTAssertEqual(PronounAudit.check(db, language: .en).map(\.text), ["text.test.word"], "英語の除く語は大文字小文字を問わない")
        XCTAssertEqual(Set(PronounAudit.checkAll(db).keys), [.ja, .en])
    }

    /// pronounRules の review と allow は省略できる。allow が空なら書き出さない(今のファイルと同じ形)。
    func testPronounRuleJSONDefaults() throws {
        let rule = try JSONDecoder().decode(PronounRule.self, from: Data(#"{"id":"pronoun.test","about":"person.test.a","error":["zorb"]}"#.utf8))
        XCTAssertEqual(rule.error.ja, ["zorb"])
        XCTAssertTrue(rule.review.byLanguage.isEmpty)
        XCTAssertTrue(rule.allow.byLanguage.isEmpty)
        let encoded = String(decoding: try JSONEncoder().encode(rule), as: UTF8.self)
        XCTAssertFalse(encoded.contains("allow"))
        let withAllow = try JSONDecoder().decode(PronounRule.self, from: Data(#"{"id":"p","about":"person.test.a","error":["zorb"],"review":[],"allow":{"ja":["zorbs"],"en":["zorbs"]}}"#.utf8))
        XCTAssertEqual(withAllow.allow[.en], ["zorbs"])
        XCTAssertEqual(try JSONDecoder().decode(PronounRule.self, from: try JSONEncoder().encode(withAllow)), withAllow)
        XCTAssertThrowsError(try JSONDecoder().decode(PronounRule.self, from: Data(#"{"id":"p","about":"person.test.a","error":[],"allow":{"x-pseudo":["a"]}}"#.utf8)))
    }
}
