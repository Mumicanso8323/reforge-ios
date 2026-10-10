import XCTest
import ReForgeEngine
@testable import ReForge

/// 世界の差し替え(つづきから・巻き戻し・ロード・DEBUG の台本の合わせ直し)の後、画面の写し(地図の視界・区画の中身・足元カード)が
/// 差し替えた世界のものになる。台本の流し込みと同じ呼び方(GameStore.replaceWorld)で確かめる。
@MainActor
final class ReplaceWorldStoreTests: XCTestCase {
    private func store(seed: UInt64) throws -> (GameStore, ContentDB) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let c = try AppModel.loadBundledContent(bundle: .main)
        let s = GameStore(content: c, world: playable(c, seed: seed), saves: FileSaveStorage(directory: dir))
        return (s, c)
    }

    /// 序の場面と止まった時計の無い、遊べる状態の新しい世界(非公開の層を重ねると、新しい世界は序の場面から始まる。
    /// その間は地図が空の絵・足元カードが出ない決めなので、差し替えの前後の比べには向かない)。
    private func playable(_ c: ContentDB, seed: UInt64) -> WorldState {
        var w = GameBootstrap.newWorld(content: c, seed: seed)
        w.clock.held = false
        w.narrative.scene = nil
        return w
    }

    /// 保存して読み戻した世界(台本の合わせ直しの点と同じ経路)。
    private func savedWorld(_ w: WorldState) throws -> WorldState {
        try SaveCodec.decode(try SaveCodec.encode(SaveEnvelope(slot: .resume, world: w, content: []))).world
    }

    private func assertScreenMatchesHost(_ s: GameStore, _ message: String, file: StaticString = #filePath, line: UInt = #line) async {
        let f = await s.host.frame
        XCTAssertEqual(s.revision, f.revision, message, file: file, line: line)
        XCTAssertEqual(s.mapView, f.map, message + ": 地図の視界と区画の版", file: file, line: line)
        XCTAssertEqual(s.placements, f.placements, message + ": 置いた物", file: file, line: line)
        let all = await s.host.chunks(Array(0..<f.map.chunkRevisions.count))
        for c in all { XCTAssertEqual(s.chunks[c.index], c, message + ": 区画 \(c.index)", file: file, line: line) }
        let card = await s.host.footCard(at: f.focus ?? GridPoint(0, 0))
        XCTAssertEqual(s.footCard, card, message + ": 足元カード", file: file, line: line)
    }

    func testReplaceWorldRebuildsChunksAndFootCard() async throws {
        let (s, c) = try store(seed: 7)
        await s.load()
        await assertScreenMatchesHost(s, "最初")
        // 別の種の世界(地形も違う)を、保存を読み戻した形で差し替える
        let other = try savedWorld(playable(c, seed: 9))
        let generation = s.worldGeneration
        let f = await s.replaceWorld(other)
        XCTAssertEqual(s.worldGeneration, generation + 1, "差し替えで地図の View を作り直す印が進む")
        XCTAssertEqual(s.revision, f.revision)
        await assertScreenMatchesHost(s, "差し替え後")
        XCTAssertEqual(s.mapView.chunkRevisions, Array(repeating: f.revision, count: s.mapView.chunkRevisions.count),
                       "全区画が差し替えの版になっている")
        // もう一度、前の世界へ戻しても同じ
        let back = try savedWorld(playable(c, seed: 7))
        await s.replaceWorld(back)
        await assertScreenMatchesHost(s, "戻した後")
    }

    /// 前の世界の取り込みが await の途中で止まっていても、差し替えの Frame が必ず勝つ(旧い描画に居座らない)。
    func testReplaceWorldBeatsInFlightRefresh() async throws {
        let (s, c) = try store(seed: 7)
        await s.load()
        let stale = await s.host.frame
        let task = Task { await s.refresh(stale) }
        await Task.yield()
        await s.replaceWorld(try savedWorld(playable(c, seed: 9)))
        await task.value
        await assertScreenMatchesHost(s, "取り込み中に差し替え")
    }

    /// 差し替え直後に時計の歩みが入っても、画面の写しは本体の最新に追いつく。
    func testClockStepAfterReplaceKeepsScreenInSync() async throws {
        let (s, c) = try store(seed: 7)
        await s.load()
        await s.replaceWorld(try savedWorld(playable(c, seed: 9)))
        await s.clockStep(realSeconds: 0.5)
        await assertScreenMatchesHost(s, "差し替え後の歩み")
    }
}
