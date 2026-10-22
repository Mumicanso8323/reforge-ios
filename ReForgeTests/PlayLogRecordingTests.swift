import XCTest
@testable import ReForge
import RFContent
import RFWorld

/// PT-B4: 操作の記録(命令・無操作・節目・書き出し・消去・入切)。端末の中だけ。
@MainActor
final class PlayLogRecordingTests: XCTestCase {
    private var clockNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeStore(content override: ContentDB? = nil, dir: URL) async throws -> (GameStore, PlayLog) {
        let c = try override ?? AppModel.loadBundledContent(bundle: .main)
        let name = "reforge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 3),
                              saves: FileSaveStorage(directory: tempDir()), defaults: defaults, now: { [unowned self] in self.clockNow })
        let log = try XCTUnwrap(PlayLog(directory: dir.appendingPathComponent("playlog"), defaults: defaults))
        store.playLog = log
        await store.load()
        return (store, log)
    }

    private func events(_ log: PlayLog) throws -> [[String: Any]] {
        log.flush()
        let text = try String(contentsOf: log.export(), encoding: .utf8)
        return try text.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    private func kinds(_ log: PlayLog, _ kind: String) throws -> [[String: String]] {
        try events(log).filter { $0["kind"] as? String == kind }.map { $0["fields"] as? [String: String] ?? [:] }
    }

    /// TEST-B4-1
    func testTwentyCommandsGiveTwentyCommandEventsWithResults() async throws {
        let (store, log) = try await makeStore(dir: tempDir())
        var rejected = 0
        for i in 0..<20 {
            let reason = await store.perform(.crew(.steer(direction: i.isMultiple(of: 2) ? .north : nil)))
            if reason != nil { rejected += 1 }
        }
        let commands = try kinds(log, "command")
        XCTAssertEqual(commands.count, 20)
        XCTAssertEqual(commands.filter { $0["result"] == "rejected" }.count, rejected)
        XCTAssertTrue(commands.filter { $0["result"] == "rejected" }.allSatisfy { $0["reason"] != nil })
    }

    /// TEST-B4-2
    func testIdleAfterTenSecondsButNotNine() async throws {
        let (store, log) = try await makeStore(dir: tempDir())
        await store.perform(.crew(.steer(direction: nil)))
        clockNow.addTimeInterval(9)
        await store.perform(.crew(.steer(direction: nil)))
        XCTAssertEqual(try kinds(log, "idle").count, 0)
        clockNow.addTimeInterval(10)
        await store.perform(.crew(.steer(direction: nil)))
        let idle = try kinds(log, "idle")
        XCTAssertEqual(idle.count, 1)
        XCTAssertEqual(idle.first?["seconds"], "10")
    }

    /// TEST-B4-3b(節目)
    func testMarkIsLoggedOnceWhenItHolds() async throws {
        var c = try AppModel.loadBundledContent(bundle: .main)
        c.playtestMarks = ["mark.test.start": PlaytestMarkDef(id: "mark.test.start", when: .always)]
        let (store, log) = try await makeStore(content: c, dir: tempDir())
        await store.perform(.crew(.steer(direction: nil)))
        await store.perform(.crew(.steer(direction: nil)))
        XCTAssertEqual(try kinds(log, "mark"), [["mark": "mark.test.start"]])
    }

    /// TEST-B4-4(2 MB を超えたら古い日から消す。上限は差し替えて小さくして確かめる)
    func testOldestFileIsPrunedWhenOverTheCap() throws {
        let dir = tempDir().appendingPathComponent("playlog")
        let log = try XCTUnwrap(PlayLog(directory: dir, defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), maxBytes: 600))
        for day in 1...3 {
            let t = Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400)
            for _ in 0..<4 {
                log.append(PlayLogEvent(t: t, kind: "x", day: day, minute: 0, fields: ["k": String(repeating: "a", count: 60)]))
            }
            log.flush()
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertLessThan(files.count, 3)
        XCTAssertTrue(files.last?.hasSuffix(".jsonl") == true)
    }

    func testRecordingOffWritesNothingAndClearRemovesEverything() async throws {
        let (store, log) = try await makeStore(dir: tempDir())
        await store.perform(.crew(.steer(direction: nil)))
        XCTAssertFalse(try events(log).isEmpty)
        log.clear()
        XCTAssertTrue(try events(log).isEmpty)
        UserDefaults.standard.set(false, forKey: PlayLog.recordingKey)
        defer { UserDefaults.standard.removeObject(forKey: PlayLog.recordingKey) }
        let off = try XCTUnwrap(PlayLog(directory: tempDir().appendingPathComponent("playlog")))
        XCTAssertFalse(off.isRecording)
        off.append(PlayLogEvent(t: clockNow, kind: "x", day: 1, minute: 0, fields: [:]))
        off.flush()
        XCTAssertEqual(try String(contentsOf: off.export(), encoding: .utf8), "")
    }
}
