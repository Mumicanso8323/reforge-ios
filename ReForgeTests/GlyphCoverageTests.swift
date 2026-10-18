import XCTest
import CoreText
import UIKit
import ReForgeEngine
@testable import ReForge

/// TEST-L7(L-12): 言語ごとに、画面の文と地図の字が字体(と iOS の代わりの字体)で描けること。macOS の CI で回す。
/// 描ける = CTFontCreateForString が LastResort でない字体を返し、その字体で字形が得られる。
/// 非公開の層の文の字は、統合担当が非公開の層を重ねてこのテストを回して確かめる(公開の層だけでは日本語の公開の分だけ)。
@MainActor
final class GlyphCoverageTests: XCTestCase {
    private struct Miss: CustomStringConvertible {
        var char: String
        var language: String
        var place: String
        var description: String { "\(language) \(place) U+\(char.unicodeScalars.map { String($0.value, radix: 16, uppercase: true) }.joined(separator: "+")) \(char)" }
    }

    /// base の字体(と代わりの字体)で text の 1 字が描けるか。
    private func canDraw(_ scalar: Unicode.Scalar, base: CTFont) -> Bool {
        let s = String(scalar)
        let units = Array(s.utf16)
        let used = CTFontCreateForString(base, s as CFString, CFRange(location: 0, length: units.count))
        let name = CTFontCopyPostScriptName(used) as String
        if name.contains("LastResort") { return false }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(used, units, &glyphs, units.count) && glyphs[0] != 0
    }

    private func misses(in text: String, language: String, place: String, base: CTFont) -> [Miss] {
        var out: [Miss] = []
        var seen = Set<Unicode.Scalar>()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format { continue }
            guard seen.insert(scalar).inserted else { continue }
            if !canDraw(scalar, base: base) { out.append(Miss(char: String(scalar), language: language, place: place)) }
        }
        return out
    }

    private func ctFont(_ name: String, size: CGFloat = 15) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    private func report(_ misses: [Miss]) -> String {
        misses.map(\.description).joined(separator: "\n")
    }

    /// 字体の名前そのものが実在する(打ち間違いで黙って別の字体になるのを防ぐ)。
    func testEveryShippedFamilyNameExists() {
        let names = ["PingFangSC-Regular", "PingFangTC-Regular", "AppleSDGothicNeo-Regular", "BIZUDGothic-Regular"]
        for name in names {
            XCTAssertNotNil(UIFont(name: name, size: 15), "\(name) が引けない")
        }
        for language in LanguageID.shipped {
            XCTAssertTrue(names.contains(InkFont.family(for: language)), "\(language.rawValue) の字体の名前が一覧に無い")
        }
    }

    /// 画面の文: AppLanguage が出せる言語(= 出す言語)の表の全部の値の全部の字。
    func testScreenTextIsDrawableForReleasedLanguages() throws {
        let content = try AppModel.loadBundledContent(bundle: .main)
        var all: [Miss] = []
        for language in LanguageID.released {
            let base = ctFont(InkFont.family(for: language))
            let table = content.textTables.tables[language] ?? [:]
            for (id, text) in table {
                all += misses(in: text, language: language.rawValue, place: "text:\(id.rawValue)", base: base)
            }
        }
        XCTAssertTrue(all.isEmpty, "字体で描けない字:\n\(report(all))")
    }

    /// 日本語以外の字体(簡体字・繁体字・韓国語・英語): その言語の表の文と、日本語の表の文(訳の無い文はこれが出る)の全部の字が、
    /// その言語の字体と iOS の代わりの字体で描ける(言語を出す前に豆腐を見つける)。
    func testScreenTextIsDrawableInEveryShippedFont() throws {
        let content = try AppModel.loadBundledContent(bundle: .main)
        let japanese = content.textTables.tables[.ja] ?? [:]
        var all: [Miss] = []
        for language in LanguageID.shipped where language != .ja {
            let base = ctFont(InkFont.family(for: language))
            for (id, text) in content.textTables.tables[language] ?? [:] {
                all += misses(in: text, language: language.rawValue, place: "text:\(id.rawValue)", base: base)
            }
            for (id, text) in japanese {
                all += misses(in: text, language: language.rawValue, place: "ja-text:\(id.rawValue)", base: base)
            }
        }
        XCTAssertTrue(all.isEmpty, "字体で描けない字:\n\(report(all))")
    }

    /// 地図の字: 地図の 1 マスの字体(BIZ UD ゴシック)か iOS の代わりの字体で描ける。
    func testMapGlyphsAreDrawable() throws {
        let content = try AppModel.loadBundledContent(bundle: .main)
        let base = ctFont(FontBook.mapFont, size: 22)
        var all: [Miss] = []
        for (subject, def) in content.perception {
            for variant in def.variants {
                if let glyph = variant.glyph {
                    all += misses(in: glyph, language: "map", place: "glyph:\(subject.rawValue)", base: base)
                }
                if let id = variant.glyphText {
                    for language in LanguageID.released {
                        if let text = content.textTables.tables[language]?[id] {
                            all += misses(in: text, language: language.rawValue, place: "glyphText:\(id.rawValue)", base: base)
                        }
                    }
                }
            }
        }
        for (subject, glyph) in content.glyphs {
            all += misses(in: glyph, language: "map", place: "glyphs:\(subject.rawValue)", base: base)
        }
        for (name, glyph) in [("noah", TilePalette.noahGlyph), ("member", TilePalette.memberGlyph), ("spent", TilePalette.spentGlyph)] {
            all += misses(in: glyph, language: "map", place: "palette:\(name)", base: base)
        }
        XCTAssertTrue(all.isEmpty, "字体で描けない地図の字:\n\(report(all))")
    }
}
