import RFContent
import RFKernel
import RFMatter
import RFPresent
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// U17: 設計画面・ノート・資料の射影。
final class WorkbenchTests: XCTestCase {
    private let steps = [ProcessStep(.furnace, input: .charcoal)]

    private func world(_ rig: TestRig, furnace: Bool) -> WorldState {
        var ctx = StepContext(world: rig.factory.newWorld(seed: 3), content: rig.content)
        ctx.addStock(.matter(.ironOre(purity: Purity(percent: 30))), 6, to: .base)
        ctx.addStock(.item(.charcoal), 40, to: .base)
        ctx.world.research.unlocked.modules.formUnion([.millstone, .furnace, .quenchTank])
        if furnace {
            let id = ctx.world.newEntityID()
            let rec = ctx.record(.placed, .module(.furnace, id), actor: .noah)
            let at = ctx.world.map.spawn
            ctx.world.placements.items[id] = Placement(
                id: id, kind: .module(.furnace), at: WorldPoint(at.layer, GridPoint(at.point.x + 2, at.point.y + 2)),
                facing: .north, origin: rec, status: .running)
        }
        return ctx.world
    }

    private func ore(_ bench: DesignBench) throws -> StockSelector {
        try XCTUnwrap(bench.materials.first?.selector)
    }

    func testBenchListsUnlockedModulesStockAndMissingEquipment() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        let bench = b.designBench(in: world(rig, furnace: false))
        let furnace = try XCTUnwrap(bench.modules.first { $0.module == .furnace })
        XCTAssertEqual(furnace.name, "炉")
        XCTAssertNotNil(furnace.missing, "炉を置いていなければ、試せない理由の 1 行が付く")
        XCTAssertFalse(bench.modules.contains { $0.module == .anvil }, "解禁していない段は出さない")
        XCTAssertEqual(bench.materials.count, 1)
        XCTAssertEqual(bench.materials[0].quantity, 6)
        XCTAssertEqual(bench.materials[0].percent, 30, "ノアの手の見当")
        XCTAssertTrue(bench.additives.contains { $0.quantity == 40 })
        XCTAssertTrue(bench.plates.isEmpty)

        let ready = b.designBench(in: world(rig, furnace: true))
        XCTAssertNil(ready.modules.first { $0.module == .furnace }?.missing)
    }

    /// 試す → 試作の表(結果カードつき)・同じ並びの下書きには見込みが出る・札にすると札の一覧に載る。
    func testTrialDraftForecastAndPlate() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var w = world(rig, furnace: true)
        let sel = try ore(b.designBench(in: w))

        // 試す前の下書き: 段はあるが見込みは「？」
        let before = try XCTUnwrap(b.sheet(.draft(steps: steps, input: sel), in: w))
        XCTAssertEqual(before.rows.map(\.title), ["炉"])
        XCTAssertEqual(before.rows[0].step, 0)
        XCTAssertNil(before.rows[0].forecast)
        XCTAssertNil(before.expected)
        XCTAssertEqual(before.head?.percent, 30)

        let r = rig.simulation.apply(.invention(.trial(input: sel, quantity: 1, steps: steps)), to: &w)
        XCTAssertNil(r.rejection)
        let page = b.notebook(in: w)
        let t = try XCTUnwrap(page.trials.first)
        XCTAssertEqual(t.steps, 1)
        XCTAssertEqual(t.input.percent, 30)

        let sheet = try XCTUnwrap(b.sheet(.trial(t.record), in: w))
        let card = try XCTUnwrap(sheet.card)
        XCTAssertEqual(sheet.result, card.product.name)
        XCTAssertEqual(card.quantity, 1)
        XCTAssertTrue(card.used.contains { $0.quantity > 0 }, "使った燃料が載る")

        let after = try XCTUnwrap(b.sheet(.draft(steps: steps, input: sel), in: w))
        XCTAssertNotNil(after.rows[0].forecast, "同じ入力で試した段には見込みが出る")
        XCTAssertEqual(after.expected?.name, card.product.name)

        XCTAssertTrue(page.codex.contains { $0.made && $0.name == card.product.name }, "作った物は図鑑に載る")

        rig.simulation.apply(.invention(.makeDesign(steps: steps)), to: &w)
        let plates = b.designBench(in: w).plates
        XCTAssertEqual(plates.count, 1)
        XCTAssertEqual(plates[0].steps, ["炉"])
        XCTAssertNotNil(b.sheet(.design(plates[0].design), in: w))
    }

    /// 資料は開く条件が成り立ったものだけ。読むのは任意(状態を変えない)。
    func testDocumentsOnlyWhenOpen() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        XCTAssertEqual(b.notebook(in: ctx.world).documents.map(\.title), ["試験の書き付け"])
        XCTAssertNil(b.document("doc.test.later", in: ctx.world))
        ctx.learn("fact.test.alpha")
        let w = ctx.world
        XCTAssertEqual(b.notebook(in: w).documents.count, 2)
        let d = try XCTUnwrap(b.document("doc.test.later", in: w))
        XCTAssertEqual(d.body, "試験の事実を知ると読める全文。")
        XCTAssertNil(d.source)
        XCTAssertNotNil(b.document("doc.test.first", in: w)?.source)
        XCTAssertTrue(b.notebook(in: w).records.contains { $0.sheet == "sheet.test.record" }, "開ける記録はノートに並ぶ")
    }

    /// 装置の候補と名簿を締めたかは、同じ工程表に載る(ノートの記録の頁がボタンを出す)。
    func testRecordSheetCarriesImprintAndManifestState() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        ctx.learn("fact.test.device_fixed")
        ctx.learn("fact.test.vessel_ready")
        var w = ctx.world
        let ledger = try XCTUnwrap(b.sheet(.record("sheet.test.ledger"), in: w))
        let im = try XCTUnwrap(ledger.imprint)
        XCTAssertEqual(im.skills.map(\.id), ["skill.test.kindling"])
        XCTAssertFalse(im.targets.isEmpty)
        XCTAssertNil(ledger.manifestLocked)

        let m = try XCTUnwrap(b.sheet(.record("sheet.test.manifest"), in: w))
        XCTAssertEqual(m.manifestLocked, false)
        XCTAssertNil(m.imprint)
        _ = rig.simulation.apply(.narrative(.setBoarding(sheet: "sheet.test.manifest", person: .noah, aboard: true)), to: &w)
        _ = rig.simulation.apply(.narrative(.lockManifest(sheet: "sheet.test.manifest")), to: &w)
        XCTAssertEqual(b.sheet(.record("sheet.test.manifest"), in: w)?.manifestLocked, true)
    }

    /// 設計・ノートのタブが引き直す印は、在庫などが変わったときだけ上がる。
    func testBenchRevisionRisesOnRelevantChanges() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var w = world(rig, furnace: true)
        let f0 = b.build(w, revision: 1, previous: nil, report: nil)
        let quiet = rig.simulation.advance(&w, realSeconds: 0.2)
        let f1 = b.build(w, revision: 2, previous: f0, report: quiet)
        if quiet.changes.areas.isDisjoint(with: [.inventory, .notebook, .perception, .research, .narrative, .placements]) {
            XCTAssertEqual(f1.benchRevision, f0.benchRevision)
        }
        let sel = try XCTUnwrap(b.designBench(in: w).materials.first?.selector)
        let r = rig.simulation.apply(.invention(.trial(input: sel, quantity: 1, steps: steps)), to: &w)
        let f2 = b.build(w, revision: 3, previous: f1, report: r)
        XCTAssertEqual(f2.benchRevision, 3)
    }

    /// 図鑑の影: 品の欄(正体が分かるまで埋まらない)・造語の名前だけの欄・条件つきの欄。答えは出さず、欄があることだけを出す。
    func testCodexShadowsShowDepthNotAnswers() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        var codex = b.notebook(in: ctx.world).codex
        let ore = try XCTUnwrap(codex.first { $0.item })
        XCTAssertEqual(ore.name, "見慣れない石")
        XCTAssertFalse(ore.made)
        XCTAssertTrue(codex.contains { $0.name == "試験の造語の欄" && !$0.made })
        XCTAssertFalse(codex.contains { $0.name == "あとで出る試験の欄" })
        ctx.learn("fact.test.alpha")
        ctx.learn("fact.test.revealed")
        codex = b.notebook(in: ctx.world).codex
        XCTAssertTrue(codex.contains { $0.name == "あとで出る試験の欄" })
        XCTAssertEqual(codex.first { $0.item }?.made, true)
    }

    /// 作れば埋まる名前の欄は、作った後は本物の行に任せて消える。棚の「？」はまだ知らない段の数。
    func testTargetShadowDisappearsOnceMadeAndUnknownModuleCount() throws {
        var c = try TestContent.publicOnly()
        let rig0 = TestRig(content: c)
        var w = world(rig0, furnace: true)
        let sel = try XCTUnwrap(FrameBuilder(content: c).designBench(in: w).materials.first?.selector)
        var probe = w
        rig0.simulation.apply(.invention(.trial(input: sel, quantity: 1, steps: steps)), to: &probe)
        let made = try XCTUnwrap(probe.notebook.trials.last?.outcome.name)
        c.codexShadows["codex.test.target"] = CodexShadowDef(id: "codex.test.target", name: "misc:codex.test.coined",
                                                             target: made, order: 9)
        let rig = TestRig(content: c)
        let b = FrameBuilder(content: c)
        let before = b.notebook(in: w).codex.filter { $0.name == "試験の造語の欄" }.count
        XCTAssertEqual(before, 2, "試験の欄と、作れば埋まる欄")
        rig.simulation.apply(.invention(.trial(input: sel, quantity: 1, steps: steps)), to: &w)
        XCTAssertEqual(b.notebook(in: w).codex.filter { $0.name == "試験の造語の欄" }.count, 1)

        let bench = b.designBench(in: w)
        XCTAssertEqual(bench.unknownModules, c.ruleBook.modules.keys.count - bench.modules.count)
        XCTAssertGreaterThan(bench.unknownModules, 0)
    }

    /// 影の欄の名前は認識の表に載る見出しでなければ、検証で止める(気配の監査が見え方を引けるように)。
    func testCodexShadowNameMustBeInPerception() throws {
        var c = try TestContent.publicOnly()
        XCTAssertFalse(ContentValidator.validate(c).contains { $0.rule.hasPrefix("codexShadows") })
        c.codexShadows["codex.test.bad"] = CodexShadowDef(id: "codex.test.bad", name: "misc:codex.test.missing")
        XCTAssertTrue(ContentValidator.validate(c).contains { $0.rule == "codexShadows.name" && $0.level == .error })
    }
}

