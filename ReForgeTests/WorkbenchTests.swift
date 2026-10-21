import XCTest
import ReForgeEngine
@testable import ReForge

/// 設計・ノートのタブの画面側の状態(U17)。射影そのものは RFPresentTests の WorkbenchTests が Linux で確かめる。
@MainActor
final class WorkbenchAppTests: XCTestCase {
    /// 公開の層だけで作る。CI は非公開の層を重ねて回し、非公開の層は公開の試験用の物(工程・人・表)を外す。
    /// ここで確かめるのは画面側の状態と取り消しの帯の配線で、物語のコンテンツには依らない。
    private func store() throws -> GameStore {
        let root = try XCTUnwrap(Bundle.main.url(forResource: "content", withExtension: nil))
        let c = try ContentLoader.load(layers: [root.appendingPathComponent("public", isDirectory: true)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return GameStore(content: c, world: GameBootstrap.newWorld(content: c, seed: 3), saves: FileSaveStorage(directory: dir))
    }

    func testSenseWordsNeverShowNumbers() {
        XCTAssertEqual(SenseWords.tenths(30), 3)
        XCTAssertEqual(SenseWords.tenths(2), 0)
        XCTAssertEqual(SenseWords.tenths(96), 10)
    }

    /// 下書きは画面側の状態: 積む・動かす・崩すが本体を変えずにでき、タブを替えても残る(store が持つ)。
    func testDraftEditsWithoutTouchingWorld() async throws {
        let s = try store()
        await s.load()
        let wb = s.workbench
        await wb.reload(s)
        XCTAssertNotNil(wb.bench)
        XCTAssertNotNil(wb.notebook)
        let before = await s.host.world
        await wb.append("furnace", s)
        await wb.append("quench_tank", s)
        XCTAssertEqual(wb.steps.map(\.module), ["furnace", "quench_tank"])
        XCTAssertEqual(wb.draft?.rows.count, 2)
        await wb.move(1, by: -1, s)
        XCTAssertEqual(wb.steps.map(\.module), ["quench_tank", "furnace"])
        let removed = wb.steps[0]
        await wb.remove(0, s)
        XCTAssertEqual(wb.steps.count, 1)
        await wb.restore(step: removed, at: 0, s)
        XCTAssertEqual(wb.steps.map(\.module), ["quench_tank", "furnace"], "工程の取り消しで元の場所に戻る")
        XCTAssertTrue(s.workbench === wb)
        let after = await s.host.world
        XCTAssertEqual(before.invention, after.invention, "下書きは本体に書かない")
        await wb.clear(s)
        XCTAssertNil(wb.draft)
    }

    /// 断られた操作はタブの中に 1 行(ダイアログは出さない)。
    func testRejectedPlateShowsMessageInTab() async throws {
        let s = try store()
        await s.load()
        let wb = s.workbench
        await wb.makePlate(s)
        XCTAssertNotNil(wb.message, "段が無いので断られ、理由が出る")
    }

    /// 札を捨てる操作はすぐ反映し、取り消しの帯から本体の札を戻せる。
    func testDiscardPlateUndoRestoresTheDesign() async throws {
        let s = try store()
        await s.load()
        // 開始時は工程が無い(Z2)。炉を解いた世界で札を作る
        var unlocked = await s.host.world
        unlocked.research.unlocked.modules.insert("furnace")
        await s.refresh(await s.host.replace(world: unlocked))
        let wb = s.workbench
        await wb.reload(s)
        await wb.append("furnace", s)
        await wb.makePlate(s)
        guard let plate = wb.bench?.plates.first else {
            return XCTFail("試験用の札を作れない: \(wb.message ?? "-")")
        }
        let before = await s.host.world

        await wb.discard(plate, s)
        XCTAssertNotNil(s.timedUndo, "捨てると取り消しの帯を出す")
        let discarded = await s.host.world
        XCTAssertNil(discarded.invention.designs[plate.design], "捨てる操作はすぐ効く")

        await s.undoTimed()?.value
        let restored = await s.host.world
        XCTAssertEqual(restored.invention, before.invention, "取り消しで札を戻す")
    }

    /// 帯が出ている間に次の操作をすると、帯は確定して閉じる(古い写しで後の操作を消さない)。
    func testNextOperationCommitsThePendingUndo() async throws {
        let s = try store()
        await s.load()
        var unlocked = await s.host.world
        unlocked.research.unlocked.modules.insert("furnace")
        await s.refresh(await s.host.replace(world: unlocked))
        let wb = s.workbench
        await wb.reload(s)
        await wb.append("furnace", s)
        await wb.makePlate(s)
        guard let plate = wb.bench?.plates.first else {
            return XCTFail("試験用の札を作れない: \(wb.message ?? "-")")
        }
        await wb.discard(plate, s)
        XCTAssertNotNil(s.timedUndo)
        _ = await s.perform(.crew(.steer(direction: nil)))
        XCTAssertNil(s.timedUndo, "次の操作で帯は閉じる")
        XCTAssertNil(s.undoTimed(), "閉じた帯は戻さない")
        let after = await s.host.world
        XCTAssertNil(after.invention.designs[plate.design], "捨てたまま")
    }

    /// 「戻す」の直後の操作は、戻した世界の上で効く(戻す差し替えが後の操作を上書きしない)。
    func testOperationRightAfterUndoRunsOnTheRestoredWorld() async throws {
        let s = try store()
        await s.load()
        var unlocked = await s.host.world
        unlocked.research.unlocked.modules.insert("furnace")
        await s.refresh(await s.host.replace(world: unlocked))
        let wb = s.workbench
        await wb.reload(s)
        await wb.append("furnace", s)
        await wb.makePlate(s)
        guard let plate = wb.bench?.plates.first else {
            return XCTFail("試験用の札を作れない: \(wb.message ?? "-")")
        }
        await wb.discard(plate, s)
        // 「戻す」の差し替えを本体へ送る手前で止め、その間に次を押す(差し替えより後の操作が先に本体へ届きうる形)
        let gate = Gate()
        let settling = Gate()
        s.undoInstallHook = { await gate.wait() }
        s.undoSettleHook = { await settling.arrive() }
        s.undoTimed()
        await gate.entered()  // 差し替えが関門で止まってから次を押す
        async let second: Void = wb.discard(plate, s)
        await settling.entered()  // 次の操作が差し替えを待ち始めてから関門を開ける
        await gate.open()
        await second
        XCTAssertNil(wb.message, "戻した札をもう一度捨てられる")
        XCTAssertNotNil(s.timedUndo, "2 度目の捨てるにも帯が出る")
        let after = await s.host.world
        XCTAssertNil(after.invention.designs[plate.design], "後の操作が残る")
    }

    /// 技能を付ける選びもすぐ反映し、取り消すと技能を付ける前の世界へ戻る。
    func testGrantUndoRestoresThePreviousWorld() async throws {
        let s = try store()
        await s.load()
        // 開始時は仲間がいない(Z2)。付ける相手を仲間にした世界で付ける
        var context = StepContext(world: await s.host.world, content: s.content)
        context.learn("fact.test.device_fixed")
        var person = context.world.people["person.test_a"] ?? PersonState(id: "person.test_a", presence: .unmet)
        person.presence = .member(since: .zero)
        person.position = context.world.map.spawn
        context.world.people["person.test_a"] = person
        await s.refresh(await s.host.replace(world: context.world))
        let before = await s.host.world

        await s.workbench.grant(sheet: "sheet.test.ledger", person: "person.test_a", skill: "skill.test.kindling", s)
        XCTAssertNil(s.workbench.message, "付ける操作が断られた")
        let granted = await s.host.world
        XCTAssertTrue(granted.people["person.test_a"]?.skills.contains("skill.test.kindling") == true, "付ける操作はすぐ効く")
        XCTAssertNotNil(s.timedUndo, "付けると取り消しの帯を出す")

        await s.undoTimed()?.value
        let restored = await s.host.world
        XCTAssertEqual(restored, before, "取り消しで技能を付ける前へ戻す")
    }
}

/// 開くまで待たせる関門(試験用)。
private actor Gate {
    private var opened = false
    private var arrived = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    /// 止まらずに着いた印だけを付ける。
    func arrive() {
        arrived = true
        watchers.forEach { $0.resume() }
        watchers.removeAll()
    }

    func wait() async {
        arrive()
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// 誰かが関門に着くまで待つ。
    func entered() async {
        if arrived { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
