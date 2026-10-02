import RFContent
import RFKernel
import RFRules
import RFWorld
import XCTest

/// PT-B1 火の見込み(TEST-B1-5・INV-B1-4)。
final class FireOutlookTests: XCTestCase {
    static let def = HearthDef(capSeconds: 43_200, fuels: ["stick": 10_800, "wood": 21_600],
                               thresholds: [0, 10_800, 21_600, 32_400], light: [0, 2, 3, 4, 5],
                               burnPermille: [0, 500, 750, 1000, 1500], pileItem: "stick")
    /// 昼 8 時間・夜 18 時間(日没 28 800・夜半 61 200・夜明け 93 600)。
    static let clock = ClockDef()

    func outlook(_ fuelSeconds: Int, now: Int64, structures: Int = 0) -> FireOutlook {
        let s = HearthState(fuel: fuelSeconds * 1000, lit: fuelSeconds > 0)
        return HearthRule.outlook(s, Self.def, now: GameTime(seconds: now), clock: Self.clock, structuresInLight: structures)
    }

    /// TEST-B1-5: 燃料の残りと時刻の組の表(8 組)で 4 段の答えが合う。
    func testOutlookTable() {
        let rows: [(fuel: Int, now: Int64, structures: Int, want: FireOutlook)] = [
            (3_600, 0, 0, .untilEvening),
            (14_400, 7_200, 0, .midnight),
            (21_600, 28_800, 0, .beforeDawn),
            (43_200, 40_000, 0, .throughNight),
            (43_200, 28_800, 4, .beforeDawn),
            (7_200, 50_000, 0, .beforeDawn),
            (0, 10_000, 0, .untilEvening),
            (0, 50_000, 0, .midnight),
        ]
        for r in rows {
            XCTAssertEqual(outlook(r.fuel, now: r.now, structures: r.structures), r.want, "\(r)")
        }
    }

    /// 見込みは burn で実際に燃やした結果と合う(同じ式)。
    func testOutlookAgreesWithBurn() {
        let edges: [Int64] = [28_800, 61_200, 93_600]
        for fuel in stride(from: 1_800, through: 43_200, by: 3_600) {
            for now in stride(from: Int64(0), to: 93_600, by: 9_000) {
                for structures in [0, 3] {
                    var b = HearthState(fuel: fuel * 1000, lit: true)
                    var t = Int64(0)
                    while b.lit {
                        b = HearthRule.burn(b, Self.def, seconds: 15, structuresInLight: structures, nightWork: false, tended: false)
                        t += 15
                    }
                    let end = now + t
                    // burn は 15 秒刻みなので、境目の 15 秒以内は見ない
                    if edges.contains(where: { abs($0 - end) <= 15 }) { continue }
                    let want: FireOutlook = end < 28_800 ? .untilEvening : end < 61_200 ? .midnight
                        : end < 93_600 ? .beforeDawn : .throughNight
                    XCTAssertEqual(outlook(fuel, now: now, structures: structures), want, "fuel \(fuel) now \(now) s \(structures)")
                }
            }
        }
    }

    /// 1 本くべた後の見込みは、今と同じか良くなる。燃料にならない物なら同じ。状態は変わらない(INV-B1-4)。
    func testAfterOneMoreNeverWorse() {
        let order: [FireOutlook] = [.untilEvening, .midnight, .beforeDawn, .throughNight]
        for fuel in stride(from: 0, through: 43_200, by: 3_600) {
            for now in stride(from: Int64(0), to: 93_600, by: 7_800) {
                let s = HearthState(fuel: fuel * 1000, lit: fuel > 0)
                let before = s
                let t = GameTime(seconds: now)
                let a = HearthRule.outlook(s, Self.def, now: t, clock: Self.clock, structuresInLight: 1)
                let b = HearthRule.outlookAfterOneMore(s, Self.def, item: "stick", now: t, clock: Self.clock, structuresInLight: 1)
                XCTAssertGreaterThanOrEqual(order.firstIndex(of: b)!, order.firstIndex(of: a)!, "fuel \(fuel) now \(now)")
                XCTAssertEqual(s, before)
                XCTAssertEqual(HearthRule.outlookAfterOneMore(s, Self.def, item: "stone", now: t, clock: Self.clock,
                                                              structuresInLight: 1), a)
            }
        }
        // 夜半に尽きる火は、薪(6 時間)を 1 本くべると夜明けの前になる
        XCTAssertEqual(outlook(14_400, now: 20_000), .midnight)
        let s = HearthState(fuel: 14_400_000, lit: true)
        XCTAssertEqual(HearthRule.outlookAfterOneMore(s, Self.def, item: "wood", now: GameTime(seconds: 20_000),
                                                      clock: Self.clock, structuresInLight: 0), .beforeDawn)
    }

    /// 薪の山の本数を入れた見込みは、山が無ければ今と同じで、山があれば良くなる。
    func testOutlookWithPile() {
        let s = HearthState(fuel: 14_400_000, lit: true, pile: 4)
        let now = GameTime(seconds: 40_000)
        let plain = HearthRule.outlook(s, Self.def, now: now, clock: Self.clock, structuresInLight: 0)
        let withPile = HearthRule.outlookWithPile(s, Self.def, now: now, clock: Self.clock, structuresInLight: 0)
        XCTAssertEqual(plain, .beforeDawn)
        XCTAssertEqual(withPile, .throughNight)
        var empty = s
        empty.pile = 0
        XCTAssertEqual(HearthRule.outlookWithPile(empty, Self.def, now: now, clock: Self.clock, structuresInLight: 0), plain)
    }
}
