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

    /// 公開の束だけで、保留中の最初の押し続ける行為を作る。地図を見る試験はこれを終えてから確かめる。
    private func heldStartContent() throws -> (content: ContentDB, world: WorldState) {
        var db = try content()
        let probe = GameBootstrap.newWorld(content: db, seed: 3)
        let position = try XCTUnwrap(probe.people[.noah]?.position)
        let terrain = try XCTUnwrap(probe.map[position.layer]?.terrain(at: position.point))
        let tag = try XCTUnwrap(db.terrains[terrain]?.tags.first)
        db.interactions.removeAll()
        try ContentLoader.apply(json: Data(#"""
        {
          "interactions": [
            { "id": "interaction.test.start", "target": { "terrain": { "tag": "\#(tag)" } }, "seconds": 5,
              "hold": true, "yields": [] }
          ]
        }
        """#.utf8), to: &db)
        var first = try XCTUnwrap(db.interactions["interaction.test.start"])
        first.effects = [.placeStructure(structure: "structure.campfire", at: .trigger, built: true),
                         .hearth(at: .trigger, op: .ignite())]
        db.interactions[first.id] = first
        db.structures["structure.campfire"]?.hearth?.initialSeconds = 0
        db.structures["structure.campfire"]?.hearth?.igniteSeconds = 3600
        // 始まりの時刻も試験の側で決める(非公開の層の始まりの時刻に引きずられて昼でなくなるのを避ける)
        db.start.clock = StartClockDef(day: 0, hoursBeforeDusk: 4, held: true, firstAct: first.id)
        let world = GameBootstrap.newWorld(content: db, seed: 3)
        XCTAssertTrue(world.clock.held)
        return (db, world)
    }

    /// 非公開の層は序の場面(W-16)から始まる。地図や命令を確かめるテストは、序を読み終えてから見る。
    /// 公開の層には序が無いので、そのまま抜ける。
    private func readThroughPrologue(_ store: GameStore) async throws {
        for _ in 0..<200 where store.prologue != nil {
            store.send(.narrative(.advanceScene))
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(store.prologue, "序を読み終えた")
    }

    /// 診断用: 世界の今の様子を 1 行にする(CI で落ちた時に原因を読むため)。
    private func darkStartDiagnosis(_ store: GameStore, _ label: String, rejection: String? = nil, steps: Int? = nil) async -> String {
        let w = await store.host.world
        let noah = w.people[.noah]
        let active = w.exploration.active[.noah]
        return "[\(label)] rejection=\(String(describing: rejection)) notice=\(String(describing: store.notice)) "
            + "darkStart=\(String(describing: store.darkStart)) running=\(store.clock.running) held=\(w.clock.held) "
            + "phase=\(w.clock.phase) now=\(w.clock.now.seconds) active=\(String(describing: active)) "
            + "pos=\(String(describing: noah?.position)) motion=\(String(describing: noah?.motion)) "
            + "alive=\(String(describing: noah?.presence.isAlive)) prologue=\(store.prologue != nil) steps=\(String(describing: steps)) "
            + "hearths=\(w.placements.items.values.compactMap { $0.structure?.hearth })" + " footCard=\(String(describing: store.footCard?.actions))"
    }

    private func startDarkStartAction(_ store: GameStore) async throws {
        let action = try XCTUnwrap(store.darkStart?.action, "最初の行為の前は暗い場面を出す")
        let before = await darkStartDiagnosis(store, "押す前")
        let rejection = await store.perform(action.start)
        var log = [before, await darkStartDiagnosis(store, "押した直後", rejection: rejection)]
        var totalSteps = 0
        for i in 0..<100 where store.darkStart != nil {
            try await Task.sleep(nanoseconds: 20_000_000)
            let (frame, report) = await store.host.tick(realSeconds: 0.25)
            totalSteps += report.steps
            await store.refresh(frame)
            if i < 3 { log.append(await darkStartDiagnosis(store, "tick \(i)", steps: report.steps)) }
        }
        log.append(await darkStartDiagnosis(store, "最後", steps: totalSteps))
        XCTAssertNil(store.darkStart, "最初の行為で火が点いた後は通常画面になる ## " + log.joined(separator: " ## "))
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
        let start = try heldStartContent()
        let store = GameStore(content: start.content, world: start.world, saves: tempSaves())
        await store.load()
        try await readThroughPrologue(store)
        try await startDarkStartAction(store)
        XCTAssertEqual(store.chunks.count, store.mapView.chunkColumns * store.mapView.chunkRows, "全区画を引いた")
        XCTAssertNotNil(store.focus, "ノアの位置に追従する")
        XCTAssertNotNil(store.footCard, "足元カードはノアの足元")
        XCTAssertTrue(store.actors.contains { $0.isNoah })
        XCTAssertTrue(store.clock.running)
    }

    /// 断られた操作は足元カードに 1 行(ダイアログは出さない)。
    func testRejectedCommandShowsNotice() async throws {
        let start = try heldStartContent()
        let store = GameStore(content: start.content, world: start.world, saves: tempSaves())
        await store.load()
        try await readThroughPrologue(store)
        try await startDarkStartAction(store)
        store.choose(.sleep)
        for _ in 0..<100 where store.notice == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(store.notice, "まだ昼だ")
    }

    func testHeldStartUsesAndClearsDarkStartAction() async throws {
        let start = try heldStartContent()
        let store = GameStore(content: start.content, world: start.world, saves: tempSaves())
        await store.load()
        try await readThroughPrologue(store)
        try await startDarkStartAction(store)
        XCTAssertTrue(store.clock.running)
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
}
