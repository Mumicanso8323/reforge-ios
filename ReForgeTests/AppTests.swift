import UIKit
import XCTest
import ReForgeEngine
@testable import ReForge

/// アプリ側(同梱のコンテンツとフォント・保存・GameStore)の単体テスト。シミュレータで回す(CI の ios ジョブ)。
/// 射影(区画・視界・視点・補間)のロジックは ReForgeCore の RFPresentTests が Linux で確かめる。
@MainActor
final class AppTests: XCTestCase {
    private final class PerformanceClock {
        private let origin = ContinuousClock().now
        private var offsets: [Duration]

        init(milliseconds: [Int]) { offsets = milliseconds.map(Duration.milliseconds) }

        func now() -> ContinuousClock.Instant { origin.advanced(by: offsets.removeFirst()) }
    }

    @MainActor private final class BackgroundTasks: BackgroundTaskManaging {
        private(set) var events: [String] = []
        private(set) var handlers: [() -> Void] = []
        func begin(name: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
            events.append("begin")
            handlers.append(expirationHandler)
            return UIBackgroundTaskIdentifier(rawValue: 1)
        }
        func end(_ identifier: UIBackgroundTaskIdentifier) { events.append("end") }
    }
    private func tempSaves() -> FileSaveStorage {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return FileSaveStorage(directory: dir)
    }

    private func content() throws -> ContentDB { try AppModel.loadBundledContent(bundle: .main) }

    /// 公開の束だけで、保留中の最初の押し続ける行為を作る。地図を見る試験はこれを終えてから確かめる。
    private func heldStartContent() throws -> (content: ContentDB, world: WorldState) {
        // 公開の層だけで作る。非公開の層を重ねると、ノアの始まりのマスに残骸があって焚き火を置けず、火が点かない。
        let dir = try XCTUnwrap(Bundle.main.url(forResource: "content", withExtension: nil))
        var db = try ContentLoader.load(layers: [dir.appendingPathComponent("public", isDirectory: true)])
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

    func testDarkMarkBrightnessStaysVisibleOutsideVisionAndRespectsReduceMotion() {
        let outside = PlacementBrightness.value(seenInDark: true, visible: false, night: true,
                                                 reduceMotion: true, elapsed: 1.5)
        XCTAssertEqual(outside, TilePalette.nightVisible)
        let still = PlacementBrightness.value(seenInDark: true, visible: true, night: true,
                                              reduceMotion: true, elapsed: 0.75)
        XCTAssertEqual(still, TilePalette.nightVisible)
        let dim = PlacementBrightness.value(seenInDark: true, visible: false, night: true,
                                            reduceMotion: false, elapsed: 0.75)
        XCTAssertEqual(dim, TilePalette.nightVisible * 1.15, accuracy: 0.000_001)
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

    func testSaveWriterKeepsWriteOrder() async throws {
        let saves = tempSaves()
        let writer = SaveWriter(storage: saves)
        try await writer.write(Data("one".utf8), slot: .resume)
        try await writer.write(Data("two".utf8), slot: .resume)
        try await writer.write(Data("three".utf8), slot: .resume)
        XCTAssertEqual(try saves.read(slot: .resume), Data("three".utf8))
    }

    func testBackgroundSaveEndsAfterWriterCompletes() async throws {
        let tasks = BackgroundTasks()
        let app = AppModel(saves: tempSaves(), backgroundTasks: tasks)
        let content = try XCTUnwrap(app.content)
        let store = GameStore(content: content, world: GameBootstrap.newWorld(content: content, seed: 5), saves: tempSaves())
        app.saveInBackground(store)
        XCTAssertEqual(tasks.events, ["begin"])
        for _ in 0..<50 where tasks.events.count < 2 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(tasks.events, ["begin", "end"])
    }

    /// 時間切れの通知が先に来たら、その場で終える(後から保存が終わっても 2 度は終えない)。
    func testBackgroundSaveEndsWhenExpired() async throws {
        let tasks = BackgroundTasks()
        let app = AppModel(saves: tempSaves(), backgroundTasks: tasks)
        let content = try XCTUnwrap(app.content)
        let store = GameStore(content: content, world: GameBootstrap.newWorld(content: content, seed: 5), saves: tempSaves())
        app.saveInBackground(store)
        tasks.handlers.first?()
        XCTAssertEqual(tasks.events, ["begin", "end"])
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(tasks.events, ["begin", "end"], "2 度終えない")
    }

    func testClockStepRecordsOnlySlowSteps() async throws {
        let content = try content()
        var world = GameBootstrap.newWorld(content: content, seed: 5)
        world.clock.held = false
        let slowClock = PerformanceClock(milliseconds: [0, 60])
        let slow = GameStore(content: content, world: world, saves: tempSaves(), performanceNow: slowClock.now)
        await slow.load()
        await slow.clockStep(realSeconds: 0.25)
        XCTAssertEqual(slow.slowSteps.count, 1)
        XCTAssertEqual(slow.slowSteps.first?.milliseconds, 60)

        let fastClock = PerformanceClock(milliseconds: [0, 40])
        let fast = GameStore(content: content, world: world, saves: tempSaves(), performanceNow: fastClock.now)
        await fast.load()
        await fast.clockStep(realSeconds: 0.25)
        XCTAssertTrue(fast.slowSteps.isEmpty)
    }

    func testTerrainCacheDoesNotRenderAnUnchangedChunkAgain() async throws {
        let start = try heldStartContent()
        let store = GameStore(content: start.content, world: start.world, saves: tempSaves())
        await store.load()
        let chunk = try XCTUnwrap(store.chunks.values.first)
        let cache = MapTerrainCache()
        _ = cache.image(for: chunk, cellSize: 24, night: store.clock.isNight, vision: store.mapView.vision, terrains: start.content.terrains)
        _ = cache.image(for: chunk, cellSize: 24, night: store.clock.isNight, vision: store.mapView.vision, terrains: start.content.terrains)
        XCTAssertEqual(cache.renderCount[chunk.index], 1)
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

    func testMapZoomPlansAndNewCameraStartAtFortyFourPoints() {
        for plan in MapZoomPlan.allCases {
            XCTAssertGreaterThanOrEqual(plan.levels[plan.defaultZoom], 44, "\(plan)")
        }
        XCTAssertGreaterThanOrEqual(MapCamera().cellSize, 44)
    }

    /// 歩ける範囲の中で、ノアの隣の 1 マス(ノアのマスではない)。無ければ nil。
    private func walkableNeighbour(_ store: GameStore, of start: GridPoint) -> GridPoint? {
        let around = [GridPoint(1, 0), GridPoint(-1, 0), GridPoint(0, 1), GridPoint(0, -1)].map { start + $0 }
        return around.first { c in store.walkable.contains { $0.y == c.y && $0.minX <= c.x && c.x <= $0.maxX } }
    }

    private func walkDiagnostic(_ store: GameStore, target: GridPoint?) async -> String {
        let noah = await store.host.world.people[.noah]
        return "target=\(String(describing: target)) noah=\(String(describing: noah?.position?.point)) motion=\(noah?.motion != nil) "
            + "route=\(store.route.count) walkable=\(store.walkable.count) canSteer=\(store.canSteer) "
            + "darkStart=\(store.darkStart != nil) notice=\(store.notice ?? "nil")"
    }

    /// 焚き火を置いて点けた世界(火が点くまでは歩ける範囲が空なので、歩く確かめはこの世界で行う)。
    private func litWorld(_ content: ContentDB) -> WorldState {
        var world = GameBootstrap.newWorld(content: content, seed: 5)
        world.clock.held = false
        // 新しい世界は序の場面から始まる(その間は地図も操作棒も出ない)。読み終えた後の世界にする
        world.narrative.scene = nil
        let origin = world.map.spawn
        var ctx = StepContext(world: world, content: content)
        EffectApplier.apply([
            .placeStructure(structure: "structure.campfire", at: .point(at: origin), built: true),
            .hearth(at: .point(at: origin), op: .ignite()),
        ], &ctx, cause: nil)
        return ctx.world
    }

    func testSelectingTwiceStartsWalkingWithoutSavingSelection() async throws {
        let content = try content()
        let world = litWorld(content)
        let start = try XCTUnwrap(world.people[.noah]?.position)
        let store = GameStore(content: content, world: world, saves: tempSaves())
        await store.load()
        let before = await walkDiagnostic(store, target: nil)
        let target = try XCTUnwrap(walkableNeighbour(store, of: start.point), before)

        store.select(target)
        XCTAssertEqual(store.selected, target)
        XCTAssertTrue(store.route.isEmpty)
        XCTAssertNil(store.notice, "1 度目の選びでは歩く命令を送らない")
        let afterFirstSelection = await store.host.world.people[.noah]?.position
        XCTAssertEqual(afterFirstSelection, start)

        store.select(target)
        // 歩いた(動き・経路・着いた)だけを合格にする。断りの 1 行は合格にしない
        var walked = false
        for _ in 0..<100 {
            let noah = await store.host.world.people[.noah]
            if noah?.motion != nil || noah?.position?.point == target || !store.route.isEmpty { walked = true; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let diagnostic = await walkDiagnostic(store, target: target)
        XCTAssertTrue(walked, "同じマスの 2 度目の選びで歩き出す: " + diagnostic)

        let recreated = GameStore(content: content, world: world, saves: tempSaves())
        await recreated.load()
        XCTAssertNil(recreated.selected)
    }

    /// 歩ける範囲の外を 2 度選んでも歩かず、断りの 1 行が出る(範囲の外のマスは行為も歩きも出さない)。
    func testSelectingOutsideWalkableTwiceRefusesWithoutMoving() async throws {
        let content = try content()
        let world = litWorld(content)
        let start = try XCTUnwrap(world.people[.noah]?.position)
        let store = GameStore(content: content, world: world, saves: tempSaves())
        await store.load()
        let far = start.point + GridPoint(40, 0)
        store.select(far)
        store.select(far)
        for _ in 0..<100 where store.notice == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let noah = await store.host.world.people[.noah]
        let diagnostic = await walkDiagnostic(store, target: far)
        XCTAssertNotNil(store.notice, diagnostic)
        XCTAssertEqual(noah?.position, start)
        XCTAssertNil(noah?.motion)
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
    /// 読めない保存では「つづきから」を出さない(壊れ・未来の版)。ファイルは消さず、「はじめから」で新しい保存に置き換わる。
    func testResumeHiddenWhenUnreadable() async throws {
        let saves = tempSaves()
        // (a) 壊れたバイト列
        let junk = Data("not json".utf8)
        try saves.write(junk, slot: .resume)
        let a = AppModel(saves: saves)
        XCTAssertFalse(a.hasResume)
        XCTAssertEqual(try saves.read(slot: .resume), junk, "読めない保存を消さない")
        // (b) 未知の版
        let future = Data(#"{"format":"reforge.save","schemaVersion":999}"#.utf8)
        try saves.write(future, slot: .resume)
        XCTAssertFalse(AppModel(saves: saves).hasResume)
        XCTAssertEqual(try saves.read(slot: .resume), future)
        // (d) 読めない保存のまま「はじめから」
        let app = AppModel(saves: saves)
        app.startNewGame()
        let store = try XCTUnwrap(app.game)
        await store.saveResume()
        XCTAssertTrue(app.hasResume)
        XCTAssertTrue(AppModel.resumeIsReadable(saves))
        // (c) 正しい保存
        XCTAssertTrue(AppModel(saves: saves).hasResume)
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

    /// L-10a: 角の窓は、ボタン(44×44pt)の外の押下を下の窓へ通す(角の 4pt の余白も通す)。
    func testSettingsCornerWindowPassesTouchesOutsideButton() {
        let w = SettingsCornerWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let b = w.buttonFrame
        XCTAssertEqual(b.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(b.maxX, 393 - SettingsCorner.margin, accuracy: 0.5)
        XCTAssertNil(w.hitTest(CGPoint(x: 393 - 1, y: b.midY), with: nil), "右の余白は下へ通す")
        XCTAssertNil(w.hitTest(CGPoint(x: b.midX, y: b.maxY + 2), with: nil), "下の余白は下へ通す")
        XCTAssertNil(w.hitTest(CGPoint(x: 100, y: 400), with: nil), "画面の中ほどは下へ通す")
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
