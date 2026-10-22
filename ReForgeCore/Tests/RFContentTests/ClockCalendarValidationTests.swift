import RFKernel
import RFContent
import RFTestSupport
import XCTest

/// W-24 暦の値の検証と、旧い内容の出力が変わらないこと。
final class ClockCalendarValidationTests: XCTestCase {
    private func rules(_ edit: (inout ClockDef) -> Void) throws -> Set<String> {
        var db = try TestContent.publicOnly()
        edit(&db.clock)
        return Set(ContentValidator.validate(db).filter { $0.level == .error && $0.rule.hasPrefix("clock.") }.map(\.rule))
    }

    private let good = SeasonCycleDef(cycleDays: 340, boundaries: [85, 170, 255, 340])

    func testValidCalendarPasses() throws {
        XCTAssertEqual(try rules { $0.seasons = self.good; $0.calendarOutlook = CalendarOutlookDef(counter: "counter.x") }, [])
        XCTAssertEqual(try rules { _ in }, [], "旧い内容(seasons 無し)")
    }

    func testBadSeasonValuesAreRejectedWithRuleIDs() throws {
        func s(_ c: Int, _ b: [Int]) throws -> Set<String> { try rules { $0.seasons = SeasonCycleDef(cycleDays: c, boundaries: b) } }
        XCTAssertTrue(try s(0, [1]).contains("clock.seasons.cycleDays"))
        XCTAssertTrue(try s(-5, [1]).contains("clock.seasons.cycleDays"))
        XCTAssertTrue(try s(Int.max, [1]).contains("clock.seasons.cycleDays"))
        XCTAssertTrue(try s(340, []).contains("clock.seasons.boundaries"))
        XCTAssertTrue(try s(340, [100, 100]).contains("clock.seasons.boundaries"), "重なり")
        XCTAssertTrue(try s(340, [200, 100]).contains("clock.seasons.boundaries"), "昇順でない")
        XCTAssertTrue(try s(340, [100, 341]).contains("clock.seasons.boundaries"), "周を超える")
        XCTAssertTrue(try s(340, [0, 100]).contains("clock.seasons.boundaries"))
    }

    func testBadOutlookValuesAreRejectedWithRuleIDs() throws {
        func o(_ d: CalendarOutlookDef, seasons: Bool = true) throws -> Set<String> {
            try rules { $0.seasons = seasons ? self.good : nil; $0.calendarOutlook = d }
        }
        let c: CounterID = "counter.x"
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c), seasons: false).contains("clock.calendarOutlook.seasons"))
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c, leadDays: -1)).contains("clock.calendarOutlook.leadDays"))
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c, initialWidth: -1)).contains("clock.calendarOutlook.initialWidth"))
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c, initialWidth: Int.max)).contains("clock.calendarOutlook.initialWidth"))
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c, narrowEvery: 0)).contains("clock.calendarOutlook.narrowEvery"))
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c, narrowEvery: -3)).contains("clock.calendarOutlook.narrowEvery"))
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c, narrowStep: -2)).contains("clock.calendarOutlook.narrowStep"))
        XCTAssertTrue(try o(CalendarOutlookDef(counter: c, narrowStep: Int.max)).contains("clock.calendarOutlook.narrowStep"))
    }

    /// 検証を通らない値でも、算術は落ちず、広がらない。
    func testArithmeticNeverTrapsOrWidens() {
        let wild = CalendarOutlookDef(counter: "c", leadDays: Int.max, initialWidth: Int.max, narrowEvery: 1, narrowStep: Int.max)
        XCTAssertEqual(wild.width(count: Int.max), 0)
        XCTAssertLessThanOrEqual(wild.width(count: 0), CalendarOutlookDef.maxWidth)
        let negative = CalendarOutlookDef(counter: "c", narrowStep: -2)
        XCTAssertEqual(negative.width(count: 9), 8, "負の narrowStep は広げない")
        XCTAssertEqual(CalendarOutlookDef(counter: "c", narrowEvery: 0).width(count: 3), 2)
        XCTAssertNil(SeasonCycleDef(cycleDays: Int.max, boundaries: [Int.max]).next(elapsedDays: 5))
        XCTAssertEqual(SeasonCycleDef(cycleDays: 100, boundaries: [50, 300]).next(elapsedDays: 60)?.daysLeft, 90, "周を超える替わり目は無視")
    }

    /// 旧い内容は seasons / calendarOutlook のキーを出さず、書き出したバイト列は新しい欄で変わらない。
    func testOldClockEncodesWithoutNewKeysAndRoundTrips() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(ClockDef())
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"dayGameHours":8,"dayRealSeconds":180,"nightGameHours":18}"#)
        XCTAssertEqual(try JSONDecoder().decode(ClockDef.self, from: data), ClockDef())
        let withCal = ClockDef(seasons: good, calendarOutlook: CalendarOutlookDef(counter: "counter.x"))
        XCTAssertEqual(try JSONDecoder().decode(ClockDef.self, from: try enc.encode(withCal)), withCal)
    }
}
