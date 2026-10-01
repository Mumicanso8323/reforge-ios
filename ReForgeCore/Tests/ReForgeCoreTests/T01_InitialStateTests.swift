import XCTest
@testable import ReForgeCore

/// TEST-01: 新規ゲームの初期状態が §6.1 の通り。
final class T01_InitialStateTests: XCTestCase {
    func testNewGameMatchesSpec() {
        let s = Fixture.game.newGame(seed: 0)
        XCTAssertEqual(s.population, 5)
        XCTAssertEqual(s.companions, ["クロム", "シリカ", "カーボ", "ルーメン"])
        XCTAssertEqual(s.quantity(ID.food), 25)
        XCTAssertEqual(s.quantity(ID.water), 18)
        XCTAssertEqual(s.quantity(ID.wood), 20)
        XCTAssertEqual(s.quantity(ID.stone), 5)
        XCTAssertEqual(s.quantity(ID.ironOre), 5)
        XCTAssertEqual(s.quantity("copper_ore"), 0, "銅は Phase 2")
        XCTAssertEqual(s.inventory.count, 5, "ほかの物は持っていない")
        XCTAssertEqual(s.scavengeRemaining, 10)
        XCTAssertEqual(s.actionPointsLeft, 10)
        XCTAssertEqual(s.actionBudget, 10)
        XCTAssertEqual(s.day, 1)
        XCTAssertEqual(s.phase, .day)
        XCTAssertEqual(s.buildings, [])
        XCTAssertEqual(s.outcome, .ongoing)
        XCTAssertEqual(s.cap(for: ID.food, balance: .mvp), 60)
        XCTAssertEqual(s.cap(for: ID.water, balance: .mvp), 60)
        XCTAssertNil(s.cap(for: ID.wood, balance: .mvp))
    }

    func testProtagonistIsNoah() {
        // OPEN-04 確定: 主人公は「ノア」で固定
        XCTAssertEqual(Balance.mvp.protagonistName, "ノア")
        let s = Fixture.game.newGame(seed: 0)
        XCTAssertTrue(Fixture.text.journal(s.log[0]).contains("ノア"))
    }

    func testDefaultPoliciesAreTheSpecDefaults() {
        let g = Fixture.game
        let tm = try! XCTUnwrap(g.timeModel as? MixedDayNightTimeModel)
        XCTAssertEqual(tm.daySeconds, 180)
        XCTAssertEqual(tm.nightGameHours, 18)
        XCTAssertEqual(tm.gameHoursPerDay, 26)
        XCTAssertEqual(tm.dayActionBudget, 10)
        XCTAssertEqual(tm.nightActionBudget, 4)
        XCTAssertTrue(g.failurePolicy is ChoiceFailurePolicy)
        XCTAssertTrue(g.offlinePolicy is NoOfflineProgress)
    }
}
