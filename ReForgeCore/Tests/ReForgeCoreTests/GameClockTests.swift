import XCTest
@testable import ReForgeCore

final class GameClockTests: XCTestCase {
    func testTurnBasedAdvancesOnlyOnPlayerAction() {
        var clock: any GameClock = TurnBasedClock()
        XCTAssertEqual(clock.realTimeDidPass(seconds: 3600, whileInactive: true), 0)
        XCTAssertEqual(clock.playerDidAct(), 1)
        XCTAssertEqual(clock.playerDidAct(), 1)
        XCTAssertEqual(clock.elapsedTicks, 2)
    }

    func testRealTimeAccumulatesFractionalSeconds() {
        var clock = RealTimeClock(secondsPerTick: 2, progressesWhileInactive: false)
        XCTAssertEqual(clock.realTimeDidPass(seconds: 1.5, whileInactive: false), 0)
        XCTAssertEqual(clock.realTimeDidPass(seconds: 1.5, whileInactive: false), 1)
        XCTAssertEqual(clock.realTimeDidPass(seconds: 3.0, whileInactive: false), 2)
        XCTAssertEqual(clock.playerDidAct(), 0)
        XCTAssertEqual(clock.elapsedTicks, 3)
    }

    func testRealTimeInactivePolicy() {
        var frozen = RealTimeClock(secondsPerTick: 60, progressesWhileInactive: false)
        XCTAssertEqual(frozen.realTimeDidPass(seconds: 3600, whileInactive: true), 0)

        var capped = RealTimeClock(secondsPerTick: 60, progressesWhileInactive: true, maxInactiveTicks: 10)
        XCTAssertEqual(capped.realTimeDidPass(seconds: 3600, whileInactive: true), 10)
        XCTAssertEqual(capped.elapsedTicks, 10)
    }

    func testRealTimeIgnoresInvalidDurations() {
        var clock = RealTimeClock(secondsPerTick: 1, progressesWhileInactive: true)
        XCTAssertEqual(clock.realTimeDidPass(seconds: -5, whileInactive: false), 0)
        XCTAssertEqual(clock.realTimeDidPass(seconds: .infinity, whileInactive: true), 0)
        XCTAssertEqual(clock.elapsedTicks, 0)
    }
}
