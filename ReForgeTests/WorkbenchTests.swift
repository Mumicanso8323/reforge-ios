import XCTest
import ReForgeEngine
@testable import ReForge

/// 設計・ノートのタブの画面側の状態(U17)。射影そのものは RFPresentTests の WorkbenchTests が Linux で確かめる。
@MainActor
final class WorkbenchAppTests: XCTestCase {
    private func store() throws -> GameStore {
        let c = try AppModel.loadBundledContent(bundle: .main)
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
        let wb = s.workbench
        await wb.reload(s)
        await wb.append("furnace", s)
        await wb.makePlate(s)
        guard let plate = wb.bench?.plates.first else {
            return XCTFail("試験用の札を作れない")
        }
        let before = await s.host.world

        await wb.discard(plate, s)
        XCTAssertNotNil(s.timedUndo, "捨てると取り消しの帯を出す")
        let discarded = await s.host.world
        XCTAssertNil(discarded.invention.designs[plate.design], "捨てる操作はすぐ効く")

        s.undoTimed()
        for _ in 0..<100 {
            if (await s.host.world).invention.designs[plate.design] != nil { break }
            await Task.yield()
        }
        let restored = await s.host.world
        XCTAssertEqual(restored.invention, before.invention, "取り消しで札を戻す")
    }

    /// 技能を付ける選びもすぐ反映し、取り消すと技能を付ける前の世界へ戻る。
    func testGrantUndoRestoresThePreviousWorld() async throws {
        let s = try store()
        await s.load()
        var context = StepContext(world: await s.host.world, content: s.content)
        context.learn("fact.test.device_fixed")
        await s.refresh(await s.host.replace(world: context.world))
        let before = await s.host.world

        await s.workbench.grant(sheet: "sheet.test.ledger", person: "person.test_a", skill: "skill.test.kindling", s)
        let granted = await s.host.world
        XCTAssertTrue(granted.people["person.test_a"]?.skills.contains("skill.test.kindling") == true, "付ける操作はすぐ効く")
        XCTAssertNotNil(s.timedUndo, "付けると取り消しの帯を出す")

        s.undoTimed()
        for _ in 0..<100 {
            if (await s.host.world).people["person.test_a"]?.skills.contains("skill.test.kindling") == false { break }
            await Task.yield()
        }
        let restored = await s.host.world
        XCTAssertEqual(restored, before, "取り消しで技能を付ける前へ戻す")
    }
}
