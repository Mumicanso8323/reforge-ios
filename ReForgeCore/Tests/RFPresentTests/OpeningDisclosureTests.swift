import Foundation
import RFContent
import RFFailure
import RFKernel
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFTime
import RFWorld
import XCTest

/// U20: 序盤の骨組み(W-01 表示の開示と時計の保留・W-14 始まりの時刻・W-11 寝る見込み)。
/// TEST-O1(時計と開示の部分)・TEST-O2(止まっている間は開示が増えない)・TEST-O11(見込み = 実際)・TEST-O16。
final class OpeningDisclosureTests: XCTestCase {
    var base: ContentDB!

    override func setUpWithError() throws { base = try TestContent.publicOnly() }

    /// Day 0・日没の 4 時間前・時計を止めて始め、足元の行為 1 つと、門の付いた要素を持つコンテンツ。
    func openingContent() throws -> ContentDB {
        var db = base!
        db.interactions.removeAll()
        let json = """
        {
          "interactions": [
            { "id": "interaction.test.open.first", "target": { "terrain": { "tag": "ground" } }, "seconds": 600,
              "hold": false, "yields": [] }
          ],
          "uiGates": [
            { "id": "notes.trials", "when": { "known": { "expr": "fact.test.k" } }, "latch": "knowledge" },
            { "id": "crew.assign", "when": { "known": { "expr": "fact.test.w" } }, "latch": "world" },
            { "id": "base.build", "when": { "known": { "expr": "fact.test.live" } } }
          ]
        }
        """
        try ContentLoader.apply(json: Data(json.utf8), to: &db)
        db.start.clock = StartClockDef(day: 0, hoursBeforeDusk: 4, held: true)
        return db
    }

    func noahAt(_ w: WorldState) -> WorldPoint { w.people[w.people.order[0]]!.position! }

    func firstAction(_ w: WorldState) -> Command {
        .exploration(.interact(interaction: "interaction.test.open.first", at: noahAt(w), holding: false))
    }

    // MARK: - W-14 始まりの時刻・W-01 時計の保留

    func testStartsDayZeroFourHoursBeforeDuskWithClockHeld() throws {
        let rig = TestRig(content: try openingContent())
        let w = rig.factory.newWorld(seed: 1)
        XCTAssertEqual(w.clock.day, 0)
        XCTAssertTrue(w.clock.held)
        XCTAssertEqual(TimeSystem.dayRemainingPermille(w.clock, rig.content.clock), 500, "昼 8 時間の残り 4 時間")
        XCTAssertEqual(TimeSystem.dayRemainingRealSeconds(w.clock, rig.content.clock), 90, "日没まで 90 秒")
        let f = FrameBuilder(content: rig.content).build(w, revision: 0, previous: nil, report: nil)
        XCTAssertTrue(f.clock.held)
        XCTAssertFalse(f.clock.running)
    }

    func testDefaultStartIsUnchanged() throws {
        let rig = TestRig(content: base)
        let w = rig.factory.newWorld(seed: 1)
        XCTAssertEqual(w.clock.day, 1)
        XCTAssertEqual(w.clock.now, .zero)
        XCTAssertFalse(w.clock.held)
    }

    /// TEST-O2 の前半: 何もしないと、10 分待っても時計も開示も動かない(画面の引き直しも起きない)。
    func testNothingMovesWhileHeld() async throws {
        let rig = TestRig(content: try openingContent())
        var w = rig.factory.newWorld(seed: 3)
        let before = w
        for _ in 0..<6000 { _ = rig.simulation.advance(&w, realSeconds: 0.1) }
        XCTAssertEqual(w, before)
        let host = GameHost(simulation: rig.simulation, world: before)
        let rev = await host.frame.revision
        for _ in 0..<100 { _ = await host.tick(realSeconds: 0.1) }
        let after = await host.frame.revision
        XCTAssertEqual(after, rev, "止まっている間は Frame を作り直さない")
    }

    func testWalkingKeepsHoldAndFirstActionReleasesIt() throws {
        let rig = TestRig(content: try openingContent())
        var w = rig.factory.newWorld(seed: 1)
        _ = rig.simulation.apply(.crew(.walk(to: noahAt(w))), to: &w)
        XCTAssertTrue(w.clock.held, "歩くだけでは時計は動かない")
        let r = rig.simulation.apply(firstAction(w), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertFalse(w.clock.held)
        let t = w.clock.now
        _ = rig.simulation.advance(&w, realSeconds: 1)
        XCTAssertGreaterThan(w.clock.now, t, "動き出した後は昼が進む")
    }

    // MARK: - W-01 開示

    func testLatchedGateStaysOpenAndUnlatchedFollowsCondition() throws {
        let rig = TestRig(content: try openingContent())
        let b = FrameBuilder(content: rig.content)
        var w = rig.factory.newWorld(seed: 1)
        XCTAssertFalse(b.unlocks(w).isOpen("notes.trials"))
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.k")
        ctx.learn("fact.test.live")
        w = ctx.world
        _ = rig.simulation.apply(firstAction(w), to: &w)
        XCTAssertEqual(w.knowledge.disclosed["notes.trials"], .knowledge)
        XCTAssertNil(w.knowledge.disclosed["base.build"], "latch の無い門は記録しない")
        w.knowledge.facts["fact.test.k"] = nil
        w.knowledge.facts["fact.test.live"] = nil
        let u = b.unlocks(w)
        XCTAssertTrue(u.isOpen("notes.trials"), "一度開いたら開いたまま")
        XCTAssertFalse(u.isOpen("base.build"), "latch の無い門は今の条件に従う")
    }

    func testTabsAreDerivedFromGatedChildren() throws {
        let rig = TestRig(content: try openingContent())
        let b = FrameBuilder(content: rig.content)
        var w = rig.factory.newWorld(seed: 1)
        var u = b.unlocks(w)
        XCTAssertFalse(u.isOpen(UIElements.tabNotes))
        XCTAssertFalse(u.isOpen(UIElements.tabCrew))
        XCTAssertFalse(u.isOpen(UIElements.tabBase))
        XCTAssertTrue(u.isOpen(UIElements.tabDesign), "配下に門が無ければ今どおり出す")
        XCTAssertTrue(u.gated.contains(UIElements.tabNotes))
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.k")
        w = ctx.world
        u = b.unlocks(w)
        XCTAssertTrue(u.isOpen(UIElements.tabNotes))
        XCTAssertTrue(u.open.contains(UIElements.tabNotes))
        XCTAssertFalse(u.isOpen(UIElements.tabCrew))
    }

    /// TEST-O16: 知識で開いたものは巻き戻しても残り、世界で開いたものは巻き戻した先に従う。
    func testRewindCarriesOnlyKnowledgeDisclosures() throws {
        let rig = TestRig(content: try openingContent())
        let dawn = rig.factory.newWorld(seed: 1)
        var failed = dawn
        failed.knowledge.disclosed = ["notes.trials": .knowledge, "crew.assign": .world]
        var dawnWithWorld = dawn
        dawnWithWorld.knowledge.disclosed = ["base.lines": .world]
        let w = MemoryCarry.rewind(failed: failed, dawn: dawnWithWorld, content: rig.content)
        XCTAssertEqual(w.knowledge.disclosed, ["notes.trials": .knowledge, "base.lines": .world])
    }

    // MARK: - 保存

    func testOldSavesWithoutNewKeysStillDecodeAndKeyOrderIsStable() throws {
        let rig = TestRig(content: try openingContent())
        var w = rig.factory.newWorld(seed: 1)
        w.knowledge.disclosed = ["notes.trials": .knowledge, "crew.assign": .world, "base.lines": .world]
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let a = try enc.encode(w)
        XCTAssertEqual(try JSONDecoder().decode(WorldState.self, from: a), w)
        XCTAssertEqual(try enc.encode(try JSONDecoder().decode(WorldState.self, from: a)), a, "並びが固まる")
        // 古い保存: held と disclosed のキーが無い
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: a) as? [String: Any])
        var clock = try XCTUnwrap(obj["clock"] as? [String: Any])
        clock["held"] = nil
        obj["clock"] = clock
        var know = try XCTUnwrap(obj["knowledge"] as? [String: Any])
        know["disclosed"] = nil
        obj["knowledge"] = know
        let old = try JSONDecoder().decode(WorldState.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertFalse(old.clock.held)
        XCTAssertEqual(old.knowledge.disclosed, [:])
    }

    // MARK: - W-11 寝る見込み = 実際(TEST-O11 の土台)

    func testSleepForecastMatchesActualAndDoesNotTouchWorld() throws {
        let rig = TestRig(content: base)
        for seed in UInt64(1)...20 {
            var w = rig.factory.newWorld(seed: seed)
            XCTAssertNil(rig.simulation.forecastSleep(w), "昼は見込みなし")
            _ = rig.playDay(&w, dt: Double(seed % 5 + 1) / 10)
            let before = w
            let fc = try XCTUnwrap(rig.simulation.forecastSleep(w))
            XCTAssertEqual(w, before, "本物の世界と乱数を進めない")
            var actual = w
            let r = rig.simulation.apply(.time(.sleep), to: &actual)
            XCTAssertEqual(fc.world, actual, "seed \(seed)")
            XCTAssertEqual(fc.report.events, r.events)
        }
    }
}
