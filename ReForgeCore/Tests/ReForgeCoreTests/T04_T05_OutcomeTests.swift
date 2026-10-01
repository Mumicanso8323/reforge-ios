import XCTest
@testable import ReForgeCore

/// TEST-04: 食料 0 が 5 日続くと餓死、4 日では継続。水は 3 日。
/// TEST-05: 30 日目の朝 + 井戸・農場・基礎炉 → 勝利。どれか欠けると継続。
final class T04_T05_OutcomeTests: XCTestCase {
    let g = Fixture.game

    func testStarvationAfterFiveDays() {
        var s = g.newGame(seed: 4).with(ID.food, 0).with(ID.water, 60)
        s = g.idleDays(4, s)
        XCTAssertEqual(s.outcome, .ongoing, "4 日では継続")
        XCTAssertEqual(s.daysWithoutFood, 4)
        XCTAssertEqual(Fixture.text.warnings(s).first?.text, "食料が尽きています(あと 1 日で餓死)")
        s = s.with(ID.water, 60)
        s = g.idleDays(1, s)
        XCTAssertEqual(s.outcome, .gameOver(.starvation))
        XCTAssertEqual(s.day, 6)
        XCTAssertEqual(Fixture.text.failureReasonText(.starvation), "食料が尽きて 5 日が過ぎた")
        XCTAssertEqual(g.perform(.gather(.food), on: s), .failure(.gameNotActive))
    }

    func testDehydrationAfterThreeDays() {
        var s = g.newGame(seed: 4).with(ID.water, 0)
        s = g.idleDays(2, s)
        XCTAssertEqual(s.outcome, .ongoing, "2 日では継続")
        s = g.idleDays(1, s)
        XCTAssertEqual(s.outcome, .gameOver(.dehydration))
        XCTAssertEqual(Fixture.text.failureReasonText(.dehydration), "水が尽きて 3 日が過ぎた")
    }

    func testCounterResetsAfterAFullDay() {
        var s = g.newGame(seed: 4).with(ID.food, 0)
        s = g.idleDays(3, s)
        XCTAssertEqual(s.daysWithoutFood, 3)
        s = s.with(ID.food, 20).with(ID.water, 30)
        s = g.idleDays(1, s)
        XCTAssertEqual(s.daysWithoutFood, 0)
        s = s.with(ID.food, 0)
        s = g.idleDays(4, s.with(ID.water, 60))
        XCTAssertEqual(s.outcome, .ongoing, "数え直しなので 4 日では倒れない")
    }

    func testFailureIsCheckedDuringDayTicksToo() {
        // 判定は昼の tick でも行う(数は夜明けで増えるので、閾値を越えた状態なら tick で確定する)
        var s = g.newGame(seed: 4)
        s.daysWithoutWater = 3
        s = g.tick(s, deltaSeconds: 1)
        XCTAssertEqual(s.outcome, .gameOver(.dehydration))
    }

    func testWarnings() {
        let t = Fixture.text
        var s = g.newGame(seed: 4)
        XCTAssertEqual(t.warnings(s), [])
        s = s.with(ID.food, 8)
        XCTAssertEqual(t.warnings(s), [GameText.Warning(level: .caution, text: "食料が 1.6 日分しかありません")])
        s = s.with(ID.food, 0)
        XCTAssertEqual(t.warnings(s).first, GameText.Warning(level: .danger, text: "食料が尽きています(あと 5 日で餓死)"))
        s = s.with(ID.food, 30).with(ID.water, 0)
        XCTAssertEqual(t.warnings(s), [GameText.Warning(level: .danger, text: "水が尽きています(あと 3 日で脱水)")])
    }

    private func stocked(_ s: GameState) -> GameState {
        s.with(ID.food, 60).with(ID.water, 60)
    }

    func testVictoryOnDay30WithThreeBuildings() {
        var s = g.newGame(seed: 5).withBuildings([ID.well, ID.simpleFarm, ID.basicFurnace])
        for _ in 1..<29 { s = g.idleDays(1, stocked(s)) }
        XCTAssertEqual(s.day, 29)
        XCTAssertEqual(s.outcome, .ongoing)
        s = g.idleDays(1, stocked(s))
        XCTAssertEqual(s.day, 30)
        XCTAssertEqual(s.outcome, .victory)
        XCTAssertTrue(s.hasWon)
        XCTAssertEqual(Fixture.text.victoryBody(s), "井戸と畑と炉がそろい、5 人は当面を生き延びられる。この先は、まだ誰も知らない。")

        // 「つづける」: 同じルールで続き、勝利はもう出ない
        s = g.continueAfterVictory(s)
        XCTAssertEqual(s.outcome, .ongoing)
        s = g.idleDays(1, stocked(s))
        XCTAssertEqual(s.day, 31)
        XCTAssertEqual(s.outcome, .ongoing)
    }

    func testNoVictoryIfABuildingIsMissing() {
        for missing in [ID.well, ID.simpleFarm, ID.basicFurnace] {
            let ids = [ID.well, ID.simpleFarm, ID.basicFurnace].filter { $0 != missing }
            var s = g.newGame(seed: 5).withBuildings(ids)
            s.day = 29
            s = g.idleDays(1, stocked(s))
            XCTAssertEqual(s.day, 30)
            XCTAssertEqual(s.outcome, .ongoing, "\(missing) が無い")
        }
    }

    func testVictoryLaterIfBuiltAfterDay30() {
        var s = g.newGame(seed: 5).withBuildings([ID.well, ID.simpleFarm])
        s.day = 34
        s = g.idleDays(1, stocked(s))
        XCTAssertEqual(s.outcome, .ongoing)
        s = g.idleDays(1, stocked(s).withBuildings([ID.basicFurnace]))
        XCTAssertEqual(s.outcome, .victory)
    }
}
