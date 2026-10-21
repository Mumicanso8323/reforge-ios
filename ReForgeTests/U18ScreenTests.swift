import XCTest
import ReForgeEngine
@testable import ReForge

/// U18: 拠点・仲間・戦闘・ゲームオーバーの画面の部品と、保存のつなぎ。
@MainActor
final class U18ScreenTests: XCTestCase {
    private func store() throws -> GameStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let c = try AppModel.loadBundledContent(bundle: .main)
        return GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 7),
                         saves: FileSaveStorage(directory: dir))
    }

    func testTextBar() {
        XCTAssertEqual(TextBar.bar(1000, width: 5), "■■■■■")
        XCTAssertEqual(TextBar.bar(0, width: 5), "□□□□□")
        XCTAssertEqual(TextBar.bar(500, width: 4), "■■□□")
    }

    func testTabsFollowGates() {
        XCTAssertEqual(GameTab.visible(UIUnlocks()), GameTab.allCases, "条件が無ければ全部出す")
        let closed = UIUnlocks(gated: [UIElements.tabBase, UIElements.tabCrew, UIElements.tabDesign, UIElements.tabNotes])
        XCTAssertEqual(GameTab.visible(closed), [.map], "最初は地図だけ")
    }

    func testLockedTabsAreNotIncludedInTheTabBarChoices() {
        let locked = UIUnlocks(gated: [UIElements.tabBase, UIElements.tabCrew, UIElements.tabDesign, UIElements.tabNotes])
        XCTAssertFalse(GameTab.visible(locked).contains(.base))
        XCTAssertFalse(GameTab.visible(locked).contains(.crew))
        XCTAssertFalse(GameTab.visible(locked).contains(.design))
        XCTAssertFalse(GameTab.visible(locked).contains(.notes))
    }

    func testBuildRowKindOnlyMakesAffordableOptionsButtons() {
        let affordable = BaseView.BuildOption(kind: "structure.test", name: "試験", glyph: "#", cost: [],
                                               affordable: true, missing: [])
        let unavailable = BaseView.BuildOption(kind: "structure.test", name: "試験", glyph: "#", cost: [],
                                                affordable: false, missing: [(name: "材料", quantity: 2)])
        XCTAssertEqual(BuildRowKind.of(affordable), .button)
        XCTAssertEqual(BuildRowKind.of(unavailable), .plain)
    }

    func testGaugeTextAndPercent() {
        XCTAssertEqual(GaugeText.render(StatGauge(fillPermille: 500, marks: [250, 900]), width: 4), "■┃□┃")
        XCTAssertEqual(PanelText.percent(40), "4%")
        XCTAssertEqual(PanelText.percent(355), "35.5%")
    }

    func testBattleLane() {
        let b = BattleBand(id: EntityID(1), foe: "x", stance: .keepDistance, retreating: false,
                           laneSize: 5, at: GridPoint(0, 0),
                           units: [.init(glyph: "@", isAlly: true, position: 0, hpPermille: 1000, active: true),
                                   .init(glyph: "w", isAlly: false, position: 4, hpPermille: 500, active: true),
                                   .init(glyph: "w", isAlly: false, position: 2, hpPermille: 0, active: false)])
        XCTAssertEqual(BattleBandView.lane(b), "@・・・w") // ja-table
    }

    func testPlacingShowsPreviewAndCancels() async throws {
        let s = try store()
        await s.load()
        guard let kind = s.content.structures.keys.sorted().first else { return }
        s.beginPlacing(kind)
        XCTAssertEqual(s.requestedTab, .map)
        for _ in 0..<50 where s.preview == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(s.preview?.kind, kind, "照準が出る")
        s.cancelPlacing()
        XCTAssertNil(s.placing)
        XCTAssertNil(s.preview)
    }

    func testManualSaveAndLoadAndRestartWithoutDialogs() async throws {
        let s = try store()
        await s.load()
        await s.saveManual(0)
        XCTAssertTrue(s.savePoints().contains { $0.slot == .manual(index: 0) })
        let loaded = await s.load(.manual(index: 0))
        XCTAssertTrue(loaded)

        // 走行を終わらせ、「はじめから」を確認なしで実行する
        var w = await s.host.world
        w.run.outcome = .failed(cause: "text.unknown", record: nil)
        await s.refresh(await s.host.replace(world: w))
        XCTAssertTrue(s.runEnded)
        let choices = await s.recoveryChoices()
        XCTAssertEqual(choices.map(\.option), RecoveryOption.allCases)
        XCTAssertTrue(choices.first { $0.option == .loadSavePoint }?.available == true, "手動セーブから戻れる")
        let problem = await s.recover(.restart)
        XCTAssertNil(problem)
        XCTAssertFalse(s.runEnded)
        XCTAssertTrue(s.savePoints().contains { $0.slot == .manual(index: 0) }, "はじめからでも手動セーブは残る")
    }

    /// 失敗からの復帰はすぐ反映し、取り消すと失敗直前の世界へ戻る。帯の間は時計も止める。
    func testRecoveryUndoRestoresFailedWorldAndPausesClock() async throws {
        let s = try store()
        await s.load()
        var failed = await s.host.world
        failed.narrative.counters["counter.test.doom"] = 1
        failed.run.outcome = .failed(cause: "text.test.cause", record: nil)
        await s.refresh(await s.host.replace(world: failed))

        let problem = await s.recoverUndoable(.continueWithLoss, label: UIText.shared.string("ui.button.recovery_continue"))
        XCTAssertNil(problem)
        XCTAssertFalse(s.runEnded, "復帰はすぐ効く")
        XCTAssertEqual(s.timedUndo?.seconds, 4, "取り消しの帯は4秒")
        XCTAssertTrue(s.isPaused, "復帰の取り消し中は時計を止める")

        s.undoTimed()
        for _ in 0..<100 where !s.runEnded { await Task.yield() }
        XCTAssertTrue(s.runEnded, "取り消すと失敗の画面へ戻る")
        let restored = await s.host.world
        XCTAssertEqual(restored, failed, "取り消しは失敗直前の世界を戻す")
    }

    /// 古い Frame の取り込みが await の途中で止まり、新しい Frame の取り込みが先に終わっても、古い側の暗い場面は居残らない。
    func testStaleRefreshDoesNotWriteBackDarkStart() async throws {
        let s = try store()
        let w = await s.host.world
        let older = await s.host.replace(world: w)
        let newer = await s.host.replace(world: w)
        XCTAssertGreaterThan(newer.revision, older.revision)
        var stale = older
        stale.darkStart = DarkStartView(action: FootCard.Action(id: "interaction.test", label: "x", hold: false,
                                                                at: WorldPoint(.surface, GridPoint(0, 0))))
        let task = Task { await s.refresh(stale) }
        await Task.yield()
        await s.refresh(newer)
        await task.value
        XCTAssertNil(s.darkStart, "新しい Frame に暗い場面は無い。古い側が書き戻さない")
        XCTAssertEqual(s.revision, newer.revision)
    }
}
