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

    func testDuskShowsNightfallAndSleepShowsDawn() {
        let s = newSession()
        s.advanceClock(by: 180)
        XCTAssertEqual(s.state.phase, .dusk)
        XCTAssertEqual(s.sheet, .nightfall)
        s.sleep()
        XCTAssertEqual(s.state.day, 2)
        XCTAssertEqual(s.sheet, .dawn)
        XCTAssertFalse(s.clockRunning, "結果シートの間は時計を止める")
        XCTAssertEqual(store.loadSavePoint()?.day, 2, "毎朝の自動セーブ")
        s.beginMorning()
        XCTAssertNil(s.sheet)
        XCTAssertTrue(s.clockRunning)
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
            s.sleep()
            s.beginMorning()
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
            session.sleep()
            session.beginMorning()
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
