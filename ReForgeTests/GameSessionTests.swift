import XCTest
import ReForgeCore
import ReForgeContent
@testable import ReForge

/// アプリ側(GameSession・保存・広告枠)の単体テスト。シミュレータで回す。
@MainActor
final class GameSessionTests: XCTestCase {
    private var store: SaveStore!
    private let game: Game = {
        do { return Game(content: try ContentLoader.bundled()) } catch { fatalError("content: \(error)") }
    }()

    /// テストごとに一時ディレクトリの保存先を作る。
    private func newSession() -> GameSession {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        store = SaveStore(directory: dir)
        return GameSession.newGame(game: game, store: store, purchases: { Purchases() })
    }

    func testNewGameStartsOnDayOneWithClockRunning() {
        let s = newSession()
        XCTAssertEqual(s.state.day, 1)
        XCTAssertEqual(s.text.actionsLabel(s.state), "残り行動 10/10")
        XCTAssertFalse(s.isPaused)
        XCTAssertTrue(store.hasResume)
        XCTAssertNotNil(store.loadSavePoint(), "新規開始はセーブ地点")
    }

    func testClockStopsWhenInactiveAndStaysPausedAfterResume() {
        let s = newSession()
        s.advanceClock(by: 30)
        XCTAssertEqual(s.state.dayElapsedSeconds, 30)
        s.didBecomeInactive()
        XCTAssertTrue(s.isPaused)
        s.advanceClock(by: 30)
        XCTAssertEqual(s.state.dayElapsedSeconds, 30, "止まっている間は進まない")
        let resumed = GameSession.resume(game: game, store: store, purchases: { Purchases() })
        XCTAssertEqual(resumed?.isPaused, true, "復帰時は停止状態")
        XCTAssertEqual(resumed?.state, s.state)
    }

    func testSunsetChangesInPlaceAndDawnNeedsNoTap() {
        let s = newSession()
        s.sheet = .craft
        s.advanceClock(by: 180)
        XCTAssertEqual(s.state.phase, .dusk)
        XCTAssertNil(s.sheet, "日没に開いていた「作る」は黙って閉じ、別のシートは出さない")
        XCTAssertTrue(s.rest())
        XCTAssertEqual(s.state.day, 2)
        XCTAssertNil(s.sheet, "夜明けの結果シートは出さない")
        XCTAssertEqual(s.toast?.lines.first?.hasPrefix("夜が明けた"), true, "短い要約を出す")
        XCTAssertEqual(store.loadSavePoint()?.day, 2, "毎朝の自動セーブ")
        XCTAssertTrue(s.state.log.contains { if case .dawn = $0.event { true } else { false } }, "内訳は日誌")
        // 取り消しの数秒が過ぎたら、何も押さなくても時計が動き出し、知らせも消える
        XCTAssertFalse(s.clockRunning)
        s.advanceClock(by: GameSession.undoSeconds)
        XCTAssertFalse(s.canUndoRest)
        XCTAssertTrue(s.clockRunning)
        s.advanceClock(by: GameSession.dawnToastSeconds)
        XCTAssertNil(s.toast)
    }

    func testJournalStaysOpenAtSunset() {
        let s = newSession()
        s.sheet = .journal
        s.advanceClock(by: 180)
        XCTAssertEqual(s.sheet, .journal)
    }

    func testRestRunsWithoutConfirmationAndCanBeUndone() {
        let s = newSession()
        s.perform(.gather(.wood))
        s.advanceClock(by: 30)
        let before = s.state
        XCTAssertTrue(s.rest())
        XCTAssertEqual(s.state.phase, .dusk)
        XCTAssertTrue(s.canUndoRest)
        s.undoRest()
        XCTAssertEqual(s.state, before, "休む前と完全に同じ")
        XCTAssertNil(s.toast)
        XCTAssertEqual(store.loadResume()?.state, before)
    }

    func testSleepUndoAlsoRestoresSavePoint() {
        let s = newSession()
        s.advanceClock(by: 180)
        let dusk = s.state
        let savePoint = s.savePoint
        s.rest()
        XCTAssertEqual(s.savePoint?.day, 2)
        s.undoRest()
        XCTAssertEqual(s.state, dusk)
        XCTAssertEqual(s.savePoint, savePoint)
        XCTAssertEqual(store.loadSavePoint(), savePoint)
    }

    func testDoubleTapRestThenSleepUndoesBoth() {
        let s = newSession()
        let before = s.state
        let savePoint = s.savePoint
        s.rest()
        s.rest()
        XCTAssertEqual(s.state.day, 2)
        s.undoRest()
        XCTAssertEqual(s.state, before, "休む前まで戻る")
        XCTAssertEqual(s.savePoint, savePoint)
    }

    func testUndoIsGoneAfterAnotherAction() {
        let s = newSession()
        s.advanceClock(by: 180)
        s.rest()
        s.perform(.gather(.water))
        XCTAssertFalse(s.canUndoRest)
        let after = s.state
        s.undoRest()
        XCTAssertEqual(s.state, after)
        XCTAssertNotNil(s.toast, "夜明けの要約は残る")
    }

    func testAutoPauseResumesWhenBackButManualPauseStays() {
        let s = newSession()
        s.didBecomeInactive()
        XCTAssertTrue(s.isPaused)
        s.didBecomeActive()
        XCTAssertFalse(s.isPaused, "戻ったら ▶ を押さなくても再開")
        s.pause()
        s.didBecomeInactive()
        s.didBecomeActive()
        XCTAssertTrue(s.isPaused, "手で止めた時計は止めたまま")
    }

    func testGatherFlashAndAutosave() {
        let s = newSession()
        XCTAssertTrue(s.perform(.gather(.water)))
        XCTAssertEqual(s.flash?.text, "+4")
        XCTAssertEqual(store.loadResume()?.state.quantity(ID.water), 22, "行動のたびに保存")
    }

    func testManualSaveWritesSavePoint() {
        let s = newSession()
        s.perform(.gather(.wood))
        s.manualSave()
        XCTAssertEqual(store.loadSavePoint()?.quantity(ID.wood), s.state.quantity(ID.wood))
    }

    func testRecoveryFromGameOver() {
        let s = newSession()
        for _ in 0..<3 {
            s.advanceClock(by: 180)
            s.rest()
        }
        XCTAssertNil(s.gameOverReason)
        XCTAssertEqual(s.savePoint?.day, 4)
        // ここから水を切らして 3 日
        var failed = s.state
        failed.inventory[ID.water] = 0
        let session = GameSession(game: game, state: failed, savePoint: s.savePoint, startPaused: false,
                                  store: store, purchases: { Purchases() })
        for _ in 0..<3 where session.state.isActive {
            session.advanceClock(by: 180)
            session.rest()
        }
        XCTAssertEqual(session.gameOverReason, .dehydration)
        XCTAssertEqual(session.recoveryChoices().count, 4)
        // 毎朝の自動セーブで、セーブ地点は倒れる前の朝(6 日目)まで進んでいる
        XCTAssertEqual(session.savePoint?.day, 6)
        session.recover(.loadSavePoint)
        XCTAssertTrue(session.state.isActive)
        XCTAssertEqual(session.state.day, 6)
    }

    func testAdLayoutReservesFixedHeights() {
        XCTAssertEqual(AdLayout.bannerHeight, 50)
        XCTAssertGreaterThanOrEqual(AdLayout.contentGap, 8)
        XCTAssertGreaterThanOrEqual(AdLayout.bottomButtonGap, 12)
    }

    func testStoreIsUnavailableInPhase1() async {
        let store = UnavailableStoreService()
        XCTAssertFalse(store.isAvailable)
        XCTAssertEqual(store.productIds, ["reforge.remove_ads"])
        let price = await store.displayPrice(for: ProductID.removeAds)
        XCTAssertNil(price)
    }
}
