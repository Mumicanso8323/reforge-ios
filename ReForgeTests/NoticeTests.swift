import XCTest
import ReForgeEngine
@testable import ReForge

/// 足元カードの断りは、次の選び・歩き・行為の開始で消え、出してから数秒(実時間)でも消える(押し続けても延びない)。
@MainActor
final class NoticeTests: XCTestCase {
    private func makeStore() async throws -> GameStore {
        let c = try AppModel.loadBundledContent(bundle: .main)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let name = "reforge.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 3),
                              saves: FileSaveStorage(directory: dir), defaults: defaults)
        await store.load()
        return store
    }

    func testNoticeClearsOnNextSelect() async throws {
        let store = try await makeStore()
        store.show(notice: "遠すぎる")
        XCTAssertEqual(store.notice, "遠すぎる")
        store.select(GridPoint(1, 1))
        XCTAssertNil(store.notice, "次の選びで消える")
    }

    func testNoticeClearsOnWalkAndBandChoice() async throws {
        let store = try await makeStore()
        store.select(GridPoint(1, 1))
        store.show(notice: "そこには付けない")
        store.walkToSelection()
        XCTAssertNil(store.notice, "次の歩きで消える")
        store.show(notice: "そこには付けない")
        store.choose(.sleep)
        XCTAssertNil(store.notice, "次の行為の開始で消える")
    }

    func testNoticeExpiresInRealTimeAndRepeatDoesNotExtend() async throws {
        let store = try await makeStore()
        store.noticeLifetime = 0.2
        store.show(notice: "遠すぎる")
        try await Task.sleep(nanoseconds: 120_000_000)
        store.show(notice: "遠すぎる")  // 同じ断りの繰り返しは延ばさない
        XCTAssertEqual(store.notice, "遠すぎる")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(store.notice, "最初に出してから 0.2 秒で消える(繰り返しで延びない)")
    }
}
