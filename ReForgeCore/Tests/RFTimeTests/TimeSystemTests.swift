import RFContent
import RFKernel
import RFRules
import RFSim
import RFTestSupport
import RFTime
import RFWorld
import XCTest

/// RFTime の受け入れテスト(docs/architecture/F-work-units.md の U4)。
final class TimeSystemTests: XCTestCase {
    /// 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(TimeSystem().handle(foreign, &ctx), .notMine)
    }

    /// 昼:夜 = 8:18。昼は 180 実秒で終わり、日没で止まる。寝ると夜明けまで一括。
    func testDayIsRealtimeAndNightIsSkipped() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 2)
        var realSeconds = 0.0
        while w.clock.phase == .day {
            _ = rig.simulation.advance(&w, realSeconds: 0.5)
            realSeconds += 0.5
        }
        XCTAssertEqual(realSeconds, 180, accuracy: 0.5)
        XCTAssertEqual(w.clock.sinceDawn.seconds, rig.content.clock.dayGameSeconds)
        XCTAssertTrue(w.clock.isNight)
        // 日没で止まる(画面が実時間を渡しても進まない)
        let atDusk = w
        _ = rig.simulation.advance(&w, realSeconds: 1)
        XCTAssertEqual(w, atDusk)
        // 寝る: 夜明けまで一括、夜明けで寝ている印が消える
        XCTAssertEqual(TimeSystem.untilDawn(w.clock, rig.content.clock).seconds, rig.content.clock.nightGameSeconds)
        let r = rig.simulation.apply(.time(.sleep), to: &w)
        XCTAssertEqual(r.steps, Int(rig.content.clock.nightGameSeconds / SimStep.gameSeconds))
        XCTAssertEqual(w.clock.day, 2)
        XCTAssertEqual(w.clock.phase, .day)
        XCTAssertFalse(w.clock.sleeping)
        XCTAssertEqual(w.clock.now.seconds, TimeSystem.dayLength(rig.content.clock).seconds)
    }

    /// 夜作業の行為で時間が進み、残りを寝ても同じ夜明けになる。昼に寝ることはできない。
    func testNightWorkThenSleepReachesTheSameDawn() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        XCTAssertEqual(rig.simulation.apply(.time(.sleep), to: &w).rejection?.reason, "reason.time.still_day")
        _ = rig.playDay(&w)
        XCTAssertNil(rig.simulation.apply(.time(.startNightWork), to: &w).rejection)
        _ = rig.simulation.runSteps(Int(3600 * 5 / SimStep.gameSeconds), &w)  // 夜作業の行為 5 時間ぶん
        XCTAssertEqual(w.clock.phase, .nightWork)
        _ = rig.simulation.apply(.time(.sleep), to: &w)
        XCTAssertEqual(w.clock.day, 2)
        XCTAssertEqual(w.clock.now.seconds, TimeSystem.dayLength(rig.content.clock).seconds)
    }

    /// 画面に時間数を出さないための問い合わせ: 昼の残りの割合と実秒。
    func testDayRemainingWithoutHours() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 4)
        let def = rig.content.clock
        XCTAssertEqual(TimeSystem.dayRemainingPermille(w.clock, def), 1000)
        XCTAssertEqual(TimeSystem.dayRemainingRealSeconds(w.clock, def), 180)
        _ = rig.simulation.runSteps(Int(def.dayGameSeconds / SimStep.gameSeconds / 4), &w)
        XCTAssertEqual(TimeSystem.dayRemainingPermille(w.clock, def), 750)
        XCTAssertEqual(TimeSystem.dayRemainingRealSeconds(w.clock, def), 135)
        _ = rig.playDay(&w)
        XCTAssertEqual(TimeSystem.dayRemainingPermille(w.clock, def), 0)
    }

    /// 閉じている間は進まない: 本体は壁時計を読まず、画面が渡した実時間だけ進む(1 回の上限つき)。
    func testNothingAdvancesWithoutTicks() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 5)
        let before = w
        _ = rig.simulation.advance(&w, realSeconds: 0)
        XCTAssertEqual(w, before)
        _ = rig.simulation.advance(&w, realSeconds: 3600)  // 裏から戻った直後の大きな刻み
        XCTAssertEqual(w.clock.phase, .day)
        XCTAssertLessThanOrEqual(w.clock.sinceDawn.seconds, rig.content.clock.dayGameSeconds / 180 + SimStep.gameSeconds)
    }

    /// 刻み 1 回でも多数回でも同じ: 細かい刻みと粗い刻みと一括のステップで、日没の時計が一致する。
    func testFrameRateIndependence() throws {
        let rig = try TestRig.publicOnly()
        var fine = rig.factory.newWorld(seed: 6)
        var coarse = fine
        var bulk = fine
        _ = rig.playDay(&fine, dt: 1.0 / 120)
        _ = rig.playDay(&coarse, dt: 0.9)
        _ = rig.simulation.runSteps(Int(rig.content.clock.dayGameSeconds / SimStep.gameSeconds), &bulk,
                                    stopAtPhaseChange: true)
        XCTAssertEqual(fine.clock, coarse.clock)
        XCTAssertEqual(fine.clock, bulk.clock)
    }
}
