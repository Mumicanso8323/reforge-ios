import RFContent
import RFKernel
import RFMap
import RFPerception
import RFPresent
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// PT-B2 夜の締めの 3 行(TEST-B2-1〜3)と再開の 1 行(TEST-B2-6)。
final class DayWrapTests: XCTestCase {
    private func dusk(_ rig: TestRig) -> WorldState {
        var w = rig.factory.newWorld(seed: 1)
        w.clock.phase = .dusk
        return w
    }

    @discardableResult
    private func record(_ w: inout WorldState, _ act: ActKind, _ subject: SubjectRef, count: Int = 1,
                        day: Int? = nil, actor: PersonID? = .noah) -> ProvenanceID {
        let at = w.clock.now
        let d = day ?? w.clock.day
        let run = w.run.index
        return w.ledger.append { id in
            ProvenanceRecord(id: id, at: at, day: d, run: run, actor: actor, act: act, subject: subject, count: count)
        }
    }

    // MARK: TEST-B2-1

    /// 1 日に品 A を 3・B を 2 作った世界で、締めの 1 行目は多い順。
    func testMadeListsCountedNamesMostFirst() throws {
        let rig = try TestRig.publicOnly()
        var w = dusk(rig)
        for _ in 0..<2 { record(&w, .crafted, .item("test_ore")) }
        for _ in 0..<3 { record(&w, .crafted, .item("wood")) }
        let b = FrameBuilder(content: rig.content)
        let p = Perceiver(content: rig.content, world: w)
        let wrap = try XCTUnwrap(b.build(w, revision: 1, previous: nil, report: nil).dayWrap)
        XCTAssertEqual(wrap.made, [CountedName(name: p.name(Subject.item("wood")), count: 3),
                                   CountedName(name: p.name(Subject.item("test_ore")), count: 2)])
        XCTAssertEqual(wrap.made.first?.count, 3)
    }

    /// 昨日の来歴・仲間のまとめ(count)・行為の種類・3 つまでの上限・同数は名前の順。
    func testMadeCountsOnlyTodayAndCapsAtThree() throws {
        let rig = try TestRig.publicOnly()
        var w = dusk(rig)
        w.clock.day = 3
        record(&w, .crafted, .item("wood"), day: 2)
        record(&w, .mined, .item("wood"), count: 4)
        record(&w, .gathered, .item("test_ore"), count: 4)
        record(&w, .built, .structure("structure.test.beacon", nil))
        record(&w, .trialed, .structure("structure.test.shelter", nil))
        record(&w, .chose, .item("wood"), count: 9)  // 数えない行為
        let b = FrameBuilder(content: rig.content)
        let p = Perceiver(content: rig.content, world: w)
        let made = b.dayWrap(w).made
        XCTAssertEqual(made.count, 3)
        XCTAssertEqual(made.map(\.count), [4, 4, 1])
        let names = [p.name(Subject.item("wood")), p.name(Subject.item("test_ore"))]
        XCTAssertEqual(Set(made.prefix(2).map(\.name)), Set(names))
        XCTAssertEqual(made[0].name, names.sorted()[0], "同数は名前の順")
        // INV-B2-3: 数は来歴から数えた値と一致する
        XCTAssertEqual(made[0].count, w.ledger.records.filter { $0.day == 3 && $0.subject == .item("wood") && $0.act == .mined }.reduce(0) { $0 + $1.count })
    }

    /// 日没の間だけ Frame に入る(昼・夜作業では入らない)。
    func testDayWrapOnlyAtDusk() throws {
        let rig = try TestRig.publicOnly()
        var w = dusk(rig)
        let b = FrameBuilder(content: rig.content)
        XCTAssertNotNil(b.build(w, revision: 1, previous: nil, report: nil).dayWrap)
        w.clock.phase = .nightWork
        XCTAssertNil(b.build(w, revision: 2, previous: nil, report: nil).dayWrap)
        w.clock.phase = .day
        XCTAssertNil(b.build(w, revision: 3, previous: nil, report: nil).dayWrap)
    }

    /// INV-B2-1: 締めと再開の行は世界を変えない。
    func testBuildingDoesNotChangeWorld() throws {
        let rig = try TestRig.publicOnly()
        var w = dusk(rig)
        record(&w, .crafted, .item("wood"))
        let before = w
        let b = FrameBuilder(content: rig.content)
        _ = b.build(w, revision: 1, previous: nil, report: nil)
        _ = b.dayWrap(w)
        _ = b.resumeLine(w)
        XCTAssertEqual(w, before)
    }

    // MARK: TEST-B2-2

    private func furnaceRecord(_ w: inout WorldState, day: Int? = nil) -> ProvenanceID {
        record(&w, .produced, .module("furnace", w.newEntityID()), day: day)
    }

    /// 初めてラインが動いた日は、2 行目がその物を先に書く。
    func testFirstRunningThingComesFirst() throws {
        let rig = try TestRig.publicOnly()
        var w = dusk(rig)
        let id = w.newEntityID()
        var pl = Placement(id: id, kind: .module("furnace"), at: w.map.spawn, facing: .north,
                           origin: ProvenanceLedger.unknownOrigin, status: .running)
        pl.module = ModuleRuntime(design: nil, step: nil)
        w.placements.items[id] = pl
        _ = furnaceRecord(&w)
        let b = FrameBuilder(content: rig.content)
        let p = Perceiver(content: rig.content, world: w)
        let line = try XCTUnwrap(b.dayWrap(w).running)
        XCTAssertTrue(line.hasPrefix("初めて動いた: " + p.name(of: SubjectRef.module("furnace", nil))), line)
        XCTAssertTrue(line.contains("動いているライン 1"), line)
    }

    /// 前の日に動いていた物は「初めて」ではない。何も動いていなければ 2 行目は無い。
    func testNotFirstOnLaterDay() throws {
        let rig = try TestRig.publicOnly()
        var w = dusk(rig)
        w.clock.day = 2
        _ = furnaceRecord(&w, day: 1)
        _ = furnaceRecord(&w)
        let b = FrameBuilder(content: rig.content)
        XCTAssertNil(b.dayWrap(w).running)
    }

    // MARK: TEST-B2-3

    /// 急ぐ順の決め方の表: 4 つの候補の 6 組。短い日数が勝つ。
    func testMostUrgentTable() {
        typealias C = DayWrapRules.Candidate
        func c(_ k: DayWrapRules.Kind, _ d: Int) -> C { C(kind: k, milliDays: d, text: "\(k)") }
        let table: [(a: C, b: C, winner: DayWrapRules.Kind)] = [
            (c(.water, 2000), c(.food, 1000), .food),
            (c(.water, 500), c(.fire, 1500), .water),
            (c(.water, 2500), c(.line, 1000), .line),
            (c(.food, 2000), c(.fire, 500), .fire),
            (c(.food, 900), c(.line, 1000), .food),
            (c(.fire, 2500), c(.line, 1000), .line),
        ]
        for row in table {
            XCTAssertEqual(DayWrapRules.mostUrgent([row.a, row.b])?.kind, row.winner)
            XCTAssertEqual(DayWrapRules.mostUrgent([row.b, row.a])?.kind, row.winner, "並びに依らない")
        }
        // 同じ急ぎなら 水 → 食料 → 火 → ライン
        XCTAssertEqual(DayWrapRules.mostUrgent(DayWrapRules.Kind.allCases.reversed().map { c($0, 1000) })?.kind, .water)
        XCTAssertNil(DayWrapRules.mostUrgent([]))
        // 火は PT-B1 の火の見込みの 4 段で数える(夜明けまでもつなら急がない。消えていれば一番急ぐ)
        XCTAssertNil(DayWrapRules.fireMilliDays(.throughNight, lit: true))
        XCTAssertEqual(DayWrapRules.fireMilliDays(.throughNight, lit: false), 0)
        XCTAssertEqual(DayWrapRules.fireMilliDays(.untilEvening, lit: true), 0)
        XCTAssertLessThan(DayWrapRules.fireMilliDays(.midnight, lit: true)!, DayWrapRules.fireMilliDays(.beforeDawn, lit: true)!)
    }

    /// 帯の「あと何日分」と日没の締めの「あと何日分」は、同じ世界で同じ数(明日から数えて切り上げ。0 は尽きた時だけ)。
    func testBandAndDayWrapAgreeOnRemainingDays() throws {
        var db = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(#"""
        {"survival": {"consumables": [], "ailments": []},
         "perception": [
           {"subject": "stat:stat.water_days", "variants": [
             {"when": true, "name": "text.test.days", "display": {"number": {"divisor": 1000, "unit": null}}}]},
           {"subject": "stat:stat.food_days", "variants": [
             {"when": true, "name": "text.test.days", "display": {"number": {"divisor": 1000, "unit": null}}}]}],
         "texts": {"text.test.days": "日数"}}
        """#.utf8), to: &db)
        let rig = TestRig(content: db)
        let b = FrameBuilder(content: db)
        for raw: Int64 in [0, 1, 400, 999, 1000, 1001, 1500, 2000, 2999] {
            var w = dusk(rig)
            w.survival.stats["stat.water_days"] = Milli(raw: raw)
            w.survival.stats["stat.food_days"] = Milli(raw: 100_000)  // 遠い食料は締めに出ない
            let band = try XCTUnwrap(b.build(w, revision: 1, previous: nil, report: nil).status
                .first { $0.key == "stat.water_days" }).value
            let wrap = try XCTUnwrap(b.dayWrap(w).outlook)
            XCTAssertEqual(wrap, "水はあと \(band) 日分", "raw=\(raw): 帯 \(band) と締めが食い違う")
            XCTAssertEqual(band == "0", raw == 0, "raw=\(raw): 0 日分は尽きた時だけ")
        }
    }

    /// 世界から: 焚き火が消えていれば火、止まったラインがあれば理由つき、どちらも無ければ何も出さない。
    func testOutlookFromWorld() throws {
        let rig = try TestRig.publicOnly()
        var w = dusk(rig)
        let b = FrameBuilder(content: rig.content)
        XCTAssertNil(b.dayWrap(w).outlook)

        let fire = w.newEntityID()
        var camp = Placement(id: fire, kind: .structure("structure.campfire"), at: w.map.spawn, facing: .north,
                             origin: ProvenanceLedger.unknownOrigin, status: .running)
        var rt = StructureRuntime()
        rt.hearth = HearthState(fuel: 400_000_000, lit: true)
        camp.structure = rt
        w.placements.items[fire] = camp
        XCTAssertNil(b.dayWrap(w).outlook, "夜明けまでもつ火は急がない")
        w.placements.items[fire]?.structure?.hearth = HearthState(fuel: 3_600_000, lit: true)
        XCTAssertEqual(b.dayWrap(w).outlook, "火がもうすぐ消える", "火の見込み(PT-B1)の段で言う")
        w.placements.items[fire]?.structure?.hearth = HearthState()
        XCTAssertEqual(b.dayWrap(w).outlook, "火が消えている")

        let line = w.newEntityID()
        var m = Placement(id: line, kind: .module("furnace"), at: w.map.spawn, facing: .north,
                          origin: ProvenanceLedger.unknownOrigin, status: .stopped(reason: "reason.time.still_day"))
        m.module = ModuleRuntime(design: nil, step: nil)
        w.placements.items[line] = m
        XCTAssertEqual(b.dayWrap(w).outlook, "火が消えている", "火の方が急ぐ")
        w.placements.items[fire]?.structure?.hearth = HearthState(fuel: 400_000_000, lit: true)  // 夜明けまでもつ
        let text = try XCTUnwrap(b.dayWrap(w).outlook)
        let p = Perceiver(content: rig.content, world: w)
        XCTAssertEqual(text, "\(p.name(of: PlaceableKind.module("furnace")))が止まっている: \(p.text("reason.time.still_day"))")
    }

    // MARK: TEST-B2-6

    /// last は、ノアの最後の目立つ行為の来歴から作る。無ければ nil。
    func testResumeLineLastFromProvenance() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        let b = FrameBuilder(content: rig.content)
        XCTAssertNil(b.resumeLine(w).last)
        record(&w, .crafted, .item("wood"))
        let p = Perceiver(content: rig.content, world: w)
        let first = try XCTUnwrap(w.ledger.records.last.flatMap { p.journalLine($0) })
        XCTAssertEqual(b.resumeLine(w).last, first)
        // 目立たない行為・仲間の行為では変わらない
        record(&w, .chose, .item("wood"))
        record(&w, .built, .structure("structure.test.beacon", nil), actor: "person.test_a")
        XCTAssertEqual(b.resumeLine(w).last, first)
        // 後の目立つ行為が勝つ
        record(&w, .placed, .structure("structure.test.shelter", nil))
        let later = try XCTUnwrap(w.ledger.records.last.flatMap { p.journalLine($0) })
        XCTAssertEqual(b.resumeLine(w).last, later)
        XCTAssertNotEqual(first, later)
    }

    /// next は今の目標の表示と同じ。
    func testResumeLineNextMatchesObjective() throws {
        let rig = try TestRig.publicOnly()
        let w = rig.factory.newWorld(seed: 1)
        let b = FrameBuilder(content: rig.content)
        let f = b.build(w, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(b.resumeLine(w).next, f.objective)
    }
}
