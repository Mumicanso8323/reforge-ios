import XCTest
@testable import ReForgeCore

/// 「休む」「寝る」の取り消し(確認ダイアログの代わり)。取り消すと休む前と完全に同じ状態に戻り、
/// 間に別の行動や時間の経過が入ったら取り消せない。
final class RestUndoTests: XCTestCase {
    let g = Fixture.game

    private func undo(_ s: GameState, file: StaticString = #filePath, line: UInt = #line) -> RestUndo {
        do { return try g.restWithUndo(s).get() } catch {
            XCTFail("休めない: \(error)", file: file, line: line)
            return RestUndo(before: s, after: s)
        }
    }

    /// 昼に少し動いてから(時計・行動・乱数・日誌が初期値でない状態)。
    private func busyDay() -> GameState {
        var s = g.newGame(seed: 7).withBuildings([ID.campfire, ID.well])
        s = g.must(.gather(.wood), s)
        s = g.tick(s, deltaSeconds: 42.5)
        s = g.must(.gather(.stone), s)
        return s
    }

    func testDayRestUndoRestoresExactly() {
        let before = busyDay()
        let u = undo(before)
        XCTAssertEqual(u.before, before)
        XCTAssertEqual(u.after, g.must(.rest, before), "取り消しの有無で休みの結果は変わらない")
        XCTAssertEqual(u.after.phase, .dusk)
        XCTAssertTrue(u.canUndo(u.after))
        let restored = u.undo(u.after)
        XCTAssertEqual(restored, before, "時計・行動ポイント・乱数・日誌まで休む前と同じ")
        XCTAssertEqual(restored?.actionPointsLeft, 8)
        XCTAssertEqual(restored?.dayElapsedSeconds, 42.5)
        XCTAssertEqual(restored?.log, before.log, "「体を休めた」は日誌から消える")
    }

    func testSleepUndoRestoresExactly() {
        let dusk = g.tick(busyDay(), deltaSeconds: 180)
        let night = try! g.startNightWork(dusk).get()
        for before in [dusk, night] {
            let u = undo(before)
            XCTAssertEqual(u.after.day, before.day + 1)
            XCTAssertEqual(u.after.phase, .day)
            XCTAssertNotNil(u.after.lastDawn)
            let restored = u.undo(u.after)
            XCTAssertEqual(restored, before, "日付・その日の集計・夜明けの報告・日誌まで寝る前と同じ")
            // 戻してからもう一度寝ると、同じ朝になる(乱数の位置も戻っている)
            if let restored { XCTAssertEqual(g.must(.rest, restored), u.after) }
        }
    }

    func testUndoIsInvalidAfterAnotherAction() {
        // 夜明けのあとに採取した
        let dusk = g.tick(busyDay(), deltaSeconds: 180)
        let slept = undo(dusk)
        let gathered = g.must(.gather(.water), slept.after)
        XCTAssertFalse(slept.canUndo(gathered))
        XCTAssertNil(slept.undo(gathered))

        // 朝の時計が進んだ
        XCTAssertNil(slept.undo(g.tick(slept.after, deltaSeconds: 1)))

        // 手動セーブ(日誌が増える)
        XCTAssertNil(slept.undo(g.markManualSave(slept.after)))

        // 昼に休んだあと、日没で夜作業をはじめた
        let rested = undo(g.newGame(seed: 3).withBuildings([ID.campfire]))
        let nightWork = try! g.startNightWork(rested.after).get()
        XCTAssertNil(rested.undo(nightWork))

        // 別のプレイの状態(同じ見た目でも after と違えば戻さない)
        XCTAssertNil(rested.undo(g.newGame(seed: 3)))
    }

    func testConsecutiveRestsUndoTogether() {
        // 「休む」を連打して、日没の「寝る」まで押してしまった
        let day = busyDay()
        let rested = undo(day)
        let slept = undo(rested.after).following(rested)
        XCTAssertEqual(slept.after.day, day.day + 1)
        XCTAssertEqual(slept.undo(slept.after), day, "最初の休みの前まで戻る")

        // 間に別のことがあったら、まとめない
        let dusk = g.tick(busyDay(), deltaSeconds: 180)
        let separate = undo(dusk).following(rested)
        XCTAssertEqual(separate.before, dusk)
        XCTAssertEqual(undo(dusk).following(nil).before, dusk)
    }

    func testUndoIsNotOfferedIntoAnEnding() {
        // 水が尽きて 3 日目の夜に寝るとゲームオーバー。結末の画面が選択なので取り消しはしない
        var s = g.idleDays(2, g.newGame(seed: 1).with(ID.water, 0))
        s.inventory[ID.water] = 0
        s = g.tick(s, deltaSeconds: 180)
        let u = undo(s)
        XCTAssertFalse(u.after.isActive)
        XCTAssertFalse(u.canUndo(u.after))
        XCTAssertNil(u.undo(u.after))
    }

    func testRestIsRefusedWhenItCannotHappen() {
        var over = g.newGame(seed: 1)
        over.outcome = .gameOver(.starvation)
        XCTAssertEqual(g.restWithUndo(over).map(\.after), .failure(.gameNotActive))
    }

    func testDawnSummaryIsShort() {
        let t = Fixture.text
        var d = DayTally()
        d.consumed = [ID.food: 5, ID.water: 5, ID.ration: 1]
        d.produced = [ID.water: 2, ID.food: 2, ID.charcoal: 2]
        d.waterShort = true
        let r = DawnReport(endedDay: 1, tally: d, daysWithoutFood: 0, daysWithoutWater: 1)
        XCTAssertEqual(t.dawnSummary(r), [
            "夜が明けた。食料 \u{2212}3、保存食 \u{2212}1、水 \u{2212}3",
            "生産 食料 +2、水 +2、木炭 +2",
            "水が足りなかった",
        ])
        let quiet = DawnReport(endedDay: 1, tally: DayTally(), daysWithoutFood: 0, daysWithoutWater: 0)
        XCTAssertEqual(t.dawnSummary(quiet), ["夜が明けた。食料 ±0、水 ±0"])
        // 全部の内訳は日誌の集計行に残る
        XCTAssertTrue(t.journal(LogEntry(day: 1, event: .dawn(r))).contains("消費: "))
    }
}
