import Foundation
import RFContent
import RFKernel
import RFText
import RFTestSupport
import XCTest

final class TextTablesTests: XCTestCase {
    func testUnmarkedTextsUseJapaneseAndLegacyTextsCanReadAndWrite() throws {
        var db = ContentDB()
        try ContentLoader.apply(json: Data(#"{"texts":{"text.a":"alpha"},"nameJoin":{"order":["shape"],"separator":""}}"#.utf8), to: &db)
        XCTAssertEqual(db.texts["text.a"], "alpha")
        XCTAssertEqual(db.textTables.tables[.ja]?["text.a"], "alpha")
        XCTAssertEqual(db.textTables.meta[.ja]?.nameJoin, NameJoin(order: ["shape"], separator: ""))
        db.texts["text.a"] = "changed"
        XCTAssertEqual(db.textTables.tables[.ja]?["text.a"], "changed")
    }

    func testLanguageLookupFallbackAndMarker() throws {
        var db = ContentDB()
        try ContentLoader.apply(json: Data(#"{"texts":{"text.a":"alpha","text.b":"beta"}}"#.utf8), to: &db)
        try ContentLoader.apply(json: Data(#"{"language":"en","texts":{"text.a":"english"},"nameJoin":{"order":["shape"],"separator":" "}}"#.utf8), to: &db)
        XCTAssertEqual(db.textTables.available, [.ja, .en])
        XCTAssertEqual(db.textTables.meta[.en]?.nameJoin?.separator, " ")
        XCTAssertEqual(db.textTables.lookup("text.a", .en), .found("english"))
        XCTAssertEqual(db.textTables.lookup("text.b", .en), .fallback("beta"))
        XCTAssertEqual(db.textTables.lookup("text.none", .en), .missing)
        db.textTables.tables[.zhHans] = ["text.b": "simplified"]
        XCTAssertEqual(db.textTables.lookup("text.b", .zhHant), .fallback("beta"))
        XCTAssertEqual(db.textTables.pattern("text.b", .en, marker: true), "[ja]beta")
        XCTAssertEqual(db.textTables.pattern("text.a", .en, marker: true), "english")
    }

    func testPseudoLanguageExtendsJapanesePatternWithoutBreakingIt() throws {
        var tables = TextTables()
        tables.tables[.ja] = ["short": "abcde", "plural": "{n, plural, other {# items}}"]
        XCTAssertEqual(tables.lookup("short", .pseudo), .found("⟦abcde・・⟧"))
        guard case .found(let pattern) = tables.lookup("plural", .pseudo) else { return XCTFail("missing pseudo pattern") }
        let rendered = try MessageFormat.render(pattern, args: ["n": .number(2, places: 0)], language: .pseudo)
        XCTAssertTrue(rendered.hasPrefix("⟦2 items"))
        XCTAssertTrue(rendered.hasSuffix("⟧"))
    }

    func testLanguageLoadingErrorsRemovalAndIgnoredL10n() throws {
        var db = ContentDB()
        XCTAssertThrowsError(try ContentLoader.apply(json: Data(#"{"language":"x-pseudo","texts":{"x":"x"}}"#.utf8), to: &db))
        XCTAssertThrowsError(try ContentLoader.apply(json: Data(#"{"language":"en","textGates":[]}"#.utf8), to: &db))
        XCTAssertThrowsError(try ContentLoader.apply(json: Data(#"{"language":"ja","texts":{"x":"x"}}"#.utf8), to: &db, name: "text/en/test.json"))

        let layer = try temporaryLayer()
        try write(#"{"texts":{"same":"ja"}}"#, at: "text/ja/a.json", in: layer)
        try write(#"{"language":"en","texts":{"same":"en"}}"#, at: "text/en/a.json", in: layer)
        XCTAssertNoThrow(try ContentLoader.load(layers: [layer]))
        try write(#"{"texts":{"same":"again"}}"#, at: "text/ja/b.json", in: layer)
        XCTAssertThrowsError(try ContentLoader.load(layers: [layer]))

        db.textTables.tables[.ja] = ["remove": "ja"]
        db.textTables.tables[.en] = ["remove": "en"]
        try ContentLoader.apply(json: Data(#"{"remove":{"texts":["remove"]}}"#.utf8), to: &db)
        XCTAssertNil(db.textTables.tables[.ja]?["remove"])
        XCTAssertNil(db.textTables.tables[.en]?["remove"])

        let ignored = try temporaryLayer()
        try write(#"{"texts":{"kept":"yes"}}"#, at: "a.json", in: ignored)
        try write(#"{"notAContentKey":true}"#, at: "l10n/ignored.json", in: ignored)
        XCTAssertEqual(try ContentLoader.load(layers: [ignored]).texts["kept"], "yes")
        XCTAssertFalse(ContentLoader.isContentPath("l10n/ignored.json"))
    }

    func testTextTableValidationRules() throws {
        var db = try TestContent.publicOnly()
        db.textTables.tables[.ja]?["format"] = "{"
        db.textTables.tables[.ja]?["args"] = "{who}"
        db.textTables.tables[.en] = ["args": "{actor}", "orphan": "orphan", "glyph": "ab"]
        db.textTables.tables[.ja]?["glyph"] = "ab"
        db.perception["item:wood"]?.variants[0].glyphText = "glyph"
        let issues = ContentValidator.validate(db)
        XCTAssertTrue(issues.contains { $0.level == .error && $0.rule == "text.format" })
        XCTAssertTrue(issues.contains { $0.level == .error && $0.rule == "text.args" })
        XCTAssertTrue(issues.contains { $0.level == .warning && $0.rule == "text.orphan" })
        XCTAssertTrue(issues.contains { $0.level == .error && $0.rule == "perception.glyphText" })
    }

    /// 公開の層の文言は text/<言語>/ にだけ置く(L-02 で移した。件数と指紋は移すときに確かめ済み 205 件 0xe86bc08f462bde8b。
    /// 文言を足すたびに数が変わるので、ここでは置き場所の決まりだけを見る)。
    func testPublicTextsLiveOnlyUnderTextDirectories() throws {
        let db = try TestContent.publicOnly()
        XCTAssertGreaterThanOrEqual(db.texts.count, 205)
        XCTAssertEqual(ContentValidator.validate(db).filter { $0.level == .error }, [])
        let root = TestContent.publicLayer
        for rel in try ContentLoader.relativeJSONPaths(in: root) where !rel.hasPrefix("text/") {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(rel)))
            XCTAssertNil((object as? [String: Any])?["texts"], "\(rel) に texts がある(text/ja/ に置く)")
        }
    }

    private func temporaryLayer() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rf-text-tables-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ json: String, at path: String, in layer: URL) throws {
        let url = layer.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

}
