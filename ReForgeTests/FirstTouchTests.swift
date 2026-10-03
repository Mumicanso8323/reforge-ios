import XCTest
import ReForgeEngine
@testable import ReForge

/// A-01 最初の手触り: 序の明るさ・「飛ばす」の印・振動の合図。シミュレータで回す(CI の ios ジョブ)。
@MainActor
final class FirstTouchTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "FirstTouchTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private func tempSaves() -> FileSaveStorage {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return FileSaveStorage(directory: dir)
    }

    // MARK: - 序の明るさ

    func testPrologueTextContrastIsAtLeast4_5ForAllStyles() {
        // 序の文の色と地の色は、見せ方の 3 案(A・B・C)で共通
        for style in PrologueStyle.allCases {
            XCTAssertGreaterThanOrEqual(Contrast.ratio(InkColor.textRGB, InkColor.prologueGroundRGB), 4.5, "\(style)")
        }
        // 角の「飛ばす」(補助の色)も同じ地の上で読める
        XCTAssertGreaterThanOrEqual(Contrast.ratio((0.600, 0.592, 0.565), InkColor.prologueGroundRGB), 4.5)
    }

    func testContrastRatioKnownValues() {
        XCTAssertEqual(Contrast.ratio((1, 1, 1), (0, 0, 0)), 21, accuracy: 0.001)
        XCTAssertEqual(Contrast.ratio((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)), 1, accuracy: 0.001)
    }

    // MARK: - 「飛ばす」の印

    func testSkipFlagIsOffFirstThenSetAfterReadingThenShownSecondTime() {
        let defaults = suite()
        let first = AppModel(saves: tempSaves(), defaults: defaults)
        XCTAssertFalse(first.prologueSeen.isSet, "初回は印が無い")
        first.debugPrologue = DebugPrologue()
        XCTAssertFalse(first.canSkipPrologue, "初回は出ない")
        // 見本の序(撮る起動)は印を立てない
        first.prologueFinished()
        XCTAssertFalse(first.prologueSeen.isSet)
        first.debugPrologue = nil
        // 最後まで読み終えると印が立つ
        first.prologueFinished()
        XCTAssertTrue(first.prologueSeen.isSet)

        let second = AppModel(saves: tempSaves(), defaults: defaults)
        XCTAssertFalse(second.canSkipPrologue, "序が出ていなければ出ない")
        second.debugPrologue = DebugPrologue()
        XCTAssertTrue(second.canSkipPrologue, "2 回目は出る")
    }

    func testSkipAdvancesToTheEnd() async throws {
        let defaults = suite()
        PrologueSeen(defaults: defaults).mark()
        let app = AppModel(saves: tempSaves(), defaults: defaults)
        app.debugPrologue = DebugPrologue()
        XCTAssertNotNil(app.activePrologue)
        app.skipPrologue()
        for _ in 0 ..< 100 where app.activePrologue != nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(app.activePrologue, "残りの行が最後まで送られる")
    }

    // MARK: - 振動の合図

    private let placement = EntityID(1)
    private let record = ProvenanceID(1)

    func testEachOfTheFiveEventsGivesExactlyOneCue() {
        var judge = HapticJudge()
        XCTAssertEqual(judge.cues(for: [.hearthLevelChanged(placement: placement, level: .smoldering)]), [.fireLit])
        XCTAssertEqual(judge.cues(for: [.hearthStoked(placement: placement)]), [.hearthFed])
        XCTAssertEqual(judge.cues(for: [.partChanged(poi: EntityID(2), part: "p", record: record)]), [.partOpened])
        XCTAssertEqual(judge.cues(for: [.built(placement: placement, record: record)]), [.built])
        let gain = DomainEvent.itemGained(holder: .base, stuff: .item("stick"), quantity: 1, record: record)
        let done = DomainEvent.interacted(person: .noah, interaction: "interaction.test.gather",
                                          at: WorldPoint(.surface, GridPoint(0, 0)), record: record)
        XCTAssertEqual(judge.cues(for: [done, gain]), [.gathered])
    }

    func testOtherEventsGiveNoCue() {
        var judge = HapticJudge()
        let gain = DomainEvent.itemGained(holder: .base, stuff: .item("stick"), quantity: 1, record: record)
        XCTAssertTrue(judge.cues(for: [gain]).isEmpty, "行為の終わりでない物の入りでは鳴らない")
        XCTAssertTrue(judge.cues(for: [.dawn(day: 2), .phaseChanged(to: .dusk, day: 1),
                                       .walked(person: .noah, tiles: 1, staminaCost: 1),
                                       .itemSpent(holder: .base, stuff: .item("stick"), quantity: 1)]).isEmpty)
        // 点いていた火が強まる・消えるでは鳴らない。消えた後に点き直したら鳴る
        _ = judge.cues(for: [.hearthLevelChanged(placement: placement, level: .smoldering)])
        XCTAssertTrue(judge.cues(for: [.hearthLevelChanged(placement: placement, level: .burning)]).isEmpty)
        XCTAssertTrue(judge.cues(for: [.hearthLevelChanged(placement: placement, level: .out)]).isEmpty)
        XCTAssertEqual(judge.cues(for: [.hearthLevelChanged(placement: placement, level: .flickering)]), [.fireLit])
    }

    @MainActor private final class SpyHaptics: HapticFiring {
        private(set) var cues: [HapticCue] = []
        private(set) var ramps: [Double] = []
        func fire(_ cue: HapticCue) { cues.append(cue) }
        func ramp(intensity: Double) { ramps.append(intensity) }
    }

    func testGameStoreCallsTheHapticOutletOncePerEventAndNotForOthers() throws {
        let content = try AppModel.loadBundledContent(bundle: .main)
        let spy = SpyHaptics()
        let store = GameStore(content: content, world: GameBootstrap.newWorld(content: content, seed: 5),
                              saves: tempSaves(), haptics: spy)
        store.fireHaptics(for: [.dawn(day: 2)])
        XCTAssertTrue(spy.cues.isEmpty)
        store.fireHaptics(for: [.hearthStoked(placement: placement)])
        XCTAssertEqual(spy.cues, [.hearthFed])
        store.fireHaptics(for: [.built(placement: placement, record: record)])
        XCTAssertEqual(spy.cues, [.hearthFed, .built])
    }

    func testRampStrengthensWithProgressEveryQuarterSecond() throws {
        var ramp = HapticRamp()
        XCTAssertEqual(try XCTUnwrap(ramp.intensity(permille: 0, at: 10.0)), 0.2, accuracy: 0.001)
        XCTAssertNil(ramp.intensity(permille: 100, at: 10.1), "0.25 秒たつまで鳴らさない")
        let mid = ramp.intensity(permille: 500, at: 10.25)
        let end = ramp.intensity(permille: 1000, at: 10.5)
        XCTAssertEqual(try XCTUnwrap(mid), 0.6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(end), 1.0, accuracy: 0.001)
        XCTAssertNil(ramp.intensity(permille: nil, at: 10.6), "離したら止める")
        XCTAssertNotNil(ramp.intensity(permille: 0, at: 10.61), "離した後の押し直しは弱く始まる")
    }
}
