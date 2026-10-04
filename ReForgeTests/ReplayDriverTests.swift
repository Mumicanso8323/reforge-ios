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

    func testDrivesCommandsAndWritesDoneMark() async throws {
        let dir = tempDir()
        let app = AppModel(saves: FileSaveStorage(directory: dir.appendingPathComponent("saves")))
        let content = try XCTUnwrap(app.content)
        var world = GameBootstrap.newWorld(content: content, seed: 1)
        world.clock.held = false
        let noah = try XCTUnwrap(world.people[.noah]?.position)
        let walk1 = Command.crew(.walk(to: WorldPoint(noah.layer, GridPoint(noah.point.x + 1, noah.point.y))))
        let walk2 = Command.crew(.walk(to: WorldPoint(noah.layer, GridPoint(noah.point.x + 2, noah.point.y))))
        let script = ReplayScript(seed: 1, seconds: 1, commands: [.init(step: 0, command: walk1), .init(step: 2, command: walk2)])
        let store = GameStore(content: content, world: world, saves: FileSaveStorage(directory: dir.appendingPathComponent("saves2")))
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
        XCTAssertEqual(log.map(\.command), [walk1, walk2])
        XCTAssertGreaterThanOrEqual(log[1].step, 2, "歩みが台本の step に届いてから送る")
        let step = await store.host.step
        XCTAssertGreaterThanOrEqual(step, 2)
        XCTAssertEqual(try String(contentsOf: done, encoding: .utf8), "done\n")
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

    func testMissingOrBrokenScriptDoesNothing() throws {
        XCTAssertNil(ReplayMode.load(path: nil))
        XCTAssertNil(ReplayMode.load(path: tempDir().appendingPathComponent("none.json").path))
        let broken = tempDir().appendingPathComponent("broken.json")
        try Data("{ not a script".utf8).write(to: broken)
        XCTAssertNil(ReplayMode.load(path: broken.path))
    }
}
