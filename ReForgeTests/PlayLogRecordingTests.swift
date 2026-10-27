import XCTest
import ReForgeEngine
@testable import ReForge

/// PT-B4: 操作の記録(命令・無操作・節目・書き出し・消去・入切)。端末の中だけ。
@MainActor
final class PlayLogRecordingTests: XCTestCase {
    private var clockNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeStore(content override: ContentDB? = nil, dir: URL, seed: UInt64 = 3) async throws -> (GameStore, PlayLog) {
        let c = try override ?? AppModel.loadBundledContent(bundle: .main)
        let name = "reforge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: seed),
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
        // 命令の後と夜明けに呼ばれる見回りを直に 2 回(始まりは序や暗い場面で命令が断られることがあるので、命令には頼らない)
        await store.recordMarks()
        await store.recordMarks()
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

    /// TEST-B4-3b(offer): 決断の帯が出たときに offer が 1 件。同じ帯の間は増えない
    func testOfferIsLoggedOnceWhenADecisionAppears() async throws {
        let (store, log) = try await makeStore(dir: tempDir())
        // 日は読み込んだ世界の今日から(読み込みの Frame が覚えた日と違うと、そこで day が 1 件増える)
        let today = store.clock.day
        store.recordFrame(decision: nil, offers: [], day: today)
        store.recordFrame(decision: "decision-7", offers: [], day: today)
        store.recordFrame(decision: "decision-7", offers: [], day: today)
        XCTAssertEqual(try kinds(log, "offer"), [["decision": "decision-7"]])
        store.recordFrame(decision: nil, offers: ["tendFire:p"], day: today + 1)
        XCTAssertEqual(try kinds(log, "offer").count, 2)
        XCTAssertEqual(try kinds(log, "day").count, 1)
    }

    /// 起動し直しても、初めての節目が 2 度出ない(playlog/marks-<seed>.json)
    func testMarkIsNotRepeatedAfterRestart() async throws {
        var c = try AppModel.loadBundledContent(bundle: .main)
        c.playtestMarks = ["mark.test.start": PlaytestMarkDef(id: "mark.test.start", when: .always)]
        let dir = tempDir()
        let (first, log) = try await makeStore(content: c, dir: dir)
        await first.recordMarks()
        let (second, _) = try await makeStore(content: c, dir: dir)
        await second.recordMarks()
        XCTAssertEqual(try kinds(log, "mark").count, 1)
    }

    /// TEST-B4-7: latency は 1 分に 6 件まで、hitch は 1 分に 1 件、100ms を超える間だけ数える
    func testLatencyIsThrottledAndHitchCountedPerMinute() {
        var m = PlayMetrics()
        var t = 1000.0
        var latencyFirstMinute = 0
        var latencyTotal = 0
        var hitches: [PlayMetrics.Emitted] = []
        m.touch(at: t)
        for i in 0..<4000 {  // 60fps。10 コマごとに触れる。1500 コマ目で 0.25 秒の引っかかり
            t += 1.0 / 60
            if i == 1500 { t += 0.25 }
            let out = m.frame(at: t)
            let n = out.filter { $0.kind == "latency" }.count
            latencyTotal += n
            if t - 1000 < 59 { latencyFirstMinute += n }
            hitches += out.filter { $0.kind == "hitch" }
            if i % 10 == 0 { m.touch(at: t) }
        }
        XCTAssertEqual(latencyFirstMinute, PlayMetrics.latencyPerMinute)
        XCTAssertEqual(latencyTotal, PlayMetrics.latencyPerMinute * 2)
        XCTAssertEqual(hitches.count, 1)
        XCTAssertEqual(hitches.first?.fields["count"], "1")
        XCTAssertEqual(hitches.first?.fields["longestMs"], "267")
    }

    func testSuspendDoesNotCountTheGapAsAHitch() {
        var m = PlayMetrics()
        _ = m.frame(at: 1)
        m.suspend()
        _ = m.frame(at: 50)
        var all: [PlayMetrics.Emitted] = []
        for i in 1...3700 { all += m.frame(at: 50 + Double(i) / 60) }
        XCTAssertEqual(all.filter { $0.kind == "hitch" }.first?.fields["count"], "0")
    }

    /// TEST-B4-7(入切): 記録が切れている間は、描画の合図も書き込みも動かない(描画の時間に影響しない)
    func testNothingRunsWhileRecordingIsOff() async throws {
        let dir = tempDir()
        let (store, log) = try await makeStore(dir: dir)
        UserDefaults.standard.set(false, forKey: PlayLog.recordingKey)
        defer { UserDefaults.standard.removeObject(forKey: PlayLog.recordingKey) }
        let off = try XCTUnwrap(PlayLog(directory: dir.appendingPathComponent("off")))
        store.playLog = off
        store.startFrameMeter()
        XCTAssertFalse(store.playRecorder.ticker.isRunning)
        store.playRecorder.ticker.onFrame?(1)
        store.playRecorder.ticker.onFrame?(5)
        await store.perform(.crew(.steer(direction: nil)))
        XCTAssertTrue(try events(off).isEmpty)
        XCTAssertTrue(try events(log).isEmpty)
    }

    /// 命令の ID は、ID・数・向きだけ(文字列は入れない)
    func testCommandIDsKeepOnlyIDsAndNumbers() {
        XCTAssertEqual(GameStore.commandIDs(.crew(.steer(direction: .north))), "direction=north")
    }

    /// 後ろに下がるとき、止まったままなら idle を 1 件書き、いまの画面を入れる
    func testIdleIsWrittenWhenGoingToBackgroundAndNamesTheScreen() async throws {
        let (store, log) = try await makeStore(dir: tempDir())
        store.logPanel("notes")
        await store.perform(.crew(.steer(direction: nil)))
        clockNow.addTimeInterval(30)
        store.flushIdle()
        let idle = try kinds(log, "idle")
        XCTAssertEqual(idle.count, 1)
        XCTAssertEqual(idle.first?["screen"], "notes")
        store.flushIdle()
        XCTAssertEqual(try kinds(log, "idle").count, 1)
    }

    /// minute は夜明けからの分(残りの千分率ではない)
    func testMinuteIsMinutesSinceDawn() async throws {
        let (store, log) = try await makeStore(dir: tempDir())
        store.logPlay(kind: "probe", fields: [:])
        let e = try XCTUnwrap(try events(log).first { $0["kind"] as? String == "probe" })
        XCTAssertEqual(e["minute"] as? Int, store.clock.minutesSinceDawn)
    }

    /// 節目の印は遊び(seed)ごとのファイル。別の seed を遊んでも、元の seed の印は上書きされない
    func testMarksFilesAreSeparatePerSeed() async throws {
        var c = try AppModel.loadBundledContent(bundle: .main)
        c.playtestMarks = ["mark.test.start": PlaytestMarkDef(id: "mark.test.start", when: .always)]
        let dir = tempDir()
        let (a, log) = try await makeStore(content: c, dir: dir, seed: 1)
        await a.recordMarks()
        let (b, _) = try await makeStore(content: c, dir: dir, seed: 2)
        await b.recordMarks()
        let (a2, _) = try await makeStore(content: c, dir: dir, seed: 1)
        await a2.recordMarks()
        XCTAssertEqual(try kinds(log, "mark").count, 2, "seed 1 と 2 で 1 件ずつ。seed 1 を読み直しても増えない")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("playlog").path)
        XCTAssertTrue(names.contains("marks-1.json") && names.contains("marks-2.json"))
    }

    /// 同じ日のうちに上限を超えても、追記のたびに古い日から消える
    func testPruneRunsOnAppendWithinTheSameDay() throws {
        let dir = tempDir().appendingPathComponent("playlog")
        let log = try XCTUnwrap(PlayLog(directory: dir, defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), maxBytes: 600))
        let old = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<4 { log.append(PlayLogEvent(t: old, kind: "x", day: 1, minute: 0, fields: ["k": String(repeating: "a", count: 60)])) }
        let today = old.addingTimeInterval(86_400 * 5)
        for _ in 0..<12 { log.append(PlayLogEvent(t: today, kind: "x", day: 2, minute: 0, fields: ["k": String(repeating: "a", count: 60)])) }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".jsonl") }
        XCTAssertEqual(files.count, 1, "古い日は消え、いまの日だけ残る")
    }

    /// タブ・設定の開閉は panel の open/close で記録し、触ったことにもなる(idle を誤って書かない)
    func testPanelOpenCloseAndTouchSuppressIdle() async throws {
        let (store, log) = try await makeStore(dir: tempDir())
        await store.perform(.crew(.steer(direction: nil)))
        clockNow.addTimeInterval(8)
        store.logPanel("settings")
        clockNow.addTimeInterval(8)
        store.logPanel("settings", open: false)
        clockNow.addTimeInterval(8)
        await store.perform(.crew(.steer(direction: nil)))
        XCTAssertTrue(try kinds(log, "idle").isEmpty)
        let panels = try kinds(log, "panel")
        XCTAssertEqual(panels, [["tab": "settings", "state": "open"], ["tab": "settings", "state": "close"]])
    }
}
