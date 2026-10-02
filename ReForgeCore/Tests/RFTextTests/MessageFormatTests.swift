import Foundation
import RFKernel
import RFText
import XCTest

final class MessageFormatTests: XCTestCase {
    func testEnglishPluralAndExactMatch() throws {
        let pattern = "{n, plural, =0 {zero} one {one} other {other}}"
        XCTAssertEqual(try render(pattern, .number(0, places: 0), language: .en), "zero")
        XCTAssertEqual(try render(pattern, .number(1, places: 0), language: .en), "one")
        XCTAssertEqual(try render(pattern, .number(10, places: 1), language: .en), "other")
        XCTAssertEqual(try render(pattern, .number(2, places: 0), language: .en), "other")
    }

    func testEastAsianPluralRulesAlwaysUseOther() throws {
        let pattern = "{n, plural, one {one} other {other}}"
        for language in [LanguageID.ja, .zhHans, .zhHant, .ko] {
            for number in [Int64(0), 1, 2] {
                XCTAssertEqual(try render(pattern, .number(number, places: 0), language: language), "other")
            }
        }
    }

    func testSelectUsesMatchingBranchOrOther() throws {
        let pattern = "{kind, select, wood {wood} stone {stone} other {other}}"
        XCTAssertEqual(try MessageFormat.render(pattern, args: ["kind": .string("wood")], language: .en), "wood")
        XCTAssertEqual(try MessageFormat.render(pattern, args: ["kind": .string("iron")], language: .en), "other")
    }

    func testJosa() throws {
        XCTAssertEqual(Josa.pick(after: "책", pair: ("이", "가")), "이")
        XCTAssertEqual(Josa.pick(after: "나무", pair: ("이", "가")), "가")
        XCTAssertEqual(Josa.pick(after: "돌", pair: ("으로", "로")), "로")
        XCTAssertEqual(Josa.pick(after: "돌", pair: ("이", "가")), "이")
        XCTAssertEqual(Josa.pick(after: "3", pair: ("이", "가")), "이")
        XCTAssertEqual(Josa.pick(after: "2", pair: ("이", "가")), "가")
        XCTAssertEqual(Josa.pick(after: "1", pair: ("으로", "로")), "로", "일 は ㄹ で終わる")
        XCTAssertEqual(Josa.pick(after: "8", pair: ("으로", "로")), "로", "팔 は ㄹ で終わる")
        XCTAssertEqual(Josa.pick(after: "3", pair: ("으로", "로")), "으로")
        XCTAssertEqual(Josa.pick(after: "1", pair: ("이", "가")), "이")
        XCTAssertEqual(Josa.pick(after: "A", pair: ("이", "가")), "이(가)")
        XCTAssertEqual(try MessageFormat.render("{actor, josa, 이/가}", args: ["actor": .string("책")], language: .ko), "책이")
    }

    func testCap() throws {
        XCTAssertEqual(try MessageFormat.render("{subject, cap}", args: ["subject": .string("iron ore")], language: .en), "Iron ore")
        XCTAssertEqual(try MessageFormat.render("{subject, cap}", args: ["subject": .string("나무")], language: .en), "나무")
        XCTAssertEqual(try MessageFormat.render("{subject, cap}", args: ["subject": .string("漢字")], language: .en), "漢字")
        XCTAssertEqual(try MessageFormat.render("{subject, cap}", args: ["subject": .string("")], language: .en), "")
    }

    func testNestedBranchPoundAndQuotedBraces() throws {
        XCTAssertEqual(
            try MessageFormat.render("{n, plural, other {{who} has # items}}", args: ["n": .number(2, places: 0), "who": .string("Ada")], language: .en),
            "Ada has 2 items"
        )
        XCTAssertEqual(try MessageFormat.render("'{' {name} '}'", args: ["name": .string("ore")], language: .en), "{ ore }")
    }

    func testMissingAndWrongArgumentsDoNotThrowButMalformedPluralDoes() throws {
        XCTAssertEqual(try MessageFormat.render("{name}", args: [:], language: .en), "⟦?name⟧")
        XCTAssertEqual(try MessageFormat.render("{n, plural, one {one} other {other}}", args: ["n": .string("one")], language: .en), "⟦?n⟧")
        XCTAssertEqual(try MessageFormat.render("{actor, josa, 이/가}", args: ["actor": .number(2, places: 0)], language: .ko), "⟦?actor⟧")
        XCTAssertThrowsError(try MessageFormat.render("{n, plural, one {one}}", args: ["n": .number(1, places: 0)], language: .en))
    }

    func testNumberTextIsDeterministicForAllLanguages() {
        let languages: [LanguageID] = [.ja, .en, .zhHans, .zhHant, .ko]
        for language in languages {
            XCTAssertEqual(NumberText.format(-150, places: 2, language: language), "-1.50")
            XCTAssertEqual(NumberText.format(1234, places: 0, language: language), "1234")
            XCTAssertEqual(NumberText.format(1234, places: 1, language: language), "123.4")
            XCTAssertEqual(NumberText.format(1234, places: 2, language: language), "12.34")
            XCTAssertEqual(NumberText.format(1234, places: 3, language: language), "1.234")
        }
    }

    func testTextReferenceAndArgumentCodableRoundTrip() throws {
        let ref = TextRef("text.notice", [
            "amount": .fixed(150, places: 2),
            "person": .person("person.test"),
            "nested": .ref(TextRef("text.child", ["count": .int(2)])),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(ref)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertEqual(json, #"{"args":{"amount":{"fixed":{"_0":150,"places":2}},"nested":{"ref":{"_0":{"args":{"count":{"int":{"_0":2}}},"id":"text.child"}}},"person":{"person":{"_0":"person.test"}}},"id":"text.notice"}"#)
        XCTAssertEqual(try JSONDecoder().decode(TextRef.self, from: encoded), ref)
    }

    private func render(_ pattern: String, _ value: RenderedArg, language: LanguageID) throws -> String {
        try MessageFormat.render(pattern, args: ["n": value], language: language)
    }
}
