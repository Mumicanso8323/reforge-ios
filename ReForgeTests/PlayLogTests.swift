import XCTest
@testable import ReForge

/// 操作記録の上限: 全体が大きすぎれば古い日から消し、いちばん新しい日は残す。
final class PlayLogTests: XCTestCase {
    func testPruneRemovesOldestDaysFirstAndKeepsTheNewest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        for name in ["2026-10-01", "2026-10-02", "2026-10-03"] {
            try Data(repeating: 0x61, count: 100).write(to: dir.appendingPathComponent(name + ".jsonl"))
        }
        PlayLog.prune(dir, maxBytes: 250)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(left, ["2026-10-02.jsonl", "2026-10-03.jsonl"])
        PlayLog.prune(dir, maxBytes: 10)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["2026-10-03.jsonl"], "最新の日は残す")
    }
}
