import RFContent
import RFKernel
import RFRules
import RFWorld
import XCTest

/// W-02d 火のゲージ(INV-D1)。ゲージと見込みの唯一の入口 HearthRule.gauge。
final class HearthGaugeTests: XCTestCase {
    static let def = FireOutlookTests.def
    static let clock = ClockDef()

    func gauge(_ s: HearthState, now: Int64, structures: Int = 0, tended: Bool, stock: Int) -> FireGauge {
        HearthRule.gauge(s, Self.def, now: GameTime(seconds: now), clock: Self.clock, structuresInLight: structures,
                         tended: tended, stock: stock)
    }

    /// 燃料・山・蓄え・番・時刻の表(各 100 以上)。level は HearthRule.level と同じ。outlook は、
    /// 番がいれば山 + 蓄えを入れた outlookWithPile、いなければ山も蓄えも見ない outlook と同じ。
    func testGaugeIsOneEntry() {
        var rows = 0
        for fuel in stride(from: 0, through: 43_200, by: 3_600) {
            for pile in [0, 1, 4, 12] {
                for stock in [0, 2, 9] {
                    for tended in [false, true] {
                        for now in [Int64(0), 20_000, 28_800, 50_000, 70_000] {
                            let s = HearthState(fuel: fuel * 1000, lit: fuel > 0, pile: pile)
                            let g = gauge(s, now: now, structures: pile % 3, tended: tended, stock: stock)
                            rows += 1
                            XCTAssertEqual(g.level, HearthRule.level(s, Self.def))
                            let t = GameTime(seconds: now)
                            if tended {
                                var counted = s
                                counted.pile += stock
                                XCTAssertEqual(g.outlook, HearthRule.outlookWithPile(
                                    counted, Self.def, now: t, clock: Self.clock, structuresInLight: pile % 3, tended: true))
                            } else {
                                XCTAssertEqual(g.outlook, HearthRule.outlook(
                                    s, Self.def, now: t, clock: Self.clock, structuresInLight: pile % 3))
                                XCTAssertEqual(g.outlook, HearthRule.outlookWithPile(
                                    s, Self.def, now: t, clock: Self.clock, structuresInLight: pile % 3, tended: false))
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(rows, 100)
    }

    /// 蓄えは番がいるときだけ効く。番がいなければ蓄えを増やしても同じ。いれば同じか良くなる。
    func testStockOnlyCountsWhenTended() {
        let order: [FireOutlook] = [.untilEvening, .midnight, .beforeDawn, .throughNight]
        let s = HearthState(fuel: 14_400_000, lit: true, pile: 0)
        XCTAssertEqual(gauge(s, now: 28_800, tended: false, stock: 0), gauge(s, now: 28_800, tended: false, stock: 12))
        let none = gauge(s, now: 28_800, tended: true, stock: 0).outlook
        let many = gauge(s, now: 28_800, tended: true, stock: 12).outlook
        XCTAssertGreaterThan(order.firstIndex(of: many)!, order.firstIndex(of: none)!)
    }

    /// 1 本くべた後の見込みも同じ入口: 既定の引数なら今までと同じ。番と蓄えを渡せば gauge と同じ式。世界は変わらない。
    func testAfterOneMoreSharesTheEntry() {
        let s = HearthState(fuel: 7_200_000, lit: true, pile: 1)
        let t = GameTime(seconds: 28_800)
        let plain = HearthRule.outlookAfterOneMore(s, Self.def, item: "stick", now: t, clock: Self.clock, structuresInLight: 0)
        let more = HearthRule.add(s, Self.def, item: "stick", quantity: 1)!
        XCTAssertEqual(plain, HearthRule.outlook(more, Self.def, now: t, clock: Self.clock, structuresInLight: 0))
        let tended = HearthRule.outlookAfterOneMore(s, Self.def, item: "stick", now: t, clock: Self.clock,
                                                    structuresInLight: 0, tended: true, stock: 5)
        XCTAssertEqual(tended, HearthRule.gauge(more, Self.def, now: t, clock: Self.clock, structuresInLight: 0,
                                                tended: true, stock: 5).outlook)
    }
}
