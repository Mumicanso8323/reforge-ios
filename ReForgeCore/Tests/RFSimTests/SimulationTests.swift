import RFContent
import RFKernel
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class SimulationTests: XCTestCase {
    /// 昼をどんな刻みで進めても、日没の時点の世界は同じ(フレームの揺れで結果が変わらない)。
    func testRealtimeIsIndependentOfFrameRate() throws {
        let rig = try TestRig.publicOnly()
        var a = rig.factory.newWorld(seed: 7)
        var b = a
        var c = a
        _ = rig.playDay(&a, dt: 1.0 / 60)
        _ = rig.playDay(&b, dt: 0.37)
        // 一括: 昼のステップ数ぶん
        let steps = Int(rig.content.clock.dayGameSeconds / SimStep.gameSeconds)
        _ = rig.simulation.runSteps(steps, &c, stopAtPhaseChange: true)
        XCTAssertEqual(a.clock.phase, .dusk)
        XCTAssertEqual(a.clock.now, b.clock.now)
        XCTAssertEqual(a.clock.now, c.clock.now)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
    }

    /// 日没で時計は止まる(実時間を渡しても進まない)。寝ると夜明けまで一括で進む。
    func testDuskStopsClockAndSleepRunsToDawn() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        _ = rig.playDay(&w)
        let atDusk = w.clock.now
        _ = rig.simulation.advance(&w, realSeconds: 30)
        XCTAssertEqual(w.clock.now, atDusk)
        XCTAssertNotNil(rig.simulation.apply(.time(.sleep), to: &w).events.first { $0 == .dawn(day: 2) })
        XCTAssertEqual(w.clock.day, 2)
        XCTAssertEqual(w.clock.phase, .day)
        XCTAssertEqual(w.clock.now.seconds, Int64(26 * 3600))
    }

    /// 裏から戻った直後の大きな dt でも、1 回に進むのは上限(1 実秒)ぶんだけ(閉じている間は進まない)。
    func testLargeRealtimeDeltaIsCapped() throws {
        let rig = try TestRig.publicOnly()
        var a = rig.factory.newWorld(seed: 3)
        var b = a
        _ = rig.simulation.advance(&a, realSeconds: 600)
        _ = rig.simulation.advance(&b, realSeconds: Simulation.maxRealSecondsPerAdvance)
        XCTAssertEqual(a.clock.now, b.clock.now)
        XCTAssertEqual(a.clock.phase, .day)
    }

    func testNightWorkOnlyAtDusk() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        XCTAssertEqual(rig.simulation.apply(.time(.startNightWork), to: &w).rejection?.reason, "reason.time.not_dusk")
        _ = rig.playDay(&w)
        XCTAssertNil(rig.simulation.apply(.time(.startNightWork), to: &w).rejection)
        XCTAssertEqual(w.clock.phase, .nightWork)
    }

    /// 決定性: 同じ seed と同じ操作の列なら、同じ世界と同じ出来事の列。
    func testSameSeedSameCommandsSameWorld() throws {
        let rig = try TestRig.publicOnly()
        func run() -> (WorldState, [DomainEvent]) {
            var w = rig.factory.newWorld(seed: 99)
            var events: [DomainEvent] = []
            events += rig.playDay(&w, dt: 0.25).events
            events += rig.simulation.apply(.time(.startNightWork), to: &w).events
            events += rig.simulation.apply(.time(.sleep), to: &w).events
            events += rig.playDay(&w, dt: 0.5).events
            return (w, events)
        }
        let (w1, e1) = run()
        let (w2, e2) = run()
        XCTAssertEqual(w1, w2)
        XCTAssertEqual(e1, e2)
    }

    /// 世界状態は JSON で往復して同じになる。
    func testWorldRoundTripsThroughJSON() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 5)
        _ = rig.playDay(&w)
        let data = try JSONEncoder().encode(w)
        XCTAssertEqual(try JSONDecoder().decode(WorldState.self, from: data), w)
    }
}
