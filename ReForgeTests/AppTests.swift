import UIKit
import XCTest
import ReForgeEngine
@testable import ReForge

/// アプリ側(同梱のコンテンツとフォント・保存・GameStore)の単体テスト。シミュレータで回す(CI の ios ジョブ)。
/// 射影(区画・視界・視点・補間)のロジックは ReForgeCore の RFPresentTests が Linux で確かめる。
@MainActor
final class AppTests: XCTestCase {
    private func tempSaves() -> FileSaveStorage {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return FileSaveStorage(directory: dir)
    }

    private func content() throws -> ContentDB { try AppModel.loadBundledContent(bundle: .main) }

    /// 非公開の層は序の場面(W-16)から始まる。地図や命令を確かめるテストは、序を読み終えてから見る。
    /// 公開の層には序が無いので、そのまま抜ける。
    private func readThroughPrologue(_ store: GameStore) async throws {
        for _ in 0..<200 where store.prologue != nil {
            store.send(.narrative(.advanceScene))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(store.prologue, "序を読み終えた")
    }

    func testBundledContentLoads() throws {
        let c = try content()
        XCTAssertFalse(c.terrains.isEmpty, "content/ がアプリの束に入っている")
        XCTAssertTrue(c.layers.contains { $0.id == "public" })
    }

    func testBundledFontRegisters() {
        XCTAssertTrue(FontBook.register())
        XCTAssertNotNil(UIFont(name: FontBook.mapFont, size: 14), "BIZ UDGothic が使える")
    }

    func testSaveStorageRoundTripAndList() throws {
        let s = tempSaves()
        XCTAssertNil(try s.read(slot: .resume))
        try s.write(Data("a".utf8), slot: .resume)
        try s.write(Data("b".utf8), slot: .dawn(day: 3))
        try s.write(Data("c".utf8), slot: .manual(index: 1))
        XCTAssertEqual(try s.read(slot: .dawn(day: 3)), Data("b".utf8))
        XCTAssertEqual(Set(try s.list()), [.resume, .dawn(day: 3), .manual(index: 1)])
        try s.deleteAll()
        XCTAssertEqual(try s.list(), [])
    }

    func testNewGameLoadsMapChunksAndFootCard() async throws {
        let c = try content()
        let store = GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 3), saves: tempSaves())
        await store.load()
        try await readThroughPrologue(store)
        XCTAssertEqual(store.chunks.count, store.mapView.chunkColumns * store.mapView.chunkRows, "全区画を引いた")
        XCTAssertNotNil(store.focus, "ノアの位置に追従する")
        XCTAssertNotNil(store.footCard, "足元カードはノアの足元")
        XCTAssertTrue(store.actors.contains { $0.isNoah })
        XCTAssertTrue(store.clock.running)
    }

    /// 断られた操作は足元カードに 1 行(ダイアログは出さない)。
    func testRejectedCommandShowsNotice() async throws {
        let c = try content()
        let store = GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 3), saves: tempSaves())
        await store.load()
        try await readThroughPrologue(store)
        store.choose(.sleep)
        for _ in 0..<100 where store.notice == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.notice, "まだ昼だ")
    }

    /// 背面に回ると「つづきから」が書かれ、読み直すと同じ世界から続く。
    func testResumeRoundTrip() async throws {
        let saves = tempSaves()
        let app = AppModel(saves: saves)
        XCTAssertFalse(app.hasResume)
        app.startNewGame()
        let store = try XCTUnwrap(app.game)
        await store.saveResume()
        let saved = await store.host.world
        await app.backToTitle()
        XCTAssertNil(app.game)
        XCTAssertTrue(app.hasResume)
        do {
            let data = try XCTUnwrap(try saves.read(slot: .resume))
            _ = try SaveCodec.decode(data)
        } catch {
            XCTFail("つづきからが読めない: \(error)")
        }
        app.continueGame()
        let resumed = try XCTUnwrap(app.game)
        let world = await resumed.host.world
        XCTAssertEqual(world, saved)
        app.deleteSave()
        XCTAssertFalse(app.hasResume)
    }
    /// L-10a: 設定が開いている間は GameStore の時計が進まない。閉じたら、止めていた間の実時間を進めず、再開した点から進む。
    func testClockStopsWhileSettingsOpen() async throws {
        let c = try content()
        var world = GameBootstrap.newWorld(content: c, seed: 3)
        world.clock.held = false
        let store = GameStore(content: c, world: world, saves: tempSaves())
        await store.load()
        // 実時間を待たず、時計の 1 回ぶん(clockStep)を直に呼ぶ(CI で揺れない)
        func step(_ n: Int) async { for _ in 0..<n { await store.clockStep(realSeconds: 0.25) } }
        func now() async -> GameTime { await store.host.world.clock.now }
        await step(2)
        let beforeOpen = await now()
        XCTAssertGreaterThan(beforeOpen, GameTime.zero, "開く前は時計が進んでいる")

        store.isPaused = true
        let atOpen = await now()
        await step(4)
        let whileOpen = await now()
        XCTAssertEqual(whileOpen, atOpen, "設定が開いている間は時計が進まない")

        store.isPaused = false
        await step(2)
        let afterClose = await now()
        XCTAssertGreaterThan(afterClose, whileOpen, "閉じたら再開する")
    }

    /// L-10a: 開閉は AppModel.settingsOpen が持ち、ゲームの時計の止め方に渡す。ゲームの入れ替わりで開いたままにしない。
    func testSettingsOpenPausesGameAndResetsOnGameChange() throws {
        let app = AppModel(saves: tempSaves())
        app.settingsOpen = true
        app.startNewGame()
        XCTAssertFalse(app.settingsOpen, "新しいゲームでは閉じて始まる")
        let game = try XCTUnwrap(app.game)
        XCTAssertFalse(game.isPaused)
        app.settingsOpen = true
        XCTAssertTrue(game.isPaused, "開いている間は時計を止める")
        app.settingsOpen = false
        XCTAssertFalse(game.isPaused)
        app.settingsOpen = true
        app.deleteSave()
        XCTAssertFalse(app.settingsOpen, "記録を消したら閉じる")
    }
}
