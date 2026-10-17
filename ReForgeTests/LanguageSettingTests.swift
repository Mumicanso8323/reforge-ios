import XCTest
import ReForgeEngine
@testable import ReForge

/// L-10b: 言語の設定(AppLanguage・AppModel の切り替え)。macOS の CI で回す。
@MainActor
final class LanguageSettingTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let name = "reforge-lang-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func tempSaves() -> FileSaveStorage {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return FileSaveStorage(directory: dir)
    }

    private func tables() throws -> TextTables {
        try AppModel.loadBundledContent(bundle: .main).textTables
    }

    private func makeLanguage(_ defaults: UserDefaults, pseudo: Bool, preferred: [String] = ["en-US"], pinned: LanguageID? = nil) throws -> AppLanguage {
        addTeardownBlock { InkFont.setLanguage("ja") }
        return AppLanguage(defaults: defaults, tables: try tables(), preferred: preferred, includePseudo: pseudo, pinned: pinned)
    }

    func testPinnedLanguageWinsEvenWhenNotOfferedAndSelectDoesNotOverride() throws {
        let defaults = isolatedDefaults()
        let language = AppLanguage(defaults: defaults, tables: try tables(), preferred: ["en-US"],
                                   includePseudo: false, pinned: .ko)
        addTeardownBlock { InkFont.setLanguage("ja") }
        XCTAssertFalse(language.offered.contains(.ko))
        XCTAssertEqual(language.effective, .ko, "offered に無くても固定が勝つ")
        language.select(.language(.ja))
        XCTAssertEqual(language.effective, .ko, "固定の実行では select が上書きしない")
        XCTAssertNil(defaults.string(forKey: LanguageChoice.defaultsKey), "固定は保存しない")
    }

    private func shownText(_ store: GameStore) -> String {
        // 始まり方(非公開の層は暗い始まり・序で、状態の帯も目標もまだ無い)によらず、画面に出ている文を全部集める
        (store.status.map(\.label) + [store.objective ?? "", store.darkStart?.action.label ?? ""]
            + (store.prologue?.lines ?? []) + store.sceneLines).joined(separator: "\n")
    }

    func testDefaultIsSystemAndSectionHiddenWhileOnlyJapaneseIsOffered() throws {
        let language = try makeLanguage(isolatedDefaults(), pseudo: false)
        XCTAssertEqual(language.choice, .system)
        XCTAssertEqual(language.offered, [.ja])
        XCTAssertEqual(language.effective, .ja, "端末が英語でも、出す言語が日本語だけなら日本語")
        XCTAssertFalse(language.showsSection)
    }

    func testPseudoOfferShowsSection() throws {
        let language = try makeLanguage(isolatedDefaults(), pseudo: true)
        XCTAssertEqual(language.offered, [.ja, .pseudo])
        XCTAssertTrue(language.showsSection)
    }

    func testSelectingPseudoStoresSwitchesTextAndKeepsWorldBytes() async throws {
        let defaults = isolatedDefaults()
        let language = try makeLanguage(defaults, pseudo: true)
        let app = AppModel(saves: tempSaves(), defaults: defaults, language: language)
        app.startNewGame()
        let store = try XCTUnwrap(app.game)
        await store.load()
        let before = try await store.host.saveData(slot: .resume, stamps: [])
        let japanese = shownText(store)
        XCTAssertFalse(japanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "比べる文が画面に無い")
        XCTAssertFalse(japanese.contains("⟦"))

        app.selectLanguage(.language(.pseudo))
        XCTAssertEqual(defaults.string(forKey: LanguageChoice.defaultsKey), "x-pseudo")
        XCTAssertEqual(InkFont.language, "x-pseudo")
        // 切り替えの引き直しを待つ
        await store.setLanguage(language.effective)
        XCTAssertTrue(shownText(store).contains("⟦"), "文が囲みに変わる")
        let during = try await store.host.saveData(slot: .resume, stamps: [])
        XCTAssertEqual(during, before, "切り替えは世界を進めない")

        app.selectLanguage(.language(.ja))
        await store.setLanguage(language.effective)
        XCTAssertEqual(shownText(store), japanese, "日本語に戻すと元の文")
        let after = try await store.host.saveData(slot: .resume, stamps: [])
        XCTAssertEqual(after, before)
    }

    func testDeleteSaveKeepsLanguageAndUnofferedChoiceFallsBackToSystem() throws {
        let defaults = isolatedDefaults()
        let language = try makeLanguage(defaults, pseudo: true)
        let app = AppModel(saves: tempSaves(), defaults: defaults, language: language)
        app.selectLanguage(.language(.pseudo))
        app.startNewGame()
        app.deleteSave()
        XCTAssertEqual(defaults.string(forKey: LanguageChoice.defaultsKey), "x-pseudo", "記録を消しても言語の設定は残る")
        XCTAssertEqual(app.language.choice, .language(.pseudo))

        // 擬似言語を出さない設定の起動では、保存した擬似言語は system に戻って決まる
        let relaunched = try makeLanguage(defaults, pseudo: false)
        XCTAssertEqual(relaunched.effective, .ja)
        XCTAssertFalse(relaunched.showsSection)
    }

    func testSwitchingKeepsClockPausedWhileSettingsOpen() throws {
        let defaults = isolatedDefaults()
        let language = try makeLanguage(defaults, pseudo: true)
        let app = AppModel(saves: tempSaves(), defaults: defaults, language: language)
        app.startNewGame()
        let game = try XCTUnwrap(app.game)
        app.settingsOpen = true
        app.selectLanguage(.language(.pseudo))
        XCTAssertTrue(app.settingsOpen, "切り替えで札は閉じない")
        XCTAssertTrue(game.isPaused, "設定が開いている間は時計が進まない")
        XCTAssertTrue(app.game === game, "ゲームは作り直さない")
    }
}
