import RFContent
import RFKernel
import RFPerception
@testable import RFPresent
import RFTestSupport
import RFWorld
import XCTest

/// W-24 暦の見込み(幅つき・観測で狭まる)。
final class DayWrapCalendarTests: XCTestCase {
    static let counter: CounterID = "counter.test.observed"
    static let seasons = SeasonCycleDef(cycleDays: 340, boundaries: [85, 170, 255, 340])
    static let decl = CalendarOutlookDef(counter: counter)

    private func clock(seasons: SeasonCycleDef? = seasons, decl: CalendarOutlookDef? = decl) -> ClockDef {
        ClockDef(seasons: seasons, calendarOutlook: decl)
    }

    private func range(day: Int, count: Int, seed: UInt64 = 7, _ c: ClockDef? = nil) -> (daysMin: Int, daysMax: Int)? {
        DayWrapRules.calendarRange(clock: c ?? clock(), day: day, count: count, seed: seed)
    }

    /// 1 日目 = 経過 0。85 日目の手前(経過 84)で残り 1 日。
    func testDaysLeftCountsFromFirstDay() {
        XCTAssertEqual(Self.seasons.next(elapsedDays: 0)?.daysLeft, 85)
        XCTAssertEqual(Self.seasons.next(elapsedDays: 84)?.daysLeft, 1)
        XCTAssertEqual(Self.seasons.next(elapsedDays: 85)?.daysLeft, 85, "替わり目を越えると次の替わり目へ")
        XCTAssertEqual(Self.seasons.next(elapsedDays: 85)?.index, 1)
        XCTAssertEqual(Self.seasons.next(elapsedDays: 339)?.daysLeft, 1)
        XCTAssertEqual(Self.seasons.next(elapsedDays: 340)?.daysLeft, 85, "次の周")
        XCTAssertEqual(Self.seasons.next(elapsedDays: 340)?.index, 4)
        XCTAssertNil(SeasonCycleDef(cycleDays: 0, boundaries: [1]).next(elapsedDays: 3))
        XCTAssertNil(SeasonCycleDef(cycleDays: 10, boundaries: []).next(elapsedDays: 3))
    }

    func testNoOutlookWhenCountZeroFarOrUndeclared() {
        XCTAssertNil(range(day: 70, count: 0), "数えが 0")
        XCTAssertNil(range(day: 1, count: 5), "替わり目まで leadDays(25)より遠い")
        XCTAssertNil(range(day: 60, count: 5), "残り 26 日")
        XCTAssertNotNil(range(day: 61, count: 5), "残り 25 日")
        XCTAssertNil(range(day: 70, count: 5, clock(seasons: nil)), "季節の定義が無い")
        XCTAssertNil(range(day: 70, count: 5, clock(decl: nil)), "宣言が無い")
        XCTAssertNil(range(day: 70, count: 5, ClockDef()), "今の内容")
    }

    func testWidthNarrowsEveryThreeNightsAndEndsAsOneNumber() throws {
        let day = 70  // 残り 16 日
        var widths: [Int] = []
        for count in 1...15 {
            let r = try XCTUnwrap(range(day: day, count: count))
            widths.append(r.daysMax - r.daysMin)
            XCTAssertLessThanOrEqual(r.daysMin, 16)
            XCTAssertGreaterThanOrEqual(r.daysMax, 16, "真の残り日数を必ず含む")
            XCTAssertGreaterThanOrEqual(r.daysMin, 1)
        }
        XCTAssertEqual(widths, [8, 8, 6, 6, 6, 4, 4, 4, 2, 2, 2, 0, 0, 0, 0])
        XCTAssertEqual(try XCTUnwrap(range(day: day, count: 12)).daysMin, 16)
        XCTAssertEqual(try XCTUnwrap(range(day: day, count: 12)).daysMax, 16)
    }

    func testRangeContainsTruthAndDoesNotJitterBetweenDays() throws {
        for seed in [1, 2, 3, 99] as [UInt64] {
            var previousOffset: Int?
            for day in 61...85 {
                let left = 86 - day
                let r = try XCTUnwrap(range(day: day, count: 1, seed: seed))
                XCTAssertTrue(r.daysMin <= left && left <= r.daysMax, "day \(day) \(r)")
                if r.daysMin > 1 {
                    let offset = left - r.daysMin
                    if let p = previousOffset { XCTAssertEqual(offset, p, "同じ替わり目の間は幅の中の位置が動かない") }
                    previousOffset = offset
                }
            }
        }
        // 同じ世界・同じ替わり目なら同じ。違う seed では変わりうる
        XCTAssertEqual(range(day: 70, count: 1, seed: 5)?.daysMin, range(day: 70, count: 1, seed: 5)?.daysMin)
        let mins = Set((0..<40).compactMap { range(day: 70, count: 1, seed: UInt64($0))?.daysMin })
        XCTAssertGreaterThan(mins.count, 1)
    }

    func testJSONWithoutSeasonsStillLoadsAndDeclarationsDefault() throws {
        let old = try JSONDecoder().decode(ClockDef.self, from: Data(#"{"dayRealSeconds":180,"dayGameHours":8,"nightGameHours":18}"#.utf8))
        XCTAssertNil(old.seasons)
        XCTAssertNil(old.calendarOutlook)
        XCTAssertEqual(old, ClockDef())
        let json = #"""
        {"dayRealSeconds":180,"dayGameHours":8,"nightGameHours":18,
         "seasons":{"cycleDays":340,"boundaries":[85,170,255,340]},"calendarOutlook":{"counter":"counter.test.observed"}}
        """#
        let c = try JSONDecoder().decode(ClockDef.self, from: Data(json.utf8))
        XCTAssertEqual(c.seasons, Self.seasons)
        XCTAssertEqual(c.calendarOutlook, Self.decl)
        XCTAssertEqual(c.calendarOutlook?.leadDays, 25)
        XCTAssertEqual(c.calendarOutlook?.initialWidth, 8)
    }

    // MARK: 帯の文

    private func calendarCandidates(_ rig: TestRig, _ w: WorldState) -> [DayWrapRules.Candidate] {
        let b = FrameBuilder(content: rig.content)
        return b.outlookCandidates(w, Perceiver(content: rig.content, world: w)).filter { $0.kind == .calendar }
    }

    func testCandidateTextsFollowWidth() throws {
        var content = try TestContent.publicOnly()
        content.clock = clock()
        let rig = TestRig(content: content)
        var w = rig.factory.newWorld(seed: 3)
        w.clock.day = 70
        XCTAssertTrue(calendarCandidates(rig, w).isEmpty, "数えが 0")
        let p = Perceiver(content: rig.content, world: w)
        w.narrative.counters[Self.counter] = 1
        var c = try XCTUnwrap(calendarCandidates(rig, w).first)
        let r = try XCTUnwrap(DayWrapRules.calendarRange(clock: rig.content.clock, day: 70, count: 1, seed: w.seed))
        XCTAssertEqual(c.daysMin, r.daysMin)
        XCTAssertEqual(c.daysMax, r.daysMax)
        XCTAssertEqual(c.text, p.render(TextRef("ui.daywrap.calendar_days_range",
                                               ["min": .int(Int64(r.daysMin)), "max": .int(Int64(r.daysMax))])))
        XCTAssertNotEqual(c.text, p.text(Perceiver.unknownText))
        w.narrative.counters[Self.counter] = 12
        c = try XCTUnwrap(calendarCandidates(rig, w).first)
        XCTAssertEqual(c.daysMin, 16)
        XCTAssertEqual(c.daysMax, 16)
        XCTAssertEqual(c.text, p.render(TextRef("ui.daywrap.calendar_days_left", ["n": .int(16)])))
        XCTAssertEqual(c, DayWrapRules.Candidate.calendarOutlook(daysMin: 16, daysMax: 16, text: c.text))
        // 定義の無い内容では候補に無い
        let plain = try TestRig.publicOnly()
        XCTAssertTrue(calendarCandidates(plain, w).isEmpty)
    }

    func testCalendarIsLeastUrgentOnTies() {
        let a = DayWrapRules.Candidate(kind: .line, milliDays: 1000, text: "a")
        let b = DayWrapRules.Candidate.calendarOutlook(daysMin: 1, daysMax: 3, text: "b")
        XCTAssertEqual(DayWrapRules.mostUrgent([b, a])?.kind, .line)
    }
}
