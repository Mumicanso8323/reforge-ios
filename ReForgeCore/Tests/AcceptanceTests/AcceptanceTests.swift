import ReForgeEngine
import RFTestSupport
import XCTest

/// 受け入れテスト(TEST-R1-xx・TEST-S1〜S5 のボット走行)の置き場。
/// 本物のコンテンツが要るテストは、非公開の層が無ければ飛ばす(TestContent.hasPrivateLayer)。
final class AcceptanceTests: XCTestCase {
    /// 通しの最小: 新しい世界 → 昼をリアルタイムで過ごす → 日没 → 夜作業 → 寝る → 夜明け。警告 0。
    func testDayNightLoopRunsWithoutWarnings() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 2026)
        var r = rig.playDay(&w)
        r.merge(rig.simulation.apply(.time(.startNightWork), to: &w))
        r.merge(rig.simulation.apply(.time(.sleep), to: &w))
        XCTAssertEqual(w.clock.day, 2)
        XCTAssertEqual(r.warnings, [])
    }

    /// TEST-S5(決定性)の本物の版: 本物のコンテンツで、同じ seed と操作列から同じ出来事列。
    func testDeterminismWithFullContent() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開のコンテンツが無い(公開 CI では飛ばす)")
        let rig = TestRig(content: try TestContent.full())
        func run() -> [DomainEvent] {
            var w = rig.factory.newWorld(seed: 1)
            var e = rig.playDay(&w).events
            e += rig.simulation.apply(.time(.sleep), to: &w).events
            return e
        }
        XCTAssertEqual(run(), run())
    }
}
