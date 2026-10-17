import RFContent
import RFKernel
import RFPresent
import RFTestSupport
import XCTest

final class LanguageChoiceTests: XCTestCase {
    private let a: TextID = "t.a"
    private let b: TextID = "t.b"

    /// 試験用のメモリ上の表。日本語は 2 文(b は引数 name を持つ)と nameJoin。
    private func tables(english: [TextID: String]?, englishJoin: Bool = true) -> TextTables {
        var t = TextTables()
        t.tables[.ja] = [a: "あ", b: "{name}"]
        t.meta[.ja] = TextMeta(nameJoin: NameJoin(order: ["family", "given"], separator: ""))
        if let english {
            t.tables[.en] = english
            if englishJoin { t.meta[.en] = TextMeta(nameJoin: NameJoin(order: ["given", "family"], separator: " ")) }
        }
        return t
    }

    func testPreferredIdentifierMapping() {
        let cases: [(String, LanguageID?)] = [
            ("zh-TW", .zhHant), ("zh-HK", .zhHant), ("zh-MO", .zhHant), ("zh-Hant", .zhHant),
            ("zh-Hant-TW", .zhHant), ("zh_TW", .zhHant),
            ("zh-CN", .zhHans), ("zh-SG", .zhHans), ("zh-Hans", .zhHans), ("zh-Hans-CN", .zhHans), ("zh", .zhHans),
            ("en-US", .en), ("en-GB", .en), ("EN", .en), ("ja-JP", .ja), ("ko-KR", .ko),
            ("fr", nil), ("pt-BR", nil), ("", nil), ("x-pseudo", nil),
        ]
        for (identifier, expected) in cases {
            XCTAssertEqual(LanguageResolver.language(forPreferred: identifier), expected, identifier)
        }
    }

    func testResolve() {
        let both: [LanguageID] = [.ja, .en]
        XCTAssertEqual(LanguageResolver.resolve(.language(.en), preferred: ["ja-JP"], offered: both), .en)
        XCTAssertEqual(LanguageResolver.resolve(.language(.ko), preferred: ["en-US"], offered: both), .en)
        XCTAssertEqual(LanguageResolver.resolve(.system, preferred: ["zh-TW", "en-US"], offered: both), .en)
        XCTAssertEqual(LanguageResolver.resolve(.system, preferred: ["fr", "pt-BR"], offered: both), .en)
        XCTAssertEqual(LanguageResolver.resolve(.system, preferred: ["fr"], offered: [.ja, .ko]), .ja)
        XCTAssertEqual(LanguageResolver.resolve(.system, preferred: ["ko-KR"], offered: [.ja, .ko]), .ko)
        let onlyJa: [LanguageID] = [.ja]
        for preferred in [["en-US"], ["zh-TW"], ["ko"], ["fr"], []] {
            XCTAssertEqual(LanguageResolver.resolve(.system, preferred: preferred, offered: onlyJa), .ja)
            XCTAssertEqual(LanguageResolver.resolve(.language(.en), preferred: preferred, offered: onlyJa), .ja)
            XCTAssertEqual(LanguageResolver.resolve(.language(.pseudo), preferred: preferred, offered: onlyJa), .ja)
        }
        XCTAssertEqual(LanguageResolver.resolve(.language(.pseudo), preferred: [], offered: [.ja, .pseudo]), .pseudo)
    }

    func testPinnedWinsEvenWhenNotOffered() {
        let onlyJa: [LanguageID] = [.ja]
        XCTAssertEqual(LanguageResolver.effective(.system, pinned: .ko, preferred: ["en-US"], offered: onlyJa), .ko)
        XCTAssertEqual(LanguageResolver.effective(.language(.ja), pinned: .zhHant, preferred: [], offered: onlyJa), .zhHant)
        XCTAssertEqual(LanguageResolver.effective(.language(.en), pinned: nil, preferred: [], offered: onlyJa), .ja)
    }

    func testOfferedRequiresCompleteTables() {
        let good = tables(english: [a: "A", b: "{name}"])
        XCTAssertEqual(LanguageOffer.problems(.en, in: good), [])
        XCTAssertEqual(LanguageOffer.offered(released: [.ja, .en], tables: good), [.ja, .en])
        XCTAssertEqual(LanguageOffer.problems(.ja, in: good), [])

        let missing = tables(english: [a: "A"])
        XCTAssertEqual(LanguageOffer.problems(.en, in: missing), [.init(kind: .missing, count: 1)])
        let args = tables(english: [a: "A", b: "{who}"])
        XCTAssertEqual(LanguageOffer.problems(.en, in: args), [.init(kind: .arguments, count: 1)])
        let format = tables(english: [a: "A", b: "{name"])
        XCTAssertEqual(LanguageOffer.problems(.en, in: format), [.init(kind: .format, count: 1)])
        let join = tables(english: [a: "A", b: "{name}"], englishJoin: false)
        XCTAssertEqual(LanguageOffer.problems(.en, in: join), [.init(kind: .nameJoin, count: 1)])
        for broken in [missing, args, format, join] {
            XCTAssertEqual(LanguageOffer.offered(released: [.ja, .en], tables: broken), [.ja])
        }
    }

    func testCompleteTableNotReleasedIsNotOffered() {
        let good = tables(english: [a: "A", b: "{name}"])
        XCTAssertEqual(LanguageOffer.offered(released: [.ja], tables: good), [.ja])
        XCTAssertEqual(LanguageOffer.offered(released: [.ja, .en], tables: good, includePseudo: true), [.ja, .en, .pseudo])
        XCTAssertEqual(LanguageOffer.offered(released: [.ja], tables: good, includePseudo: true), [.ja, .pseudo])
    }

    func testShippedContentOffersOnlyJapanese() throws {
        var dbs = [try TestContent.publicOnly()]
        if TestContent.hasPrivateLayer { dbs.append(try TestContent.full()) }
        for db in dbs {
            XCTAssertEqual(LanguageOffer.offered(tables: db.textTables), [.ja])
            // 公開の層の途中の表は、全部を released に入れても選択肢に出ない。
            XCTAssertEqual(LanguageOffer.offered(released: LanguageID.shipped, tables: db.textTables), [.ja])
        }
    }

    func testChoiceRoundTrip() {
        for choice in [LanguageChoice.system, .language(.ja), .language(.en), .language(.zhHans),
                       .language(.zhHant), .language(.ko), .language(.pseudo)]
        {
            XCTAssertEqual(LanguageChoice(stored: choice.stored), choice)
        }
        XCTAssertEqual(LanguageChoice(stored: nil), .system)
        XCTAssertEqual(LanguageChoice(stored: "system"), .system)
        XCTAssertEqual(LanguageChoice(stored: "fr"), .system)
        XCTAssertEqual(LanguageChoice(stored: ""), .system)
        XCTAssertEqual(LanguageChoice.defaultsKey, "reforge.language")
    }
}
