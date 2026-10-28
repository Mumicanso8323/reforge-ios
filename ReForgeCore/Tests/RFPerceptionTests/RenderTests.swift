import Foundation
import RFContent
import RFKernel
import RFMatter
import RFPerception
import RFTestSupport
import RFWorld
import XCTest

final class RenderTests: XCTestCase {
    func testRenderUsesTypedArgumentsAndUnknownForMissingArguments() throws {
        var content = try TestContent.publicOnly()
        content.textTables.tables[.ja]?["test.inner"] = "inner"
        content.textTables.tables[.ja]?["test.outer"] = "{word}:{nested}:{subject}:{person}:{number}"
        content.textTables.tables[.ja]?["test.missing"] = "{needed}"
        let p = Perceiver(content: content, known: [])
        let rendered = p.render(TextRef("test.outer", [
            "word": .text("test.inner"),
            "nested": .ref(TextRef("test.inner")),
            "subject": .subject(Subject.item("wood")),
            "person": .person(.noah),
            "number": .fixed(125, places: 2),
        ]))
        XCTAssertEqual(rendered, "inner:inner:薪:ノア:1.25") // ja-table
        XCTAssertEqual(p.render(TextRef("test.missing")), p.text(Perceiver.unknownText))
    }

    func testPseudoWrapsOnlyTheOuterMessageAndAuditsOnce() throws {
        var content = try TestContent.publicOnly()
        content.textTables.tables[.ja]?["test.inner"] = "abcd"
        content.textTables.tables[.ja]?["test.outer"] = "{inner}"
        let auditor = PerceptionAuditor()
        let p = Perceiver(content: content, known: [], language: .pseudo, auditor: auditor)
        let text = p.render(TextRef("test.outer", ["inner": .ref(TextRef("test.inner"))]))
        XCTAssertEqual(text, "⟦abcd・・・⟧") // ja-table
        XCTAssertEqual(auditor.inspectedCount, 1)
    }

    func testUnitPatternsAndValidation() throws {
        var content = try TestContent.publicOnly()
        let stat = Subject.stat("stat.test.air")
        content.perception[stat] = SubjectDef(subject: stat, variants: [
            Variant(when: .always, name: "text.stat.air", display: .number(divisor: 1, unit: "text.unit.test", decimals: 0)),
        ])
        content.textTables.tables = content.textTables.tables.filter { $0.key == .ja }
        content.textTables.tables[.ja]?["text.unit.test"] = "{value} hour"
        content.textTables.tables[.en, default: [:]]["text.unit.test"] = "{value, plural, one {# hour} other {# hours}}"
        XCTAssertEqual(Perceiver(content: content, known: [], language: .en).stat("stat.test.air", value: Milli(raw: 2)), "2 hours")

        content.textTables.tables[.en]?["text.unit.test"] = "hours"
        XCTAssertTrue(ContentValidator.validate(content).contains { $0.level == .error && $0.rule == "text.unit" })
        content.textTables.tables[.ja]?["text.unit.test"] = "hours"
        content.textTables.tables[.en]?["text.unit.test"] = "{value} hours"
        XCTAssertTrue(ContentValidator.validate(content).contains { $0.level == .error && $0.rule == "text.unit" })
        content.textTables.tables[.ja]?["text.unit.test"] = "{value} hour"
        XCTAssertFalse(ContentValidator.validate(content).contains { $0.level == .error && $0.rule == "text.unit" })

        content.textTables.tables[.ja]?["text.unit.test"] = "hours"
        content.textTables.tables[.en]?["text.unit.test"] = "hours"
        XCTAssertEqual(Perceiver(content: content, known: [], language: .ja).stat("stat.test.air", value: Milli(raw: 2)), "2hours")
        XCTAssertEqual(Perceiver(content: content, known: [], language: .en).stat("stat.test.air", value: Milli(raw: 2)),
                       Perceiver(content: content, known: [], language: .en).text(Perceiver.unknownText))
    }

    func testNameJoinReordersAndSkipsEmptyParts() throws {
        var content = try TestContent.publicOnly()
        content.textTables.tables[.ja]?["text.grade.fine"] = "a"
        content.textTables.tables[.ja]?["text.matter.fe"] = "b"
        content.textTables.tables[.ja]?["text.shape.plate"] = "c"
        content.textTables.meta[.ja] = TextMeta(nameJoin: NameJoin(order: ["grade", "substance", "shape"], separator: " "))
        let name = MatterName([.shape(.plate), .substance("Fe"), .grade(.fine, .metal)])
        XCTAssertEqual(Perceiver(content: content, known: []).name(of: name), "a b c")
        content.textTables.tables[.ja]?["text.grade.fine"] = ""
        XCTAssertEqual(Perceiver(content: content, known: []).name(of: name), "b c")
        content.textTables.meta[.ja] = TextMeta()
        XCTAssertEqual(Perceiver(content: content, known: []).name(of: name), "cb")
    }

    func testGlyphTextUsesJapaneseForPseudoAndFallsBackToGlyph() throws {
        var content = try TestContent.publicOnly()
        let subject = Subject.item("wood")
        content.perception[subject]?.variants[0].glyph = "@"
        content.perception[subject]?.variants[0].glyphText = "test.glyph"
        content.textTables.tables[.ja]?["test.glyph"] = "*"
        XCTAssertEqual(Perceiver(content: content, known: []).glyph(subject), "\u{FF0A}")
        XCTAssertEqual(Perceiver(content: content, known: [], language: .pseudo).glyph(subject), "\u{FF0A}")
        XCTAssertEqual(Perceiver(content: content, known: [], language: .en).glyph(subject), "\u{FF20}")
    }

    func testCoreUITextsAndSourcesContainNoPlayerJapaneseLiterals() throws {
        let content = try TestContent.publicOnly()
        let p = Perceiver(content: content, known: [])
        for id in ["ui.daywrap.first", "ui.daywrap.lines", "ui.daywrap.water"] {
            XCTAssertNotEqual(p.render(TextRef(TextID(id), ["name": .subject(Subject.item("wood")), "n": .int(1)])), p.text(Perceiver.unknownText))
            XCTAssertNotNil(content.textTables.tables[.ja]?[TextID(id)])
        }
        for id in ["ui.roster.include", "ui.grant.title"] {
            XCTAssertEqual(p.render(TextRef(TextID(id))), content.textTables.tables[.ja]?[TextID(id)])
        }

        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for directory in ["RFPresent", "RFPerception"] {
            let url = root.appendingPathComponent("Sources/\(directory)")
            let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" && !["HintAudit.swift", "ForbiddenAudit.swift"].contains($0.lastPathComponent) }
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                let literals = try XCTUnwrap(try? NSRegularExpression(pattern: #"(?s)\"(?:\\.|[^\"])*\""#))
                    .matches(in: source, range: NSRange(source.startIndex..., in: source))
                    .compactMap { Range($0.range, in: source).map { String(source[$0]) } }
                // 開けない束の例外の文(ContentLoader.loadBundled と同じ。画面の ContentErrorView に出る。L-11 の BootText が両方を置き換える)
                for literal in literals where literal != "\"？\"" && literal != "\"日本語の本文の束を開けない\"" {
                    XCTAssertFalse(literal.unicodeScalars.contains { scalar in
                        (0x3040...0x30FF).contains(scalar.value) || (0x3400...0x9FFF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
                    }, "\(file.lastPathComponent) has a player-facing literal")
                }
            }
        }
    }

    func testMissingUnitEntryInExistingTableIsError() throws {
        var content = try TestContent.publicOnly()
        let stat = Subject.stat("stat.test.air")
        content.perception[stat] = SubjectDef(subject: stat, variants: [
            Variant(when: .always, name: "text.stat.air", display: .number(divisor: 1, unit: "text.unit.test", decimals: 0)),
        ])
        content.textTables.tables[.ja]?["text.unit.test"] = "{value} hour"
        func unitErrors() -> [ContentValidator.Issue] {
            ContentValidator.validate(content).filter { $0.level == .error && $0.rule == "text.unit" }
        }
        // 日本語だけなら誤りにならない
        content.textTables.tables = content.textTables.tables.filter { $0.key == .ja }
        XCTAssertTrue(unitErrors().isEmpty)
        // 別の言語の表があって、その ID が無ければ誤り
        content.textTables.tables[.en, default: [:]]["test.other"] = "x"
        XCTAssertFalse(unitErrors().isEmpty)
        // 揃っていれば誤りにならない
        content.textTables.tables[.en]?["text.unit.test"] = "{value} hours"
        XCTAssertTrue(unitErrors().isEmpty)
    }

    func testMapMarkFallbackChainIsPartThenKindThenBlock() throws {
        var content = try TestContent.publicOnly()
        let kind = POIKindID("test_kind")
        let part = Subject.part("test_part")
        let p = { Perceiver(content: content, known: [], language: .ja) }
        func chain(_ q: Perceiver) -> String {
            q.glyph(part, fallback: q.glyph(Subject.poi(kind), fallback: "\u{2592}"))
        }
        XCTAssertEqual(chain(p()), MapGlyphFont.safe("\u{2592}"))
        content.glyphs[Subject.poi(kind)] = "K"
        XCTAssertEqual(chain(p()), MapGlyphFont.safe("K"))
        content.glyphs[part] = "P"
        XCTAssertEqual(chain(p()), MapGlyphFont.safe("P"))
    }
}
