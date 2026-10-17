import XCTest
import ReForgeEngine
@testable import ReForge

/// L-11 / BRK-27: 読み込みの失敗の画面の文(BootText)は、文言の表が読めなくても出せる。macOS の CI で回す。
@MainActor
final class BootTextTests: XCTestCase {
    /// (i) 日本語の値が、公開の層の日本語の表の同じ ID の値と同じ(ずれない)。
    func testJapaneseValuesMatchThePublicTable() throws {
        let tables = try AppModel.loadBundledContent(bundle: .main).textTables
        let japanese = try XCTUnwrap(BootText.table[.ja])
        XCTAssertFalse(japanese.isEmpty)
        for (id, text) in japanese {
            XCTAssertEqual(tables.tables[.ja]?[id], text, "\(id.rawValue) が BootText と公開の層の表でずれている") // ja-table
        }
    }

    /// (ii) 出す言語の全部に BootText の項がある。
    func testEveryReleasedLanguageHasBootTextEntries() {
        for language in LanguageID.released {
            XCTAssertNotNil(BootText.table[language],
                            "\(language.rawValue) を出す言語に増やすなら、読み込みの失敗の画面の文(BootText)にもその言語の項が要る")
        }
    }

    func testLookupFallsBackToJapaneseAndNilForUnknownID() {
        XCTAssertEqual(BootText.string("ui.body.load_failed", .ko), BootText.table[.ja]?["ui.body.load_failed"])
        XCTAssertNil(BootText.string("ui.body.not_a_boot_text", .ja))
    }

    /// 表が空でも、読み込みの失敗の画面と設定の札の題・角のボタンの読み上げは BootText から出る。
    func testUITextFallsBackToBootTextWhenTablesAreMissing() {
        let shared = UIText.shared
        shared.configure(tables: TextTables(), language: .ja, markFallback: false)
        addTeardownBlock { UIText.shared.configure(tables: TextTables(), language: .ja, markFallback: false) }
        XCTAssertEqual(shared.string("ui.body.load_failed"), "データを読み込めませんでした") // ja-table
        XCTAssertEqual(shared.string("ui.a11y.settings_open"), "設定を開く") // ja-table
        XCTAssertEqual(shared.string("ui.a11y.settings_close"), "設定を閉じる") // ja-table
        XCTAssertEqual(shared.string("ui.body.settings"), "設定") // ja-table
    }
}
