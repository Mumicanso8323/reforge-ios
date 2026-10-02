import XCTest
import ReForgeEngine
@testable import ReForge

/// PT-B2 のアプリ側: 再開の 1 行(実時間の 10 分)と、考える画面の時計(開発の設定)。シミュレータで回す(CI の ios ジョブ)。
/// 締めの 3 行と resumeLine の中身は ReForgeCore の RFPresentTests(DayWrapTests)が Linux で確かめる。
@MainActor
final class DayWrapAppTests: XCTestCase {
    /// 差し替えられる時計。
    private final class FakeClock {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var date: Date
        init() { date = base }
        func advance(minutes: Double) { date = base.addingTimeInterval(minutes * 60) }
    }

    private func tempSaves() -> FileSaveStorage {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return FileSaveStorage(directory: dir)
    }

    private func tempDefaults() throws -> UserDefaults {
        let name = "reforge.tests.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func content() throws -> ContentDB { try AppModel.loadBundledContent(bundle: .main) }

    /// TEST-B2-4: 実時間 9 分では出ない、11 分では出る。最初の命令で消える。
    func testResumeBannerAppearsAfterTenMinutesAndClearsOnFirstCommand() async throws {
        let c = try content()
        var world = GameBootstrap.newWorld(content: c, seed: 3)
        let at = world.clock.now
        let day = world.clock.day
        let run = world.run.index
        world.ledger.append { id in
            ProvenanceRecord(id: id, at: at, day: day, run: run, actor: .noah, act: .crafted, subject: .item("wood"))
        }
        let clock = FakeClock()
        let defaults = try tempDefaults()
        let store = GameStore(content: c, world: world, saves: tempSaves(), defaults: defaults, now: { clock.date })
        await store.load()
        defaults.set(clock.base.timeIntervalSince1970, forKey: GameStore.lastOperationKey)

        clock.advance(minutes: 9)
        await store.evaluateResume()
        XCTAssertNil(store.resumeBanner, "9 分では出ない")

        clock.advance(minutes: 11)
        await store.evaluateResume()
        let banner = try XCTUnwrap(store.resumeBanner, "11 分で出る")
        XCTAssertNotNil(banner.last, "最後の目立つ行為がある")

        store.choose(.sleep)  // 最初の命令(断られても命令は命令)
        XCTAssertNil(store.resumeBanner, "最初の命令で消える")
        await store.evaluateResume()
        XCTAssertNil(store.resumeBanner, "命令で操作の時刻が更新されたので、すぐには出ない")
    }

    /// 前回の操作の時刻が無ければ(新しい遊び)出さない。時刻は保存の外にある。
    func testNoBannerWithoutLastOperation() async throws {
        let c = try content()
        let clock = FakeClock()
        let store = GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 3), saves: tempSaves(),
                              defaults: try tempDefaults(), now: { clock.date })
        await store.load()
        clock.advance(minutes: 60)
        await store.evaluateResume()
        XCTAssertNil(store.resumeBanner)
    }

    private func gameTime(_ store: GameStore) async -> GameTime { await store.host.world.clock.now }

    /// TEST-B2-5: 切のとき開いても今と同じに進む。入のとき、開いている間は進まず、閉じたら再開する。
    /// 実時間を待たず、時計の 1 回ぶん(`clockStep`)を直に呼ぶ(CI で揺れない)。
    func testBenchClockHoldSetting() async throws {
        let c = try content()
        for hold in [false, true] {
            var world = GameBootstrap.newWorld(content: c, seed: 3)
            world.clock.held = false
            let defaults = try tempDefaults()
            defaults.set(hold, forKey: GameStore.devHoldClockKey)
            let store = GameStore(content: c, world: world, saves: tempSaves(), defaults: defaults)
            await store.load()
            func step(_ n: Int) async { for _ in 0..<n { await store.clockStep(realSeconds: 0.25) } }

            await step(2)
            let beforeOpen = await gameTime(store)
            XCTAssertGreaterThan(beforeOpen, GameTime.zero, "開く前は進んでいる")

            store.benchOpen = true
            let atOpen = await gameTime(store)
            await step(4)
            let whileOpen = await gameTime(store)
            if hold {
                XCTAssertEqual(whileOpen, atOpen, "入: 開いている間は進まない")
            } else {
                XCTAssertGreaterThan(whileOpen, atOpen, "切: 開いていても今と同じに進む")
            }

            store.benchOpen = false
            await step(2)
            let afterClose = await gameTime(store)
            XCTAssertGreaterThan(afterClose, whileOpen, "閉じたら進む")
        }
    }
}
