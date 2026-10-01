import XCTest
@testable import ReForgeCore

/// DEC-11 / OPEN-02(オーナー決定): ゲームオーバー後に 4 つの方針から選ぶ。4 つとも同じ扱い。
final class FailureRecoveryTests: XCTestCase {
    let g = Fixture.game

    /// 6 日目の朝に餓死した状態。資材を少し持っている。
    private func starved() -> GameState {
        var s = g.newGame(seed: 21).with(ID.food, 0).with(ID.water, 60)
        s = s.withBuildings([ID.campfire, ID.well])
        s = s.with(ID.wood, 31).with(ID.stone, 7).with(ID.ironPlate, 1).with(ID.ration, 0)
        s = g.idleDays(5, s)
        XCTAssertEqual(s.outcome, .gameOver(.starvation))
        return s
    }

    private func savePoint() -> GameState {
        g.idleDays(2, g.newGame(seed: 21))
    }

    func testFourOptionsInOwnerOrderAllAvailable() {
        let choices = g.recoveryChoices(for: starved(), savePoint: savePoint())
        XCTAssertEqual(choices.map(\.recovery.option), [.restart, .rewindWithMemory, .continueWithLoss, .loadSavePoint])
        XCTAssertEqual(choices.map(\.available), [true, true, true, true])
        XCTAssertEqual(choices.map { Fixture.text.recoveryTitle($0.recovery.option) },
                       ["最初からやり直す", "記憶を持ったまま巻き戻す", "失って、ここから続ける", "最後の記録から読み込む"])
    }

    func testRecoveryOnlyAfterGameOver() {
        XCTAssertNil(g.recover(.restart, from: g.newGame(seed: 1), savePoint: nil))
    }

    // 1. 最初からやり直す
    func testRestart() throws {
        let failed = starved()
        let s = try XCTUnwrap(g.recover(.restart, from: failed, savePoint: savePoint()))
        let fresh = g.newGame(seed: s.seed)
        XCTAssertEqual(s, fresh, "新規ゲームと同じ")
        XCTAssertNotEqual(s.seed, failed.seed)
        XCTAssertEqual(s.day, 1)
        XCTAssertEqual(s.outcome, .ongoing)
        XCTAssertEqual(s.log.count, 1, "日誌も新しく")
        // 決定的: 同じ失敗からは同じ新しい seed
        XCTAssertEqual(g.recover(.restart, from: failed, savePoint: nil)?.seed, s.seed)
    }

    // 2. 記憶を持ったまま巻き戻す(持ち越しは仮値: 資材の 50%、日誌を残す)
    func testRewindWithMemory() throws {
        let failed = starved()
        let s = try XCTUnwrap(g.recover(.rewindWithMemory, from: failed, savePoint: nil))
        XCTAssertEqual(s.day, 1)
        XCTAssertEqual(s.phase, .day)
        XCTAssertEqual(s.outcome, .ongoing)
        XCTAssertEqual(s.buildings, [], "建造物は持ち越さない")
        XCTAssertEqual(s.population, 5, "仲間は全員そろう")
        XCTAssertEqual(s.quantity(ID.food), 25, "食料・水は初期値")
        XCTAssertEqual(s.quantity(ID.water), 18)
        XCTAssertEqual(s.quantity(ID.wood), 20 + failed.quantity(ID.wood) / 2)
        XCTAssertEqual(s.quantity(ID.stone), 5 + failed.quantity(ID.stone) / 2)
        XCTAssertEqual(s.quantity(ID.ironPlate), 0, "1 の半分は切り捨て")
        XCTAssertEqual(s.scavengeRemaining, 10)
        XCTAssertEqual(s.rewindCount, 1)
        XCTAssertTrue(s.log.count > failed.log.count, "日誌(記憶)は残る")
        XCTAssertEqual(Array(s.log.prefix(failed.log.count)), failed.log)
        XCTAssertTrue(Fixture.text.journal(s.log.last!).hasPrefix("記憶を頼りに、1 日目からやり直した"))
    }

    // 3. 仲間や資源の一部を失って、その場から続ける(仮値: 仲間 1 人、物資の 50%)
    func testContinueWithLoss() throws {
        let failed = starved()
        let s = try XCTUnwrap(g.recover(.continueWithLoss, from: failed, savePoint: nil))
        XCTAssertEqual(s.day, failed.day, "その日から続ける")
        XCTAssertEqual(s.outcome, .ongoing)
        XCTAssertEqual(s.companions, ["クロム", "シリカ", "カーボ"], "後ろの 1 人が去る")
        XCTAssertEqual(s.population, 4)
        XCTAssertEqual(s.buildings, failed.buildings, "建造物は残る")
        for item in g.content.items.map(\.id) {
            let q = failed.quantity(item)
            XCTAssertEqual(s.quantity(item), q - q * 50 / 100, item)
        }
        XCTAssertEqual(s.daysWithoutFood, 0)
        XCTAssertEqual(s.daysWithoutWater, 0)
        // 人口が減ったので消費も減る
        let next = g.idleDays(1, s.with(ID.food, 20))
        XCTAssertEqual(next.quantity(ID.food), 16)
        XCTAssertTrue(Fixture.text.journal(s.log.last!).hasPrefix("ルーメンが拠点を去った"))

        // 仲間がもういない場合は物資だけ失う
        var alone = failed
        alone.companions = []
        let s2 = try XCTUnwrap(g.recover(.continueWithLoss, from: alone, savePoint: nil))
        XCTAssertEqual(s2.population, 1)
        XCTAssertEqual(s2.outcome, .ongoing)
    }

    // 4. 最後のセーブ地点からロードする
    func testLoadSavePoint() throws {
        let failed = starved()
        let point = savePoint()
        let s = try XCTUnwrap(g.recover(.loadSavePoint, from: failed, savePoint: point))
        XCTAssertEqual(s.day, point.day)
        XCTAssertEqual(s.inventory, point.inventory)
        XCTAssertEqual(s.rngState, point.rngState)
        XCTAssertEqual(Array(s.log.dropLast()), point.log)
        XCTAssertEqual(Fixture.text.journal(s.log.last!), "3 日目の記録から再開した")

        // セーブ地点が無い / 終わった状態のセーブ地点しか無いときは選べない
        XCTAssertNil(g.recover(.loadSavePoint, from: failed, savePoint: nil))
        XCTAssertNil(g.recover(.loadSavePoint, from: failed, savePoint: failed))
        let choices = g.recoveryChoices(for: failed, savePoint: nil)
        XCTAssertEqual(choices.first { $0.recovery.option == .loadSavePoint }?.available, false)
    }

    func testRecoveriesAreSwappable() throws {
        let custom = Game(content: g.content, failurePolicy: ChoiceFailurePolicy(recoveries: [
            ContinueWithLossRecovery(config: LossConfig(companionsLost: 2, itemLossPercent: 10)),
        ]))
        var s = custom.idleDays(5, custom.newGame(seed: 1).with(ID.food, 0).with(ID.water, 60).with(ID.wood, 100))
        XCTAssertEqual(s.outcome, .gameOver(.starvation))
        XCTAssertEqual(custom.recoveryChoices(for: s, savePoint: nil).map(\.recovery.option), [.continueWithLoss])
        s = try XCTUnwrap(custom.recover(.continueWithLoss, from: s, savePoint: nil))
        XCTAssertEqual(s.population, 3)
        XCTAssertNil(custom.recover(.restart, from: s, savePoint: nil))
    }

    func testDetailTexts() {
        let failed = starved()
        let t = Fixture.text
        let details = g.recoveryChoices(for: failed, savePoint: savePoint()).map {
            t.recoveryDetail($0.recovery, failed: failed, savePoint: savePoint())
        }
        XCTAssertEqual(details, [
            "1 日目から、すべてを新しくはじめる",
            "1 日目に戻る。資材を持ち越す(木材 15、石材 3、鉄鉱石 2)",
            "ルーメンが去り、物資の半分を失って、この朝から続ける",
            "3 日目の記録から再開する",
        ])
    }
}
