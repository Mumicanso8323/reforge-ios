import Foundation
import RFContent
import RFKernel
import RFMap
import RFPerception
import RFPresent
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// W-02d 火の画面(帯の火のゲージ・寝る見込みの 1 行・申し出)。INV-D1(式は 1 本)・INV-D2(見せた申し出は必ず受かる)・
/// TEST-O11(見込み = 実際)。人・文字列は中立の試験用の ID。
final class FireScreenTests: XCTestCase {
    static let overlay = """
    {
      "texts": { "text.test.offer.a": "line a" },
      "crewWork": { "tendOffer": { "order": ["person.test_b", "person.test_a", "person.test_c"],
                                   "lines": { "person.test_a": "text.test.offer.a" } } }
    }
    """

    func content(offer: Bool = true, handFirst: Bool = false) throws -> ContentDB {
        var db = try TestContent.publicOnly()
        if offer { try ContentLoader.apply(json: Data(Self.overlay.utf8), to: &db) }
        if handFirst {
            let json = #"{ "crewWork": { "requireHandFirst": true, "tendFamily": "family.test.tend", "tendOffer": { "order": ["person.test_b"] } } }"#
            try ContentLoader.apply(json: Data(json.utf8), to: &db)
        }
        db.structures["structure.campfire"]?.hearth?.initialSeconds = 0
        db.modules["furnace"]?.hearth = HearthDef(capSeconds: 0, fuels: [:], thresholds: [0, 0, 0, 0],
                                                  light: [0, 0, 0, 0, 0], burnPermille: [0, 0, 0, 0, 0],
                                                  furnace: FurnaceHeatDef())
        return db
    }

    let dayLength: Int64 = 28_800 + 64_800

    func at(_ w: WorldState, _ dx: Int, _ dy: Int) -> WorldPoint {
        WorldPoint(.surface, w.map.spawn.point + GridPoint(dx, dy))
    }

    @discardableResult
    func campfire(_ w: inout WorldState, fuelSeconds: Int, pile: Int = 0, dx: Int = 3, complete: Bool = true) -> EntityID {
        let id = w.newEntityID()
        var p = Placement(id: id, kind: .structure("structure.campfire"), at: at(w, dx, 3), facing: .north,
                          origin: ProvenanceLedger.unknownOrigin,
                          status: complete ? .running : .underConstruction(progress: 0))
        var rt = StructureRuntime()
        rt.hearth = HearthState(fuel: fuelSeconds * 1000, lit: fuelSeconds > 0, pile: pile)
        p.structure = rt
        w.placements.items[id] = p
        return id
    }

    func member(_ w: inout WorldState, _ id: PersonID, dx: Int, onMap: Bool = true,
                presence: Presence = .member(since: .zero)) {
        var ps = PersonState(id: id, presence: presence)
        if onMap { ps.position = at(w, dx, 1) }
        w.people[id] = ps
    }

    func setStock(_ w: inout WorldState, _ n: Int, _ content: ContentDB) {
        var ctx = StepContext(world: w, content: content)
        if n > 0 { ctx.addStock(.item("stick"), n, to: .base) }
        _ = ctx.drainEvents()
        w = ctx.world
    }

    func dusk(_ w: inout WorldState, offset: Int64 = 0) {
        w.clock.phase = .dusk
        w.clock.dayStartedAt = .zero
        w.clock.now = GameTime(seconds: 28_800 + offset)
    }

    func frame(_ b: FrameBuilder, _ w: WorldState) -> Frame { b.build(w, revision: 1, previous: nil, report: nil) }

    // MARK: 1. 式は 1 本(INV-D1)

    func testOneFormulaForAllConsumers() throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        let texts: [FireOutlook: String] = [.untilEvening: "火がもうすぐ消える", .midnight: "火は夜半に消える",
                                            .beforeDawn: "火は夜明けの前に消える"]
        var rows = 0
        for fuel in stride(from: 1_800, through: 43_200, by: 5_400) {
            for pile in [0, 3, 12] {
                for stock in [0, 4] {
                    for tended in [false, true] {
                        for offset in [Int64(0), 9_000, 30_000] {
                            var w = rig.factory.newWorld(seed: 1)
                            let fire = campfire(&w, fuelSeconds: fuel, pile: pile)
                            setStock(&w, stock, rig.content)
                            member(&w, "person.test_a", dx: 1)
                            if tended { w.people["person.test_a"]?.assignment = .tendHearth(placement: fire) }
                            dusk(&w, offset: offset)
                            rows += 1
                            let f = frame(b, w)
                            let g = try XCTUnwrap(f.fireGauge)
                            let place = try XCTUnwrap(w.placements.items[fire])
                            let entry = try XCTUnwrap(b.fireGauge(of: place, w))
                            XCTAssertEqual(g.outlook, entry.outlook)
                            XCTAssertEqual(g.level, entry.level)
                            XCTAssertEqual(g.level, Hearths.level(of: place, rig.content))
                            XCTAssertEqual(f.clock.fireOutlook, g.outlook, "日没の帯")
                            let cell = place.at.point
                            var known = w.knowledge.mapKnown[.surface] ?? GridBitset(size: w.map[.surface]!.size)
                            known[cell] = true
                            w.knowledge.mapKnown[.surface] = known
                            XCTAssertEqual(b.footCard(w, at: cell)?.fire?.now, g.outlook, "足元カード")
                            let wrap = b.dayWrap(w).outlook
                            XCTAssertEqual(wrap, texts[g.outlook], "夜の締めの火の候補 \(g.outlook)")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(rows, 100)
    }

    /// 番がいれば蓄えの薪も見込みに入る(実際の fillPile と同じ)。足元カードも同じ値になる。
    func testTendedFireCountsStockEverywhere() throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        var w = rig.factory.newWorld(seed: 1)
        let fire = campfire(&w, fuelSeconds: 7_200, pile: 0)
        member(&w, "person.test_a", dx: 1)
        dusk(&w)
        let without = try XCTUnwrap(frame(b, w).fireGauge).outlook
        setStock(&w, 12, rig.content)
        XCTAssertEqual(try XCTUnwrap(frame(b, w).fireGauge).outlook, without, "番がいなければ蓄えは見ない")
        w.people["person.test_a"]?.assignment = .tendHearth(placement: fire)
        let g = try XCTUnwrap(frame(b, w).fireGauge)
        XCTAssertNotEqual(g.outlook, without)
        XCTAssertEqual(frame(b, w).clock.fireOutlook, g.outlook)
    }

    // MARK: 2. 見込み = 実際(TEST-O11)

    struct Lcg {
        var s: UInt64
        mutating func next(_ n: Int) -> Int {
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((s >> 33) % UInt64(max(1, n)))
        }
    }

    func furnace(_ w: inout WorldState, hot: Bool, charcoal: Int) {
        let id = w.newEntityID()
        var p = Placement(id: id, kind: .module("furnace"), at: at(w, -3, 3), facing: .north,
                          origin: ProvenanceLedger.unknownOrigin, status: .running)
        var m = ModuleRuntime(design: nil, step: nil)
        var h = HearthState()
        h.heat = hot ? 1_250_000 : 100_000
        h.lit = hot
        m.hearth = h
        if charcoal > 0 { m.input = [StockEntry(stuff: .item("charcoal"), quantity: charcoal)] }
        p.module = m
        w.placements.items[id] = p
    }

    /// 夜明けの世界から直接読んだ答え(forecast を通さない)。
    func actualAnswer(before: WorldState, after: WorldState, content: ContentDB, fire: EntityID?)
        -> (fire: SleepForecast.FireAtDawn?, furnace: SleepForecast.FurnaceAtDawn?)
    {
        var f: SleepForecast.FireAtDawn?
        if let fire, let p = before.placements.items[fire], Hearths.level(of: p, content) != .out {
            let s = after.placements.items[fire].flatMap { Hearths.state($0, content) }
            f = (s?.lit == true && (s?.fuel ?? 0) > 0) ? .holds : .dies
        }
        let hot = before.placements.sortedIDs.filter { id in
            guard let p = before.placements.items[id], FurnaceHeat.def(p, content) != nil else { return false }
            return FurnaceHeat.isHot(p, content)
        }
        var fu: SleepForecast.FurnaceAtDawn?
        if !hot.isEmpty {
            fu = hot.allSatisfy { after.placements.items[$0].map { FurnaceHeat.isHot($0, content) } ?? false } ? .stays : .cools
        }
        return (f, fu)
    }

    func nightCount() -> Int {
        ProcessInfo.processInfo.environment["REFORGE_O11_NIGHTS"].flatMap(Int.init) ?? 300
    }

    func testForecastMatchesActualNights() async throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        let started = Date()
        let nights = nightCount()
        var mismatches: [String] = []
        var holds = 0, dies = 0, stays = 0, cools = 0
        let only = ProcessInfo.processInfo.environment["REFORGE_O11_ONLY"].flatMap(Int.init)
        for i in (only.map { [$0] } ?? Array(0..<nights)) {
            var r = Lcg(s: UInt64(i) &* 7919 &+ 17)
            var w = rig.factory.newWorld(seed: UInt64(i) + 1)
            member(&w, "person.test_a", dx: 1)
            let fuel = r.next(10) == 0 ? 0 : (1 + r.next(43_200))
            let pile0 = r.next(13)
            let fire = campfire(&w, fuelSeconds: fuel, pile: pile0)
            let shelters = r.next(4)
            for k in 0..<shelters {
                let sid = w.newEntityID()
                var p = Placement(id: sid, kind: .structure("structure.shelter"), at: at(w, 3 + k - 1, 5), facing: .north,
                                  origin: ProvenanceLedger.unknownOrigin, status: .running)
                p.structure = StructureRuntime()
                w.placements.items[sid] = p
            }
            let stock0 = r.next(3) == 0 ? 0 : r.next(10)
            setStock(&w, stock0, rig.content)
            let tended = r.next(2) == 0
            if tended { w.people["person.test_a"]?.assignment = .tendHearth(placement: fire) }
            if r.next(2) == 0 { furnace(&w, hot: r.next(4) != 0, charcoal: r.next(9)) }
            let offset = Int64(r.next(960)) * 15
            dusk(&w, offset: offset)
            if r.next(3) == 0 { w.clock.phase = .nightWork }

            var actual = w
            let report = rig.simulation.apply(.time(.sleep), to: &actual)
            XCTAssertNil(report.rejection)
            let want = actualAnswer(before: w, after: actual, content: rig.content, fire: fire)

            // 毎晩: 夜明けの世界から作った答え。5 晩に 1 晩: 画面が引く GameHost.sleepForecast(もう 1 夜ぶん回す)
            var got = SleepForecast.make(before: w, after: actual, builder: b)
            if i % 5 == 0 {
                let host = GameHost(simulation: rig.simulation, world: w)
                let viaHost = await host.sleepForecast()
                XCTAssertEqual(viaHost, got, "night \(i): GameHost の見込みと夜明けの世界から作った答え")
                if let viaHost { got = viaHost }
            }
            if got.fire != want.fire || got.furnace != want.furnace {
                mismatches.append("night \(i): got \(got) want \(want)")
            }
            switch want.fire { case .holds?: holds += 1; case .dies?: dies += 1; default: break }
            switch want.furnace { case .stays?: stays += 1; case .cools?: cools += 1; default: break }
            // ゲージの 4 段目 ⇔ 夜明けまで持つ(点いている火について)
            if want.fire != nil {
                let g = try XCTUnwrap(frame(b, w).fireGauge)
                if (g.outlook == .throughNight) != (want.fire == .holds) {
                    mismatches.append("night \(i): outlook \(g.outlook) vs actual \(String(describing: want.fire)) fuel \(fuel) pile \(pile0) stock \(stock0) shelters \(shelters) offset \(offset) tended \(tended) phase \(w.clock.phase)")
                }
            }
        }
        let secs = Date().timeIntervalSince(started)
        print("[TEST-O11] nights \(nights) seconds \(Int(secs)) holds \(holds) dies \(dies) stays \(stays) cools \(cools)")
        if only == nil {  // 全部の答えが出ていること(1 晩だけ試すときは見ない)
            XCTAssertGreaterThan(holds, 0)
            XCTAssertGreaterThan(dies, 0)
            XCTAssertGreaterThan(stays, 0)
            XCTAssertGreaterThan(cools, 0)
        }
        XCTAssertEqual(mismatches, [], "最初の 10 件: \(mismatches.prefix(10))")
    }

    /// 境目: 見込みが「夜明けまで持つ」に変わる燃料(秒)を見込みの側で探し、その前後 1 秒ずつを実際に寝て確かめる。
    /// 日没の 4 時間後の火(番なし・番あり)。見込みの境目と実際の境目は同じ燃料でなければならない。
    func testBoundaryAgreesWithActual() throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        func build(_ fuel: Int, tended: Bool) -> (WorldState, EntityID) {
            var w = rig.factory.newWorld(seed: 3)
            member(&w, "person.test_a", dx: 1)
            let fire = campfire(&w, fuelSeconds: fuel, pile: 0)
            if tended { w.people["person.test_a"]?.assignment = .tendHearth(placement: fire) }
            dusk(&w, offset: 14_400)
            return (w, fire)
        }
        func outlookHolds(_ fuel: Int, tended: Bool) throws -> Bool {
            let (w, _) = build(fuel, tended: tended)
            return try XCTUnwrap(frame(b, w).fireGauge).outlook == .throughNight
        }
        func actualHolds(_ fuel: Int, tended: Bool) -> Bool {
            let (w, fire) = build(fuel, tended: tended)
            var after = w
            _ = rig.simulation.apply(.time(.sleep), to: &after)
            let s = after.placements.items[fire].flatMap { Hearths.state($0, rig.content) }
            return s?.lit == true && (s?.fuel ?? 0) > 0
        }
        for tended in [false, true] {
            var lo = 1_000, hi = 43_200   // lo: 持たない、hi: 持つ
            XCTAssertFalse(try outlookHolds(lo, tended: tended))
            XCTAssertTrue(try outlookHolds(hi, tended: tended))
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if try outlookHolds(mid, tended: tended) { hi = mid } else { lo = mid }
            }
            var wrong: [Int] = []
            for fuel in [hi - 600, hi - 3, hi - 2, hi - 1, hi, hi + 1, hi + 2, hi + 3, hi + 600] where fuel > 0 && fuel <= 43_200 {
                if try outlookHolds(fuel, tended: tended) != actualHolds(fuel, tended: tended) { wrong.append(fuel) }
            }
            XCTAssertEqual(wrong, [], "tended \(tended): 見込みの境目 \(hi) 秒。食い違う燃料(秒)")
        }
    }

    // MARK: 3. 世界を変えない

    func testQueriesDoNotChangeWorldOrRandomness() async throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        var w = rig.factory.newWorld(seed: 5)
        let fire = campfire(&w, fuelSeconds: 20_000)
        member(&w, "person.test_a", dx: 1)
        furnace(&w, hot: true, charcoal: 3)
        dusk(&w, offset: 3_000)
        _ = fire
        let before = w
        _ = frame(b, w)
        XCTAssertEqual(w, before)
        let queried = GameHost(simulation: rig.simulation, world: w)
        let plain = GameHost(simulation: rig.simulation, world: w)
        let hostBefore = await queried.world
        _ = await queried.sleepForecast()
        _ = await queried.sleepForecast()
        let hostAfter = await queried.world
        XCTAssertEqual(hostBefore, hostAfter)
        _ = await queried.send(.time(.sleep))
        _ = await plain.send(.time(.sleep))
        let a = await queried.world
        let c = await plain.world
        XCTAssertEqual(a, c, "呼んだ後の次の一歩が、呼ばなかった世界と一致")
        let day = rig.factory.newWorld(seed: 5)
        let dayHost = GameHost(simulation: rig.simulation, world: day)
        let none = await dayHost.sleepForecast()
        XCTAssertNil(none, "昼は nil")
    }

    // MARK: 4. ゲージの出し入れ

    func testGaugeAppearsAndGoesOut() throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        var w = rig.factory.newWorld(seed: 1)
        XCTAssertNil(frame(b, w).fireGauge, "焚き火が無い")
        let fire = campfire(&w, fuelSeconds: 0, complete: false)
        XCTAssertNil(frame(b, w).fireGauge, "建造中")
        w.placements.items[fire]?.status = .running
        w.placements.items[fire]?.structure = StructureRuntime()  // 火床の状態はまだ書かれていない(初めは消えている)
        XCTAssertNil(frame(b, w).fireGauge, "最初の火が点く前")
        w.placements.items[fire]?.structure?.hearth = HearthState(fuel: 60_000, lit: true)
        let lit = try XCTUnwrap(frame(b, w).fireGauge)
        XCTAssertGreaterThanOrEqual(lit.level, .smoldering)
        w.placements.items[fire]?.structure?.hearth = HearthState(fuel: 0, lit: false)
        XCTAssertEqual(frame(b, w).fireGauge?.level, .out, "消えても一度持った火は出す")
    }

    // MARK: 5. 申し出

    func base(_ rig: TestRig, fuel: Int = 30_000) -> (WorldState, EntityID) {
        var w = rig.factory.newWorld(seed: 1)
        let fire = campfire(&w, fuelSeconds: fuel)
        member(&w, "person.test_a", dx: 1)
        member(&w, "person.test_b", dx: 2)
        member(&w, "person.test_c", dx: 3)
        dusk(&w)
        return (w, fire)
    }

    func testOfferConditions() throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        var (w, fire) = base(rig)
        // (a) 昼は 0 個
        var day = w
        day.clock.phase = .day
        XCTAssertEqual(frame(b, day).offers, [])
        // (b) 日没で 1 個。order の先頭の人
        let first = frame(b, w).offers
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].person, "person.test_b")
        XCTAssertEqual(first[0].kind, .tendFire)
        XCTAssertEqual(first[0].command, .crew(.assign(person: "person.test_b", assignment: .tendHearth(placement: fire))))
        XCTAssertNil(first[0].line, "一言の無い人")
        // 夜作業でも出る
        var night = w
        night.clock.phase = .nightWork
        XCTAssertEqual(frame(b, night).offers.count, 1)
        // order の次へ: 地図にいない・亡くなった・番に付いている・仲間でない人は出ない
        var x = w
        x.people["person.test_b"]?.position = nil
        XCTAssertEqual(frame(b, x).offers.first?.person, "person.test_a")
        XCTAssertEqual(frame(b, x).offers.first?.line, "line a")
        x.people["person.test_a"]?.presence = .dead(at: .zero, record: nil)
        XCTAssertEqual(frame(b, x).offers.first?.person, "person.test_c")
        x.people["person.test_c"]?.presence = .met(at: .zero)
        XCTAssertEqual(frame(b, x).offers, [])
        // 手が先を満たさなければ出ない
        let strict = TestRig(content: try content(handFirst: true))
        let sb = FrameBuilder(content: strict.content)
        var (sw, _) = base(strict)
        XCTAssertEqual(frame(sb, sw).offers, [])
        sw.knowledge.handDone.insert("family.test.tend")
        XCTAssertEqual(frame(sb, sw).offers.first?.person, "person.test_b")
        // (c) 火が消えている・番がいる日没は 0 個
        var out = w
        out.placements.items[fire]?.structure?.hearth = HearthState()
        XCTAssertEqual(frame(b, out).offers, [])
        var tended = w
        tended.people["person.test_a"]?.assignment = .tendHearth(placement: fire)
        XCTAssertEqual(frame(b, tended).offers, [])
        // 申し出の定義が無い内容は出さない(6)
        let old = TestRig(content: try content(offer: false))
        XCTAssertEqual(frame(FrameBuilder(content: old.content), w).offers, [])
        w.people["person.test_b"]?.assignment = .tendHearth(placement: fire)
        XCTAssertEqual(frame(b, w).offers, [], "番に付いた人がいれば番がいる")
    }

    func testOfferAlwaysAcceptedAndDisappears() throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        var (w, fire) = base(rig)
        let offer = try XCTUnwrap(frame(b, w).offers.first)
        let r = rig.simulation.apply(offer.command, to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertTrue(Hearths.isTended(fire, in: w))
        XCTAssertEqual(frame(b, w).offers, [])
    }

    func testEveryShownOfferIsAcceptedAcrossNights() throws {
        let rig = TestRig(content: try content())
        let b = FrameBuilder(content: rig.content)
        var shown = 0
        for i in 0..<nightCount() {
            var r = Lcg(s: UInt64(i) &* 104_729 &+ 3)
            var w = rig.factory.newWorld(seed: UInt64(i) + 1)
            let fire = campfire(&w, fuelSeconds: r.next(4) == 0 ? 0 : 1 + r.next(43_200), pile: r.next(13))
            let ids: [PersonID] = ["person.test_a", "person.test_b", "person.test_c"]
            for (k, id) in ids.enumerated() {
                switch r.next(5) {
                case 0: member(&w, id, dx: k + 1, onMap: false)
                case 1: member(&w, id, dx: k + 1, presence: .dead(at: .zero, record: nil))
                case 2: member(&w, id, dx: k + 1, presence: .met(at: .zero))
                default: member(&w, id, dx: k + 1)
                }
                if r.next(6) == 0 { w.people[id]?.assignment = .tendHearth(placement: fire) }
                if r.next(6) == 0 { w.people[id]?.assignment = .rest }
            }
            dusk(&w, offset: Int64(r.next(960)) * 15)
            if r.next(2) == 0 { w.clock.phase = .nightWork }
            let offers = frame(b, w).offers
            XCTAssertLessThanOrEqual(offers.count, 1)
            for offer in offers {
                shown += 1
                var after = w
                let rep = rig.simulation.apply(offer.command, to: &after)
                XCTAssertNil(rep.rejection, "night \(i): 見せた申し出が断られた")
                XCTAssertTrue(Hearths.isTended(fire, in: after))
                XCTAssertEqual(frame(b, after).offers, [])
            }
        }
        XCTAssertGreaterThan(shown, 0)
    }

    /// (f) 押さずに寝れば、世界は申し出が無かった世界と同じ(自動では付かない)。
    func testIgnoringOfferChangesNothing() throws {
        let with = TestRig(content: try content())
        let without = TestRig(content: try content(offer: false))
        let (w, fire) = base(with)
        XCTAssertEqual(frame(FrameBuilder(content: with.content), w).offers.count, 1)
        var a = w
        var c = w
        _ = with.simulation.apply(.time(.sleep), to: &a)
        _ = without.simulation.apply(.time(.sleep), to: &c)
        XCTAssertEqual(a, c)
        XCTAssertFalse(Hearths.isTended(fire, in: a))
        XCTAssertEqual(frame(FrameBuilder(content: with.content), a).offers, [], "昼になって消える")
    }

    // MARK: 6. 古い内容

    func testOldContentHasNoGaugeNoOffers() throws {
        let rig = TestRig(content: try TestContent.publicOnly())
        let b = FrameBuilder(content: rig.content)
        var w = rig.factory.newWorld(seed: 1)
        XCTAssertNil(frame(b, w).fireGauge)
        XCTAssertEqual(frame(b, w).offers, [])
        dusk(&w)
        XCTAssertNil(frame(b, w).fireGauge)
        XCTAssertEqual(frame(b, w).offers, [])
    }

    // MARK: 7. 保存

    func testSaveHasNoScreenKeys() throws {
        let rig = TestRig(content: try content())
        var (w, _) = base(rig)
        w.clock.phase = .dusk
        let data = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: w, content: []))
        let text = String(decoding: data, as: UTF8.self)
        for key in ["offers", "fireGauge", "sleepForecast", "tendOffer"] {
            XCTAssertFalse(text.contains(key), key)
        }
    }

    // MARK: 8. 文

    func testNoExplanationStrings() throws {
        let rig = TestRig(content: try content())
        let with = FrameBuilder(content: rig.content)
        let without = FrameBuilder(content: try content(offer: false))
        let (w, _) = base(rig)
        var a = FrameText.allStrings(frame(with, w))
        let c = FrameText.allStrings(frame(without, w))
        for s in c { if let i = a.firstIndex(of: s) { a.remove(at: i) } }
        // 増えるのは、人の名前(認識の層を通した)と、押したときの命令の中の人の ID(表示しない)だけ。説明の文は無い
        a.removeAll { $0 == "person.test_b" }
        let p = Perceiver(content: rig.content, world: w)
        XCTAssertEqual(a, [p.name(Subject.person("person.test_b"))])
        let gaugeOnly = frame(without, w)
        XCTAssertNotNil(gaugeOnly.fireGauge, "ゲージは文字列を持たない(段と見込みの値だけ)")
    }
}
