import XCTest
import Observation
import ReForgeEngine
@testable import ReForge

/// L-11: アプリの固定文言の口(UIText)。macOS の CI で回す。
@MainActor
final class UITextTests: XCTestCase {
    private func tables() throws -> TextTables {
        try AppModel.loadBundledContent(bundle: .main).textTables
    }

    private func configured(_ language: LanguageID = .ja) throws -> UIText {
        let text = UIText.shared
        let loaded = try tables()
        text.configure(tables: loaded, language: language, markFallback: false)
        addTeardownBlock { UIText.shared.configure(tables: loaded, language: .ja, markFallback: false) }
        return text
    }

    /// (i) 日本語の出力が、旧カタログの文字と同じ(代表の 6 つ: 数・名前・割合・複数の引数・約物を表で持つ文・読み上げのラベル)。
    func testRepresentativeSentencesKeepTheOldJapanese() throws {
        let text = try configured()
        XCTAssertEqual(text.string("ui.band.undo_remaining", ["seconds": .int(3)]), "残り 3 秒") // ja-table
        XCTAssertEqual(text.string("ui.band.resume_last", ["last": .string("A")]), "前回: A") // ja-table
        XCTAssertEqual(text.string("ui.bubble.purity", ["tenths": .string("3")]), "手ざわり: 三割くらい") // ja-table
        XCTAssertEqual(text.string("ui.band.made_item", ["name": .string("A"), "count": .int(2)]), "A 2") // ja-table
        XCTAssertEqual(text.string("ui.band.resume_both", ["last": .string("A"), "next": .string("B")]), "前回: A。次: B") // ja-table
        XCTAssertEqual(text.string("ui.a11y.settings_open"), "設定を開く") // ja-table
        XCTAssertEqual(text.string("ui.button.language_system", ["language": .string("日本語")]), "端末に合わせる(日本語)") // ja-table
    }

    /// 割合の言い回しは表の言葉(漢数字の表をコードに持たない)。1〜9 は「N割くらい」の漢数字・10 は十・範囲外は数字のまま。
    func testPurityTenthsComeFromTheTable() throws {
        let text = try configured()
        let words = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        for (index, word) in words.enumerated() {
            XCTAssertEqual(text.string("ui.bubble.purity", ["tenths": .string(String(index + 1))]), "手ざわり: \(word)割くらい") // ja-table
        }
        XCTAssertEqual(text.string("ui.body.slot_dawn", ["day": .int(3)]), "3 日目の夜明け") // ja-table
        XCTAssertEqual(text.string("ui.band.made_sep"), "・") // ja-table
    }

    /// (ii) 擬似言語で configure すると、⟦…⟧ で囲まれた文を返す。
    func testPseudoLanguageWrapsTheSentence() throws {
        let text = try configured(.pseudo)
        let sentence = text.string("ui.button.close")
        XCTAssertTrue(sentence.hasPrefix("⟦") && sentence.hasSuffix("⟧"), sentence)
        XCTAssertTrue(sentence.contains("閉じる")) // ja-table
    }

    /// (iii) 表に無い ID は落ちずに「？」(開発の版は assertionFailure なので、表に無くて BootText にも無い ID は
    /// 製品の形(Release)でだけ確かめる)。BootText にある ID は表が無くても出る。
    func testMissingIDDoesNotCrashInRelease() throws {
#if !DEBUG
        let text = try configured()
        XCTAssertEqual(text.string("ui.body.no_such_id"), "？")
#endif
        let text = try configured()
        XCTAssertEqual(text.string("ui.body.settings"), "設定") // ja-table
    }

    /// 組めない引数(足りない)でも落とさない。
    func testMissingArgumentRendersWithoutCrashing() throws {
        let text = try configured()
        XCTAssertFalse(text.string("ui.button.language_system").isEmpty)
    }

    /// (iv) 言語を替えると、同じ UIText を読む View が作り直されずに更新される(Observation で変更が通知される)。
    func testChangingLanguageNotifiesObservers() throws {
        let text = try configured(.ja)
        final class Flag: @unchecked Sendable { var changed = false }
        let flag = Flag()
        withObservationTracking {
            _ = text.string("ui.button.close")
        } onChange: {
            flag.changed = true
        }
        text.configure(tables: try tables(), language: .pseudo, markFallback: false)
        XCTAssertTrue(flag.changed, "言語を替えても、読んでいる側に通知が届かない") // ja-table
        XCTAssertEqual(text.language, .pseudo)
    }
}
