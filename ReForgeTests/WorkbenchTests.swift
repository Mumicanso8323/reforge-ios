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
        XCTAssertEqual(SenseWords.phrase(30), "三割くらい")
        XCTAssertEqual(SenseWords.phrase(2), "ほとんど無い")
        XCTAssertEqual(SenseWords.phrase(100), "混じり気がほぼ無い")
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
        await wb.remove(0, s)
        XCTAssertEqual(wb.steps.count, 1)
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
}
