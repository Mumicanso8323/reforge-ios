import XCTest
@testable import ReForgeCore

/// TEST-03: 昼 180 秒の tick 合計 + 「寝る」で 1 日あたり 食料 −5 水 −5(整数一致)。
/// 生産は 井戸 → 農場 → 炭焼き の順、農場は水が無ければ生産しない。昼:夜 = 8:18。
final class T03_DayNightFlowTests: XCTestCase {
    let g = Fixture.game

    func testOneDayConsumesExactlyFiveEach() {
        var s = g.newGame(seed: 3)
        for day in 1...7 {
            s = s.with(ID.food, 30).with(ID.water, 30)
            let food = 30, water = 30
            for _ in 0..<7 { s = g.tick(s, deltaSeconds: 180.0 / 7) }
            s = g.tick(s, deltaSeconds: 0.001) // 浮動小数の端数で 180 に届かなかった場合の押し込み
            XCTAssertEqual(s.phase, .dusk, "180 秒で日没")
            s = g.mustSleep(s)
            XCTAssertEqual(food - s.quantity(ID.food), 5, "\(day) 日目の食料")
            XCTAssertEqual(water - s.quantity(ID.water), 5, "\(day) 日目の水")
            XCTAssertEqual(s.day, day + 1)
            XCTAssertEqual(s.phase, .day)
            XCTAssertEqual(s.actionPointsLeft, 10)
        }
    }

    func testDayNightSplitIsEightToEighteen() {
        let tm = g.timeModel
        XCTAssertEqual(tm.gameSecondsPerDay, 26 * 3600)
        XCTAssertEqual(tm.dayGameSeconds, 8 * 3600)
        // 昼の終わりまでに適用される消費は 5 × 8/26 = 1.53… → 1。残り 4 は夜(寝る)でまとめて
        var s = g.newGame(seed: 3)
        s = g.tick(s, deltaSeconds: 180)
        XCTAssertEqual(s.dayProgressGameSeconds, 8 * 3600)
        XCTAssertEqual(25 - s.quantity(ID.food), 1)
        XCTAssertEqual(18 - s.quantity(ID.water), 1)
        s = g.mustSleep(s)
        XCTAssertEqual(25 - s.quantity(ID.food), 5)
        // 消費の 1 回目は 1 日の 1/5 = 5.2 時間の時点(昼の 8 時間の内側)
        var early = g.newGame(seed: 3)
        early = g.tick(early, deltaSeconds: 180 * 5.2 / 8 - 0.01)
        XCTAssertEqual(early.quantity(ID.food), 25)
        early = g.tick(early, deltaSeconds: 0.02)
        XCTAssertEqual(early.quantity(ID.food), 24)
    }

    func testRestEarlyStillConsumesTheWholeDay() {
        var s = g.newGame(seed: 3)
        s = g.tick(s, deltaSeconds: 30)
        s = g.must(.rest, s)
        s = g.mustSleep(s)
        XCTAssertEqual(s.quantity(ID.food), 20)
        XCTAssertEqual(s.quantity(ID.water), 13)
    }

    func testRationReplacesFoodWhenFoodRunsOut() {
        var s = g.newGame(seed: 3).with(ID.food, 2).with(ID.ration, 10)
        s = g.idleDays(1, s)
        XCTAssertEqual(s.quantity(ID.food), 0)
        XCTAssertEqual(s.quantity(ID.ration), 7)
        XCTAssertEqual(s.daysWithoutFood, 0, "保存食で足りたので飢えていない")
    }

    func testBuildingProductionPerDayAndOrder() {
        // 井戸 +2、農場 水 1 → 食料 2、炭焼き 木材 3 → 木炭 2
        var s = g.newGame(seed: 3).withBuildings([ID.well, ID.simpleFarm, ID.charcoalPit])
        s = s.with(ID.water, 30).with(ID.food, 30).with(ID.wood, 30)
        s = g.idleDays(1, s)
        XCTAssertEqual(s.quantity(ID.water), 30 + 2 - 1 - 5)
        XCTAssertEqual(s.quantity(ID.food), 30 + 2 - 5)
        XCTAssertEqual(s.quantity(ID.wood), 27)
        XCTAssertEqual(s.quantity(ID.charcoal), 2)
        let r = try! XCTUnwrap(s.lastDawn)
        XCTAssertEqual(r.tally.produced, [ID.water: 2, ID.food: 2, ID.charcoal: 2])
        XCTAssertEqual(r.tally.consumed, [ID.water: 6, ID.food: 5, ID.wood: 3])
        XCTAssertEqual(Fixture.text.dawnLines(r), ["消費: 食料 \u{2212}5 水 \u{2212}6 木材 \u{2212}3", "生産: 食料 +2 水 +2 木炭 +2"])
    }

    func testWellWaterReachesFarmBeforeFarmRuns() {
        // 水 0 でも、同じ時刻に井戸が先に動くので農場は動ける(井戸 → 農場の順)
        var s = g.newGame(seed: 3).withBuildings([ID.well, ID.simpleFarm]).with(ID.water, 0).with(ID.food, 30)
        s = g.idleDays(1, s)
        XCTAssertEqual(s.lastDawn?.tally.produced[ID.food], 2)
    }

    func testFarmDoesNothingWithoutWater() {
        var s = g.newGame(seed: 3).withBuildings([ID.simpleFarm]).with(ID.water, 0).with(ID.food, 30)
        s = g.idleDays(1, s)
        XCTAssertNil(s.lastDawn?.tally.produced[ID.food])
        XCTAssertEqual(s.quantity(ID.food), 25)
        XCTAssertTrue(s.lastDawn!.tally.waterShort)
    }

    func testCharcoalPitNeedsWood() {
        var s = g.newGame(seed: 3).withBuildings([ID.charcoalPit]).with(ID.wood, 2)
        s = g.idleDays(1, s)
        XCTAssertEqual(s.quantity(ID.wood), 2)
        XCTAssertEqual(s.quantity(ID.charcoal), 0)
    }

    func testDayTurnModelGivesSameDailyTotals() {
        let mixed = g.idleDays(5, g.newGame(seed: 9).withBuildings([ID.well, ID.simpleFarm]))
        var turn = Fixture.turnGame.newGame(seed: 9).withBuildings([ID.well, ID.simpleFarm])
        for _ in 0..<5 { turn = Fixture.turnGame.mustSleep(turn) }
        XCTAssertEqual(mixed.inventory, turn.inventory)
        XCTAssertEqual(mixed.day, turn.day)
    }
}
