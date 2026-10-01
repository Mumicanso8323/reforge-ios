import Foundation
import RFContent
import RFKernel
import RFRules
import RFSim
import RFSurvival
import RFTestSupport
import RFTime
import RFWorld
import XCTest

/// 時間と生存の 1 日(本物のコンテンツを重ねたとき)の重さ。寝て夜を飛ばすときも同じ処理を回すので、遅くなったら気づくための見張り。
///
/// - 目標: release ビルドで 1 日をおおむね 50ms 以内(`swift test -c release -Xswiftc -enable-testing --filter SurvivalPerformanceTests`)。
/// - 機械の負荷で揺れるので、落とす上限は目標より緩くする(release 0.5 秒・debug 20 秒)。測った値は出力に出す。
/// - 非公開の層が無ければ飛ばす(公開の層だけでは軽すぎて測る意味が無い)。
final class SurvivalPerformanceTests: XCTestCase {
    func testOneDayOfTimeAndSurvivalIsCheap() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開のコンテンツが無い(公開 CI では飛ばす)")
        let content = try TestContent.full()
        let rig = TestRig(content: content)
        let sim = Simulation(content: content, systems: [TimeSystem(), SurvivalSystem()])
        var w = rig.factory.newWorld(seed: 1)
        let steps = rig.stepsPerDay
        _ = sim.runSteps(10, &w)  // 最初の 1 回の準備を測らない
        let t0 = Date()
        _ = sim.runSteps(steps, &w)
        let seconds = Date().timeIntervalSince(t0)
        #if DEBUG
        let limit = 20.0
        let build = "debug"
        #else
        let limit = 0.5
        let build = "release"
        #endif
        print("PERF Time+Survival 1 日(\(steps) ステップ・\(build)・一員 \(w.people.members.count) 人): \(Int(seconds * 1000)) ms")
        XCTAssertLessThan(seconds, limit)
    }
}
