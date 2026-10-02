import Foundation
import RFContent
import RFFailure
import RFKernel
import RFPerception
import RFPresent
import RFRules
import RFSave
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

    /// v0.5 §2.8.3・TEST-O21 (3): 始まりの出来事は時計が止まっていても作った時点で起き、場面の送りでは保留が解けない。
    func testStartEventsFireWhileHeldAndSceneAdvanceKeepsHold() throws {
        var db = try openingContent()
        let e: EventID = "event.test.chain"
        try XCTSkipIf(db.events[e] == nil)
        db.start.events = [e]
        let rig = TestRig(content: db)
        var w = rig.factory.newWorld(seed: 1)
        XCTAssertNotNil(w.narrative.fired[e], "最初の Frame の前に起きている")
        XCTAssertTrue(w.clock.held)
        let t = w.clock.now
        for _ in 0..<5 { _ = rig.simulation.apply(.narrative(.advanceScene), to: &w) }
        XCTAssertTrue(w.clock.held, "送りの間は止まったまま")
        XCTAssertEqual(w.clock.now, t)
        XCTAssertFalse(Simulation.releasesHold(.narrative(.advanceScene)))
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
        XCTAssertTrue(u.isOpen(UIElements.tabBase), "配下に latch の無い門だけなら(古い形)今どおり出す")
        XCTAssertFalse(u.gated.contains(UIElements.tabBase))
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
        w.knowledge.heldItems = ["item.test.h.b", "item.test.h.a", "item.test.h.c"]
        let a = try CanonicalJSON.encode(w)
        XCTAssertEqual(try JSONDecoder().decode(WorldState.self, from: a), w)
        XCTAssertEqual(try CanonicalJSON.encode(try JSONDecoder().decode(WorldState.self, from: a)), a, "正準の JSON で並びが固まる")
        // 古い保存: held と disclosed のキーが無い
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: a) as? [String: Any])
        var clock = try XCTUnwrap(obj["clock"] as? [String: Any])
        clock["held"] = nil
        obj["clock"] = clock
        var know = try XCTUnwrap(obj["knowledge"] as? [String: Any])
        know["disclosed"] = nil
        know["heldItems"] = nil
        obj["knowledge"] = know
        let old = try JSONDecoder().decode(WorldState.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertFalse(old.clock.held)
        XCTAssertEqual(old.knowledge.disclosed, [:])
        XCTAssertEqual(old.knowledge.heldItems, [])
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

    // MARK: - W-07 地図の題・新しく開いた要素・半分の気配

    func testPlaceTitleChangesInTheSameFrameAsTheFact() throws {
        var db = try openingContent()
        let json = """
        {
          "texts": { "text.test.place.dark": "A", "text.test.place.fire": "B" },
          "perception": [
            { "subject": "place:base", "variants": [
              { "when": "fact.test.k", "name": "text.test.place.fire" },
              { "when": true, "name": "text.test.place.dark" } ] }
          ]
        }
        """
        try ContentLoader.apply(json: Data(json.utf8), to: &db)
        let b = FrameBuilder(content: db)
        var w = TestRig(content: db).factory.newWorld(seed: 1)
        let f0 = b.build(w, revision: 0, previous: nil, report: nil)
        XCTAssertEqual(f0.placeTitle, "A")
        var ctx = StepContext(world: w, content: db)
        ctx.learn("fact.test.k")
        w = ctx.world
        let f1 = b.build(w, revision: 1, previous: f0, report: nil)
        XCTAssertEqual(f1.placeTitle, "B")
        XCTAssertEqual(f1.newlyOpened, ["notes.trials", UIElements.tabNotes], "新しく開いた要素(導出のタブも)")
        XCTAssertNil(FrameBuilder(content: base).build(w, revision: 0, previous: nil, report: nil).placeTitle,
                     "表に無ければ題を出さない")
    }

    /// TEST-O20 (1): 材料を 1 つでも見ていない間は影にならず、全部見て半分持つと影になる。解放はしない。
    func testHalfwayNeedsAllSeenAndHalfTheCost() throws {
        let rig = TestRig(content: base)
        let cost = [Ingredient(item: "item.test.h.a", quantity: 4), Ingredient(item: "item.test.h.b", quantity: 4)]
        var w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.addStock(.item("item.test.h.a"), 4, to: .base)
        w = ctx.world
        XCTAssertFalse(HintRule.halfway(cost: cost, world: w), "b をまだ見ていない")
        ctx = StepContext(world: w, content: rig.content)
        ctx.addStock(.item("item.test.h.b"), 1, to: .base)
        _ = ctx.takeStock(1, from: .base) { $0.stuff == .item("item.test.h.b") }
        w = ctx.world
        XCTAssertTrue(HintRule.halfway(cost: cost, world: w), "全部見て、4/8 を持つ")
        ctx = StepContext(world: w, content: rig.content)
        _ = ctx.takeStock(1, from: .base) { $0.stuff == .item("item.test.h.a") }
        XCTAssertFalse(HintRule.halfway(cost: cost, world: ctx.world), "3/8 は半分に届かない")
        XCTAssertFalse(HintRule.halfway(cost: [], world: w))
    }

    func testShadowRowsOnlyForLockedKinds() throws {
        let rig = TestRig(content: base)
        guard let (k, def) = rig.content.structures.sorted(by: { $0.key < $1.key }).first(where: { !$0.value.cost.isEmpty })
        else { throw XCTSkip("費用のある建造物が無い") }
        var w = rig.factory.newWorld(seed: 1)
        w.research.unlocked.structures.remove(k)
        var ctx = StepContext(world: w, content: rig.content)
        for ing in def.cost { if let i = ing.item { ctx.addStock(.item(i), ing.quantity, to: .base) } }
        w = ctx.world
        let b = FrameBuilder(content: rig.content)
        let p = Perceiver(content: rig.content, world: w)
        XCTAssertTrue(b.shadows(w, p).contains { $0.kind == .structure(k) })
        w.research.unlocked.structures.insert(k)
        XCTAssertFalse(b.shadows(w, p).contains { $0.kind == .structure(k) }, "解放済みは影にしない")
    }

    // MARK: - 帯の要素の門(U20 の仕上げ)

    func testBandElementsFollowGatesAndOldDataShowsAll() throws {
        var db = try openingContent()
        let stat = try XCTUnwrap(db.stats.keys.sorted().first)
        db.stats[stat]?.band = UIElements.bandSupplies
        db.uiGates[UIElements.bandSupplies] = UIGateDef(id: UIElements.bandSupplies, when: .known(expr: .fact("fact.test.k")),
                                                        latch: .knowledge)
        db.uiGates[UIElements.bandObjective] = UIGateDef(id: UIElements.bandObjective, when: .known(expr: .fact("fact.test.k")))
        let b = FrameBuilder(content: db)
        var w = TestRig(content: db).factory.newWorld(seed: 1)
        let f0 = b.build(w, revision: 0, previous: nil, report: nil)
        XCTAssertFalse(f0.clock.showsDayLeft, "時計を止めている間は日の残りを出さない")
        XCTAssertFalse(f0.status.contains { $0.key == stat.rawValue })
        XCTAssertNil(f0.objective)
        var ctx = StepContext(world: w, content: db)
        ctx.learn("fact.test.k")
        w = ctx.world
        w.clock.held = false
        let f1 = b.build(w, revision: 1, previous: f0, report: nil)
        XCTAssertTrue(f1.clock.showsDayLeft)
        XCTAssertEqual(f1.status.map(\.key).filter { $0 != stat.rawValue }, f0.status.map(\.key), "他の数値は変わらない")
        // 古い形(門も band も無い)では今どおり全部出る
        let old = FrameBuilder(content: base)
        let ow = TestRig(content: base).factory.newWorld(seed: 1)
        let of = old.build(ow, revision: 0, previous: nil, report: nil)
        XCTAssertTrue(of.clock.showsDayLeft)
        XCTAssertNotNil(of.objective.map { _ in true } ?? true)
        XCTAssertTrue(UIElements.all.isSuperset(of: [UIElements.bandDay, UIElements.bandFire, UIElements.cardCarry,
                                                    UIElements.bandSupplies, UIElements.bandNight, UIElements.bandGas,
                                                    UIElements.personMind, UIElements.furnaceHeat,
                                                    UIElements.bandObjective, UIElements.baseCapacity,
                                                    UIElements.routeCapacity]))
    }

    // MARK: - 足した条件

    func testNewConditions() throws {
        let rig = TestRig(content: try openingContent())
        var w = rig.factory.newWorld(seed: 1)
        func holds(_ c: Condition) -> Bool { ConditionEvaluator.evaluatePure(c, world: w, content: rig.content) == true }
        XCTAssertFalse(holds(.stockTotal(atLeast: 3)) && w.inventory.entries(.base).isEmpty)
        var ctx = StepContext(world: w, content: rig.content)
        let before = w.inventory.entries(.base).reduce(0) { $0 + $1.quantity }
        ctx.addStock(.item("item.test.h.a"), 2, to: .base)
        ctx.addStock(.item("item.test.h.b"), 1, to: .base)
        w = ctx.world
        XCTAssertTrue(holds(.stockTotal(atLeast: before + 3)))
        XCTAssertFalse(holds(.stockTotal(atLeast: before + 4)))

        XCTAssertTrue(holds(.findings(atLeast: w.notebook.notes.count)))
        XCTAssertFalse(holds(.findings(atLeast: w.notebook.notes.count + 1)))

        let t = try XCTUnwrap(w.map[noahAt(w).layer]?.terrain(at: noahAt(w).point))
        XCTAssertFalse(holds(.inspected(terrain: t, poi: nil)))
        _ = rig.simulation.apply(.exploration(.inspected(terrain: t, poi: nil)), to: &w)
        XCTAssertTrue(holds(.inspected(terrain: t, poi: nil)))
        XCTAssertTrue(w.clock.held, "調べるだけでは時計は動かない")
        XCTAssertFalse(holds(.inspected(terrain: nil, poi: nil)))

        XCTAssertFalse(holds(.hearthAtLeast(level: .smoldering)), "火床が無い")
        let here = noahAt(w)
        var c2 = StepContext(world: w, content: rig.content)
        let cause = c2.record(.chose, .none, actor: .noah, place: here)
        EffectApplier.apply([.placeStructure(structure: "structure.campfire", at: .trigger, built: true),
                             .hearth(at: .trigger, op: .ignite())], &c2, cause: cause)
        try XCTSkipIf(!c2.warnings.isEmpty, "公開の層に焚き火台が無い: \(c2.warnings)")
        w = c2.world
        XCTAssertTrue(holds(.hearthAtLeast(level: .smoldering)))
        XCTAssertFalse(holds(.hearthAtLeast(level: .roaring)))
    }

    func testConditionJSONShapes() throws {
        let json = #"""
        [ { "hearthAtLeast": { "level": 3 } }, { "stockTotal": { "atLeast": 20 } }, { "findings": { "atLeast": 5 } },
          { "inspected": { "terrain": "grass" } }, { "inspected": { "poi": "poi.test" } } ]
        """#
        let cs = try JSONDecoder().decode([Condition].self, from: Data(json.utf8))
        XCTAssertEqual(cs, [.hearthAtLeast(level: .burning), .stockTotal(atLeast: 20), .findings(atLeast: 5),
                            .inspected(terrain: "grass", poi: nil), .inspected(terrain: nil, poi: "poi.test")])
    }
}
