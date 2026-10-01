import XCTest
@testable import ReForgeCore

/// TEST-11: 昼の tick は deltaSeconds の合計だけに依存する。夜の採取・建造は .notAllowed(phase)。
/// 焚き火台なしの夜は「作る」も拒否。
final class T11_RealtimeAndNightTests: XCTestCase {
    let g = Fixture.game

    func testTickDependsOnlyOnTotalSeconds() {
        let start = g.newGame(seed: 11).withBuildings([ID.well, ID.simpleFarm, ID.charcoalPit]).with(ID.water, 3)
        var small = start
        for _ in 0..<18 { small = g.tick(small, deltaSeconds: 10) }
        let big = g.tick(start, deltaSeconds: 180)
        XCTAssertEqual(small, big)
        XCTAssertEqual(big.phase, .dusk)

        // 細かい刻み(UI のタイマー相当)でも同じ
        var fine = start
        for _ in 0..<720 { fine = g.tick(fine, deltaSeconds: 0.25) }
        XCTAssertEqual(fine.inventory, big.inventory)
        XCTAssertEqual(fine.phase, .dusk)

        // 途中まで同じ秒数なら同じ
        var a = start, b = start
        for _ in 0..<6 { a = g.tick(a, deltaSeconds: 10) }
        b = g.tick(b, deltaSeconds: 60)
        XCTAssertEqual(a, b)
        XCTAssertEqual(b.phase, .day)
    }

    func testOvershootIsClampedToDusk() {
        let s = g.tick(g.newGame(seed: 1), deltaSeconds: 10_000)
        XCTAssertEqual(s.phase, .dusk)
        XCTAssertEqual(s.dayElapsedSeconds, 180)
        XCTAssertEqual(g.tick(s, deltaSeconds: 50), s, "日没後は tick で進まない")
    }

    func testInvalidDeltasAreIgnored() {
        let s = g.newGame(seed: 1)
        XCTAssertEqual(g.tick(s, deltaSeconds: -5), s)
        XCTAssertEqual(g.tick(s, deltaSeconds: .nan), s)
        XCTAssertEqual(g.tick(s, deltaSeconds: .infinity), s)
    }

    private func night(fire: Bool) -> GameState {
        var s = g.newGame(seed: 1)
        if fire { s = s.withBuildings([ID.campfire]) }
        s = g.tick(s, deltaSeconds: 180)
        if fire { s = try! g.startNightWork(s).get() } else { s.phase = .night }
        return s
    }

    func testNightWorkGivesFourActions() {
        let s = night(fire: true)
        XCTAssertEqual(s.phase, .night)
        XCTAssertEqual(s.actionPointsLeft, 4)
        XCTAssertEqual(Fixture.text.actionsLabel(s), "残り行動 4/4")
    }

    func testOutdoorActionsAreRejectedAtNight() {
        let s = night(fire: true).with(ID.plantFiber, 9)
        for kind in GatherKind.allCases {
            XCTAssertEqual(g.perform(.gather(kind), on: s), .failure(.notAllowed(.night)))
        }
        XCTAssertEqual(g.perform(.build(ID.simpleFarm), on: s), .failure(.notAllowed(.night)))
        XCTAssertEqual(Fixture.text.message(for: .notAllowed(.night)), "暗くて外には出られない")
        // 作る・携行食はできる
        XCTAssertNoThrow(try g.perform(.craft(ID.charcoalBurn, times: 1), on: s).get())
        XCTAssertNoThrow(try g.perform(.craft(ID.rationRecipe, times: 1), on: s).get())
    }

    func testCraftingIsRejectedAtNightWithoutFire() {
        let s = night(fire: false).with(ID.plantFiber, 9)
        let r = g.perform(.craft(ID.rationRecipe, times: 1), on: s)
        XCTAssertEqual(r, .failure(.noFireAtNight))
        XCTAssertEqual(Fixture.text.message(for: .noFireAtNight), "火がなければ夜は何もできない")
    }

    func testNightWorkNeedsFire() {
        let dusk = g.tick(g.newGame(seed: 1), deltaSeconds: 180)
        XCTAssertFalse(g.canStartNightWork(dusk))
        XCTAssertEqual(g.startNightWork(dusk), .failure(.noFireAtNight))
    }

    func testDuskAllowsOnlySleep() {
        let dusk = g.tick(g.newGame(seed: 1).withBuildings([ID.campfire]), deltaSeconds: 180)
        XCTAssertEqual(g.perform(.craft(ID.charcoalBurn, times: 1), on: dusk), .failure(.notAllowed(.dusk)))
        XCTAssertEqual(g.perform(.gather(.water), on: dusk), .failure(.notAllowed(.dusk)))
        let slept = g.must(.rest, dusk)
        XCTAssertEqual(slept.day, 2)
    }

    func testRestAtNightIsSleep() {
        let s = g.must(.rest, night(fire: true))
        XCTAssertEqual(s.day, 2)
        XCTAssertEqual(s.phase, .day)
        XCTAssertEqual(s.actionPointsLeft, 10)
        XCTAssertEqual(Fixture.text.journal(s.log.last!).hasPrefix("長い夜が明けた"), true)
    }
}
