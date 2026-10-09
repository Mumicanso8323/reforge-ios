import XCTest
import ReForgeEngine
@testable import ReForge

/// A-07 通しの台本の流し込み(DEBUG の部品)。小さな台本(ノアの歩き)を流し込む。シミュレータで回す(CI の ios ジョブ)。
@MainActor
final class ReplayDriverTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }


    /// 焚き火を置いて点けた、序の後の世界(新しい世界のままだと歩く命令が断られる。AppTests の litWorld と同じ)。
    private func litWorld(_ content: ContentDB) -> WorldState {
        var world = GameBootstrap.newWorld(content: content, seed: 5)
        world.clock.held = false
        world.narrative.scene = nil
        let origin = world.map.spawn
        var ctx = StepContext(world: world, content: content)
        EffectApplier.apply([
            .placeStructure(structure: "structure.campfire", at: .point(at: origin), built: true),
            .hearth(at: .point(at: origin), op: .ignite()),
        ], &ctx, cause: nil)
        return ctx.world
    }

    /// 歩ける範囲の中の、隣の 1 マス(除くマスを避ける)。
    private func walkableNeighbour(_ store: GameStore, of start: GridPoint, excluding: Set<GridPoint> = []) -> GridPoint? {
        let around = [GridPoint(1, 0), GridPoint(-1, 0), GridPoint(0, 1), GridPoint(0, -1)].map { start + $0 }
        return around.first { c in
            !excluding.contains(c) && store.walkable.contains { $0.y == c.y && $0.minX <= c.x && c.x <= $0.maxX }
        }
    }

    /// 歩く命令 2 つ(隣のマス・その隣)。歩ける範囲は読み込みの後に決まる。
    private func twoWalks(_ store: GameStore, from start: WorldPoint) async throws -> (Command, Command) {
        await store.load()
        let a = try XCTUnwrap(walkableNeighbour(store, of: start.point), "歩ける隣が無い walkable=\(store.walkable.count)")
        let b = try XCTUnwrap(walkableNeighbour(store, of: a, excluding: [start.point, a]), "2 歩目の隣が無い")
        return (.crew(.walk(to: WorldPoint(start.layer, a))), .crew(.walk(to: WorldPoint(start.layer, b))))
    }

    private func logText(_ store: GameStore) async -> String {
        let log = await store.host.replayLog
        return "送られた \(log.count) 本 notice=\(store.notice ?? "nil")"
    }

    func testDrivesCommandsAndWritesDoneMark() async throws {
        let dir = tempDir()
        let app = AppModel(saves: FileSaveStorage(directory: dir.appendingPathComponent("saves")))
        let content = try XCTUnwrap(app.content)
        let world = litWorld(content)
        let noah = try XCTUnwrap(world.people[.noah]?.position)
        let store = GameStore(content: content, world: world, saves: FileSaveStorage(directory: dir.appendingPathComponent("saves2")))
        let (walk1, walk2) = try await twoWalks(store, from: noah)
        let script = ReplayScript(seed: 1, seconds: 1, commands: [.init(step: 0, command: walk1), .init(step: 2, command: walk2)])
        let done = dir.appendingPathComponent("done")

        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                await store.clockStep(realSeconds: 0.25)
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        var pacing = ReplayDriver.Pacing()
        pacing.poll = .milliseconds(5)
        pacing.warmup = .milliseconds(1)
        pacing.tail = 0.05
        await ReplayDriver.run(script: script, store: store, donePath: done.path, pacing: pacing)
        ticker.cancel()

        let log = await store.host.replayLog
        let why = await logText(store)
        XCTAssertEqual(log.map(\.command), [walk1, walk2], why)
        XCTAssertEqual(log.map(\.step).map { $0 >= 2 }.last, true, "2 つ目は歩みが台本の step に届いてから送る。" + why)
        let step = await store.host.step
        XCTAssertGreaterThanOrEqual(step, 2)
        XCTAssertEqual(try String(contentsOf: done, encoding: .utf8), "ok 2\ncheckpoints 0/0\nby-section -\n", why)
    }

    func testSceneAdvancesAreSpacedByAtLeastTheGap() async throws {
        let dir = tempDir()
        let app = AppModel(saves: FileSaveStorage(directory: dir.appendingPathComponent("saves")))
        let content = try XCTUnwrap(app.content)
        let world = GameBootstrap.newWorld(content: content, seed: 1)
        let store = GameStore(content: content, world: world, saves: FileSaveStorage(directory: dir.appendingPathComponent("saves2")))
        let advance = Command.narrative(.advanceScene)
        let script = ReplayScript(seed: 1, seconds: 1, commands: [.init(step: 0, command: advance), .init(step: 0, command: advance)])
        var pacing = ReplayDriver.Pacing()
        pacing.poll = .milliseconds(5)
        pacing.warmup = .milliseconds(1)
        pacing.sceneGap = 0.3
        pacing.tail = 0
        let started = ProcessInfo.processInfo.systemUptime
        await ReplayDriver.run(script: script, store: store, donePath: nil, pacing: pacing)
        let log = await store.host.replayLog
        XCTAssertEqual(log.count, 2)
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - started, 0.3)
    }

    func testAfterDelaysTheCommandByRealTimeEvenWhenStepsDoNotAdvance() async throws {
        let dir = tempDir()
        let app = AppModel(saves: FileSaveStorage(directory: dir.appendingPathComponent("saves")))
        let content = try XCTUnwrap(app.content)
        let world = GameBootstrap.newWorld(content: content, seed: 1)
        let store = GameStore(content: content, world: world, saves: FileSaveStorage(directory: dir.appendingPathComponent("saves2")))
        let advance = Command.narrative(.advanceScene)
        // どちらも step 0(保留で歩みが進まない形)。2 つ目は前の命令から 0.4 秒あけて送る
        let script = ReplayScript(seed: 1, seconds: 1, commands: [
            .init(step: 0, command: advance), .init(step: 0, command: advance, after: 0.4),
        ])
        var pacing = ReplayDriver.Pacing()
        pacing.poll = .milliseconds(5)
        pacing.warmup = .milliseconds(1)
        pacing.sceneGap = 0
        pacing.tail = 0
        let started = ProcessInfo.processInfo.systemUptime
        await ReplayDriver.run(script: script, store: store, donePath: nil, pacing: pacing)
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - started, 0.4)
        let log = await store.host.replayLog
        XCTAssertEqual(log.count, 2)
    }

    func testSkipsACommandThatKeepsBeingRefusedAndKeepsGoing() async throws {
        let dir = tempDir()
        let app = AppModel(saves: FileSaveStorage(directory: dir.appendingPathComponent("saves")))
        let content = try XCTUnwrap(app.content)
        let world = litWorld(content)
        let noah = try XCTUnwrap(world.people[.noah]?.position)
        let store = GameStore(content: content, world: world, saves: FileSaveStorage(directory: dir.appendingPathComponent("saves2")))
        let (ok, _) = try await twoWalks(store, from: noah)
        let bad = Command.base(.build(structure: "structure.no_such_kind", at: noah, facing: .south))
        let script = ReplayScript(seed: 1, seconds: 1, commands: [
            .init(step: 0, command: ok), .init(step: 0, command: bad), .init(step: 0, command: ok),
        ])
        let done = dir.appendingPathComponent("done")
        var pacing = ReplayDriver.Pacing()
        pacing.poll = .milliseconds(5)
        pacing.warmup = .milliseconds(1)
        pacing.tail = 0
        pacing.retryWindow = 0.05
        await ReplayDriver.run(script: script, store: store, donePath: done.path, pacing: pacing)
        let log = await store.host.replayLog.map(\.command)
        let why = await logText(store)
        XCTAssertEqual(log.first, ok, why)
        XCTAssertTrue(log.contains(bad), "断られた命令は何度か再試行される。" + why)
        XCTAssertEqual(log.last, ok, "飛ばして先へ進む(止めない)。" + why)
        XCTAssertEqual(try String(contentsOf: done, encoding: .utf8), "skipped 1/3 first 2\ncheckpoints 0/0\nby-section 0:1\n", why)
    }

    func testCheckpointRestoresTheScriptedWorldBeforeItsCommand() async throws {
        let dir = tempDir()
        let app = AppModel(saves: FileSaveStorage(directory: dir.appendingPathComponent("saves")))
        let content = try XCTUnwrap(app.content)
        let world = litWorld(content)
        var moved = world
        let start = try XCTUnwrap(world.people[.noah]?.position)
        let there = WorldPoint(start.layer, GridPoint(start.point.x + 3, start.point.y))
        moved.people[.noah]?.position = there
        let save = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: moved, content: []))
        let store = GameStore(content: content, world: world, saves: FileSaveStorage(directory: dir.appendingPathComponent("saves2")))
        // 合わせ直しの点だけ(命令は 1 つ。歩きでなく場面の送り=世界を動かさない)
        let script = ReplayScript(seed: 1, seconds: 1, commands: [.init(step: 0, command: .narrative(.advanceScene))],
                                  checkpoints: [.init(index: 0, save: save)])
        var pacing = ReplayDriver.Pacing()
        pacing.poll = .milliseconds(5)
        pacing.warmup = .milliseconds(1)
        pacing.tail = 0
        pacing.retryWindow = 0
        await ReplayDriver.run(script: script, store: store, donePath: nil, pacing: pacing)
        let position = await store.host.world.people[.noah]?.position
        XCTAssertEqual(position, there, "命令の前に、台本の世界へ合わせ直す")
    }

    func testEmptyScriptEndsWithOkZero() async throws {
        let dir = tempDir()
        let app = AppModel(saves: FileSaveStorage(directory: dir.appendingPathComponent("saves")))
        let content = try XCTUnwrap(app.content)
        let store = GameStore(content: content, world: litWorld(content),
                              saves: FileSaveStorage(directory: dir.appendingPathComponent("saves2")))
        let done = dir.appendingPathComponent("done")
        var pacing = ReplayDriver.Pacing()
        pacing.poll = .milliseconds(5)
        pacing.warmup = .milliseconds(1)
        pacing.tail = 0
        await ReplayDriver.run(script: ReplayScript(seed: 1, seconds: 0, commands: []), store: store,
                               donePath: done.path, pacing: pacing)
        XCTAssertEqual(try String(contentsOf: done, encoding: .utf8), "ok 0\ncheckpoints 0/0\nby-section -\n")
        let log = await store.host.replayLog
        XCTAssertTrue(log.isEmpty)
    }

    func testMissingOrBrokenScriptDoesNothing() throws {
        XCTAssertNil(ReplayMode.load(path: nil))
        XCTAssertNil(ReplayMode.load(path: tempDir().appendingPathComponent("none.json").path))
        let broken = tempDir().appendingPathComponent("broken.json")
        try Data("{ not a script".utf8).write(to: broken)
        XCTAssertNil(ReplayMode.load(path: broken.path))
    }
}
