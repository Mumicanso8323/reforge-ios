import XCTest
import UIKit
import ReForgeEngine
@testable import ReForge

/// L-13 / TEST-L8: 表の `ui.<区分>.*` の文を、区分の字の大きさ・言語ごとの本当の字体で測る。macOS の CI で回す。
/// 出す言語のうち日本語以外は、button・band・tab・label の幅が区分の上限に収まること(縮める区分は 0.85 倍の余裕込み)。
/// 日本語は測定値を一覧に出すだけ(失敗にしない)。区分の上限は翻訳者への目安で、日本語は今の画面の文だから。
@MainActor
final class TextWidthTests: XCTestCase {
    /// 幅を測る区分(伸ばす区分は、箱が伸びるので幅では測らない)。
    private static let measured: Set<WidthClass> = [.button, .band, .tab, .label]

    private struct Row {
        let id: String
        let language: String
        let width: Int
        let limit: Int
        let text: String
    }

    private func tables() throws -> TextTables {
        try AppModel.loadBundledContent(bundle: .main).textTables
    }

    /// 差し込みのある文は、数→文字列の順に試した見本の値で組む。どちらでも組めない文は数えて外す。
    private func sample(_ pattern: String, language: LanguageID) -> String? {
        guard let names = try? MessageFormat.argumentNames(pattern) else { return nil }
        let numeric = Dictionary(uniqueKeysWithValues: names.map { ($0, RenderedArg.number(12, places: 0)) })
        if let text = try? MessageFormat.render(pattern, args: numeric, language: language) { return text }
        let words = Dictionary(uniqueKeysWithValues: names.map { ($0, RenderedArg.string("あいう")) })
        return try? MessageFormat.render(pattern, args: words, language: language)
    }

    private func width(_ text: String, size: Int, language: LanguageID) -> Int {
        let family = InkFont.family(for: language)
        let font = UIFont(name: family, size: CGFloat(size)) ?? UIFont.systemFont(ofSize: CGFloat(size))
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return Int(measured.rounded(.up))
    }

    private func rows(for language: LanguageID) throws -> (rows: [Row], skipped: Int) {
        let loaded = try tables()
        var out: [Row] = []
        var skipped = 0
        for id in (loaded.tables[.ja] ?? [:]).keys.sorted() where id.rawValue.hasPrefix("ui.") {
            let cls = WidthClass.of(id)
            guard Self.measured.contains(cls), let limit = cls.maxWidth else { continue }
            guard let pattern = loaded.pattern(id, language, marker: false), let text = sample(pattern, language: language) else {
                skipped += 1
                continue
            }
            let w = width(text, size: cls.pointSize, language: language)
            // 縮める区分は、縮めた幅(w * 85 / 100)で比べる(整数で)
            let effective = cls.shrinkable ? w * WidthClass.minimumScale / 100 : w
            out.append(Row(id: id.rawValue, language: language.rawValue, width: effective, limit: limit, text: text))
        }
        return (out, skipped)
    }

    /// 出す言語のうち日本語以外: 上限を超える文があれば、ID・言語・測った幅・上限を一覧にして失敗。
    func testReleasedLanguagesOtherThanJapaneseFit() throws {
        for language in LanguageID.released where language != .ja {
            let measured = try rows(for: language)
            let over = measured.rows.filter { $0.width > $0.limit }
            XCTAssertTrue(over.isEmpty, over.map { "\($0.id) [\($0.language)] 幅 \($0.width) > 上限 \($0.limit)" }.joined(separator: "\n"))
        }
    }

    /// 日本語: 上限を超える文の一覧を出す(失敗にしない。報告に貼る)。
    func testJapaneseMeasurementsAreListed() throws {
        let measured = try rows(for: .ja)
        XCTAssertFalse(measured.rows.isEmpty, "測る文が 1 つも無い(区分の引き方が壊れている)")
        let over = measured.rows.filter { $0.width > $0.limit }.sorted { $0.id < $1.id }
        let lines = over.map { "\($0.id)\t幅 \($0.width)\t上限 \($0.limit)" }
        let summary = "測った \(measured.rows.count) 文(組めずに外した \(measured.skipped))・上限を超える \(over.count) 文\n" + lines.joined(separator: "\n")
        print("TEXTWIDTH-JA " + summary.replacingOccurrences(of: "\n", with: "\nTEXTWIDTH-JA "))
        let attachment = XCTAttachment(string: summary)
        attachment.name = "textwidth_ja"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 出す言語が増えたとき、日本語以外の測定が自動で効く(テストが言語を列挙する)。
    func testEveryReleasedLanguageHasAFont() {
        for language in LanguageID.released {
            XCTAssertNotNil(UIFont(name: InkFont.family(for: language), size: 12), "\(language.rawValue) の字体が見つからない")
        }
    }
}
