import XCTest
import Observation
import ReForgeEngine
@testable import ReForge

/// 時刻の色の画面側(W-19)。地形の絵は「区画の番号ごとに 1 枚・revision と段が替わらない限り作り直さない・作り直しは 1 回の描きで 2 枚まで」。
/// 本体(Linux)の RFPresentTests/TimeOfDayScreenTests と対になる。シミュレータで回す(CI の ios ジョブ)。
@MainActor
final class TimeTintScreenTests: XCTestCase {
    // MARK: - 区画の絵の控え

    private func chunk(_ index: Int, revision: Int = 1, step: Int = 0) -> MapChunk {
        let rect = GridRect(origin: GridPoint(index * 4, 0), size: GridSize(width: 4, height: 4))
        let tiles = (0..<16).map { _ in TileView(glyph: "#", tint: TilePalette.poi, fog: .remembered, brightness: 800) }
        return MapChunk(index: index, revision: revision, rect: rect, tiles: tiles,
                        timeTint: TimeTint(brightness: 800, outside: 300, tint: RGB(10, 20, 30), strength: 200, step: step))
    }

    /// 1 回の描き: 頭で beginPass、全区画を引く。
    private func pass(_ cache: MapTerrainCache, _ chunks: [MapChunk]) {
        cache.beginPass()
        for c in chunks { _ = cache.image(for: c, cellSize: 24, terrains: [:]) }
    }

    func testOneRenderPerChunkPerStep() {
        let cache = MapTerrainCache()
        var chunks = (0..<4).map { chunk($0) }
        for _ in 0..<120 { pass(cache, chunks) }
        for c in chunks { XCTAssertEqual(cache.renderCount[c.index], 1, "同じ鍵を 120 回引いても区画 \(c.index) は 1 回") }
        // revision と段を 1 上げた区画だけ 1 増える
        chunks[2] = chunk(2, revision: 2, step: 1)
        pass(cache, chunks)
        XCTAssertEqual(cache.renderCount[2], 2)
        for i in [0, 1, 3] { XCTAssertEqual(cache.renderCount[i], 1, "区画 \(i) は増えない") }
    }

    func testCacheHoldsOneImagePerChunkNumber() {
        let cache = MapTerrainCache()
        for step in 0..<11 {
            let chunks = (0..<4).map { chunk($0, step: step) }
            // 予算で分けて描くので、残りが無くなるまで描く
            for _ in 0..<4 { pass(cache, chunks); if !cache.hasPending { break } }
            XCTAssertLessThanOrEqual(cache.cachedCount, 4, "段 \(step): 控えは区画の数を超えない")
        }
        XCTAssertEqual(cache.cachedCount, 4)
    }

    func testRefreshIsSplitAcrossPasses() {
        let cache = MapTerrainCache()
        pass(cache, (0..<4).map { chunk($0) })
        // 絵がまだ無い 4 枚は、1 回目に全部作る(予算に数えない・黒を見せない)
        XCTAssertEqual(cache.refreshesInPass, 0)
        XCTAssertFalse(cache.hasPending)
        for i in 0..<4 { XCTAssertEqual(cache.renderCount[i], 1) }

        let stale = (0..<4).map { chunk($0, step: 1) }
        pass(cache, stale)
        XCTAssertEqual(cache.refreshesInPass, MapTerrainCache.refreshBudget)
        XCTAssertTrue(cache.hasPending, "予算を超えた区画は古い絵のまま、続きがある")
        pass(cache, stale)
        XCTAssertEqual(cache.refreshesInPass, 2, "2 回目で残り 2 枚")
        pass(cache, stale)
        XCTAssertEqual(cache.refreshesInPass, 0, "3 回目は作り直しなし")
        XCTAssertFalse(cache.hasPending)
        for i in 0..<4 { XCTAssertEqual(cache.renderCount[i], 2, "区画ごとの作り直しは合計 1 回") }
    }

    // MARK: - 色の決め方

    func testTileColorsApplyTheChunkTint() {
        let style = TileStyle(foreground: [RGB(200, 120, 40)], background: RGB(10, 30, 90))
        let tint = TimeTint(brightness: 600, outside: 300, tint: RGB(20, 40, 120), strength: 400, step: 5)
        let p = GridPoint(3, 4)
        let lit = TerrainTileColors.resolve(style: style, point: p, brightness: nil, tint: tint)
        XCTAssertEqual(lit.fg, RGB(200, 120, 40), "光る物(brightness が nil)は元の色")
        XCTAssertEqual(lit.bg, RGB(10, 30, 90))
        let shaded = TerrainTileColors.resolve(style: style, point: p, brightness: 420, tint: tint)
        XCTAssertEqual(shaded.fg, tint.apply(RGB(200, 120, 40), brightness: 420))
        XCTAssertEqual(shaded.bg, tint.apply(RGB(10, 30, 90), brightness: 420))
        let flat = TimeTint(brightness: 1000, outside: 1000, tint: RGB(0, 0, 0), strength: 0, step: 0)
        let same = TerrainTileColors.resolve(style: style, point: p, brightness: 1000, tint: flat)
        XCTAssertEqual(same.fg, RGB(200, 120, 40), "強さ 0・明るさ 1000 なら元の色")
        XCTAssertEqual(same.bg, RGB(10, 30, 90))
        let noBackground = TerrainTileColors.resolve(style: TileStyle(foreground: [RGB(1, 2, 3)]), point: p, brightness: 500, tint: tint)
        XCTAssertNil(noBackground.bg)
    }

    // MARK: - GameStore

    private func store(seed: UInt64 = 7) throws -> GameStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let c = try AppModel.loadBundledContent(bundle: .main)
        var w = GameBootstrap.newWorld(content: c, seed: seed)
        w.clock.held = false
        w.narrative.scene = nil
        return GameStore(content: c, world: w, saves: FileSaveStorage(directory: dir))
    }

    private final class Flag: @unchecked Sendable { var fired = false }

    func testStoreCatchesUpWithTheStepOnKnownChunks() async throws {
        let s = try store()
        await s.load()
        let def = TimeOfDay.resolved(s.content.timeTint, clock: s.content.clock)
        let before = TimeOfDay.tint(minutes: s.clock.minutesSinceDawn, def, clock: s.content.clock).step
        var steps = 0
        while TimeOfDay.tint(minutes: s.clock.minutesSinceDawn, def, clock: s.content.clock).step == before, steps < 400 {
            await s.clockStep(realSeconds: 5)
            steps += 1
        }
        let now = TimeOfDay.tint(minutes: s.clock.minutesSinceDawn, def, clock: s.content.clock).step
        XCTAssertGreaterThan(now, before, "世界が 1 段進んだ")
        let known = s.chunks.values.filter { $0.tiles.contains { $0.fog == .remembered } }
        XCTAssertFalse(known.isEmpty)
        for c in known { XCTAssertEqual(c.timeTint.step, now, "知っている区画 \(c.index) の段が追いつく") }
    }

    func testTimeWordChangesOnlyWhenTheValueChanges() async throws {
        let s = try store()
        await s.load()
        XCTAssertEqual(s.dayBarDots, TimeOfDay.dayBarDots(TimeOfDay.resolved(s.content.timeTint, clock: s.content.clock), clock: s.content.clock))
        // 同じ目印の間は、timeWord を読んでいる側に変更が届かない
        let flag = Flag()
        withObservationTracking { _ = s.timeWord; _ = s.timeMark } onChange: { flag.fired = true }
        await s.clockStep(realSeconds: 0.25)
        XCTAssertFalse(flag.fired, "値が替わらない更新では写さない")
        // 夕方へ飛ばす(目印が替わる)
        guard let evening = s.content.timeTint?.keys.first(where: { $0.mark == .evening }), s.timeMark != .evening else {
            throw XCTSkip("夕方の目印が無い内容")
        }
        var w = GameBootstrap.newWorld(content: s.content, seed: 7)
        w.clock.held = false
        w.narrative.scene = nil
        w.clock.now = w.clock.dayStartedAt + .minutes(evening.at)
        await s.replaceWorld(w)
        XCTAssertEqual(s.timeMark, .evening)
        XCTAssertTrue(flag.fired, "目印が替われば写す")
        XCTAssertEqual(s.timeWord == nil, s.content.texts[TimeOfDay.wordID(.evening)] == nil, "言葉は内容の表から")
    }
}
