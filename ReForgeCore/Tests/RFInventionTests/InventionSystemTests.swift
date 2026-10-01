import Foundation
import RFContent
import RFInvention
import RFKernel
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// RFInvention の受け入れテスト(docs/architecture/F-work-units.md の U6)。TEST-R1-01 は DeductionBotTests。
final class InventionSystemTests: XCTestCase {
    /// 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(InventionSystem().handle(foreign, &ctx), .notMine)
    }

    // MARK: 試作は手持ちの材料を実際に使う

    func testTrialSpendsOreAndFuelAndGoesToNotebook() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 1)
        let ore = InventionFixture.orePurity(seed: 1)
        let r = fx.trial([.charcoalFurnace, .anvil], &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(r.warnings, [])
        XCTAssertEqual(InventionFixture.oreCount(w), 7)
        XCTAssertEqual(w.inventory.quantity(.charcoal), 59)

        XCTAssertEqual(w.notebook.trials.count, 1)
        let t = try XCTUnwrap(w.notebook.trials.first)
        XCTAssertEqual(t.input, .ironOre(purity: ore))
        XCTAssertEqual(t.steps, [.charcoalFurnace, .anvil])
        XCTAssertEqual(t.outcome, ProcessChain.run([.charcoalFurnace, .anvil], input: .ironOre(purity: ore)))
        // できた板は拠点に戻る(柔らかい板)
        let plate = t.outcome.product
        XCTAssertEqual(plate.shape, .plate)
        XCTAssertEqual(plate.temper, .soft)
        XCTAssertEqual(w.inventory.quantity(where: { $0 == .matter(plate) }), 1)
        // 来歴: ノアが試作した。材料の来歴が inputs に入る
        let rec = try XCTUnwrap(w.ledger.record(t.record))
        XCTAssertEqual(rec.act, .trialed)
        XCTAssertEqual(rec.actor, .noah)
        XCTAssertEqual(rec.subject, .matter(t.outcome.name))
        XCTAssertTrue(r.events.contains(.trialed(record: t.record)))
        // 結果カード: 純度はノアの手の見当(刻み 5%)
        let card = Sheets.card(t)
        XCTAssertEqual(card.sensed.basisPoints % HandSense.resolution, 0)
        XCTAssertLessThanOrEqual(abs(card.sensed.basisPoints - plate.purity.basisPoints), HandSense.resolution / 2)
        XCTAssertEqual(card.consumed, [ItemAmount(.charcoal, 1)])
    }

    /// 1 単位ずつ同じ並びを通すので、数を増やすと使う物も増える(試作で量産はできない)。
    func testQuantityScalesConsumption() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 2)
        XCTAssertNil(fx.trial([.millstone, .sluice, .lime, .charcoalFurnace], &w, quantity: 3).rejection)
        XCTAssertEqual(InventionFixture.oreCount(w), 5)
        XCTAssertEqual(w.inventory.quantity(.charcoal), 57)
        XCTAssertEqual(w.inventory.quantity(.water), 37)
        XCTAssertEqual(w.inventory.quantity(.limestone), 17)
        XCTAssertEqual(Sheets.card(try XCTUnwrap(w.notebook.trials.last)).consumed,
                       [ItemAmount(.charcoal, 3), ItemAmount(.limestone, 3), ItemAmount(.water, 3)])
    }

    /// 材料が足りなければ何も使わずに断る。鉱石が尽きたら試せない(総当たりはできない)。
    func testRejectsWithoutSpendingWhenShort() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 3, ore: 2, charcoal: 1, water: 0)
        let before = w.inventory
        XCTAssertEqual(fx.trial([.millstone, .sluice], &w).rejection?.reason, InventionReasons.missingInput)
        XCTAssertEqual(w.inventory, before)
        XCTAssertTrue(w.notebook.trials.isEmpty)

        XCTAssertEqual(fx.trial([.millstone], &w, quantity: 3).rejection?.reason, InventionReasons.notEnoughInput)
        XCTAssertEqual(fx.trial([], &w).rejection?.reason, InventionReasons.noSteps)
        XCTAssertNil(fx.trial([.charcoalFurnace], &w).rejection)
        // 木炭が尽きた
        XCTAssertEqual(fx.trial([.charcoalFurnace], &w).rejection?.reason, InventionReasons.missingInput)
        XCTAssertNil(fx.trial([.millstone], &w).rejection)
        // 鉱石が尽きた
        XCTAssertNil(InventionFixture.oreSelector(w))
        XCTAssertEqual(w.notebook.trials.count, 2)

        // 解禁していないモジュールは使えない
        var w2 = fx.world(seed: 3)
        w2.research.unlocked.modules.remove(.quenchTank)
        XCTAssertEqual(fx.trial([.charcoalFurnace, .anvil, .quench], &w2).rejection?.reason,
                       InventionReasons.moduleLocked)
    }

    /// 試作に要る設備は世界の物で満たす: 熱する段は置いた炉、冷やす段は置いた水槽か水辺。ほかの段は手でできる。
    /// 満たさなければ理由の ID で断り、何も使わない。コンテンツのモジュールの定義で条件を書き換えられる。
    func testTrialNeedsEquipmentInTheWorld() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 10, equipped: false)
        let before = w.inventory
        XCTAssertEqual(fx.trial([.millstone, .charcoalFurnace], &w).rejection?.reason, TrialRequirements.needsFurnace)
        XCTAssertEqual(w.inventory, before)
        XCTAssertNil(fx.trial([.millstone, .sluice, .lime, .anvil], &w).rejection)  // 手と道具でできる段だけ

        // 炉を置くと熱せる。水槽が無く水辺からも離れていれば冷やせない
        var ctx = StepContext(world: w, content: fx.content)
        InventionFixture.place(.furnace, &ctx)
        w = ctx.world
        XCTAssertNil(fx.trial([.charcoalFurnace, .anvil], &w).rejection)
        let r = fx.trial([.charcoalFurnace, .anvil, .quench], &w)
        XCTAssertEqual(r.rejection?.reason, TrialRequirements.needsQuench)
        XCTAssertEqual(r.rejection?.detail["module"], .string("quench_tank"))

        // ノアのとなりのマスが水辺なら冷やせる(水槽なしで)
        let noah = try XCTUnwrap(w.people[.noah]?.position)
        w.map[noah.layer]?.setTerrain("water", at: GridPoint(noah.point.x + 1, noah.point.y))
        XCTAssertNil(fx.trial([.charcoalFurnace, .anvil, .quench], &w).rejection)
        XCTAssertEqual(w.notebook.trials.last?.outcome.product.temper, .hard)

        // コンテンツが条件を書き換える(例: 炉は焚き火台の上位の建造物でもよい → ここでは条件なし)
        var content = fx.content
        content.modules[.furnace]?.trial = TrialRequirement(when: .always, reason: "reason.test.never")
        let fx2 = InventionFixture(content: content)
        var w2 = fx2.world(seed: 10, equipped: false)
        XCTAssertNil(fx2.trial([.charcoalFurnace], &w2).rejection)
    }

    /// 夜に試作すると 2 時間進む。日没に試せば夜作業が始まる。昼はリアルタイムのまま(試作で時間を飛ばさない)。
    func testNightTrialAdvancesTime() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 4)
        let t0 = w.clock.now
        XCTAssertNil(fx.trial([.millstone], &w).rejection)
        XCTAssertEqual(w.clock.now, t0)

        _ = fx.rig.playDay(&w)
        XCTAssertEqual(w.clock.phase, .dusk)
        let dusk = w.clock.now
        let r = fx.trial([.charcoalFurnace], &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.clock.phase, .nightWork)
        XCTAssertEqual(w.clock.now, dusk + .hours(2))
        XCTAssertTrue(r.events.contains(.phaseChanged(to: .nightWork, day: 1)))
        XCTAssertNil(fx.trial([.charcoalFurnace, .anvil], &w).rejection)
        XCTAssertEqual(w.clock.now, dusk + .hours(4))
        XCTAssertEqual(w.notebook.trials.map(\.at), [t0, dusk, dusk + .hours(2)])
    }

    // MARK: 最初の鉄

    /// 初めて製錬に成功した試作は、来歴に印(工業の初めて)が付き、できた物の 1 個が唯一品として残る。
    /// 出来事の担当は trialed の引き金と firstTime(印 smelted)で場面を起こせる。
    func testFirstSmeltLeavesUniqueAndFirstTimeRecord() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 5)
        XCTAssertNil(fx.trial([.millstone, .sluice], &w).rejection)  // 溶けない
        XCTAssertNil(fx.trial([.charcoalFurnace], &w, quantity: 2).rejection)  // 最初の鉄
        XCTAssertNil(fx.trial([.charcoalFurnace, .anvil], &w).rejection)  // 2 回目の製錬

        let recs = w.notebook.trials.map { w.ledger.record($0.record)! }
        XCTAssertEqual(recs[0].tags, [])
        XCTAssertEqual(recs[1].tags, [InventionTags.smelted, InventionTags.firstSmelt])
        XCTAssertEqual(recs[2].tags, [InventionTags.smelted])

        // 唯一品: 1 個だけ。来歴は最初の製錬の記録
        let first = w.notebook.trials[1]
        let uid = try XCTUnwrap(first.unique)
        let uniques = w.inventory.entries(.base).filter { $0.unique != nil }
        XCTAssertEqual(uniques.count, 1)
        XCTAssertEqual(uniques.first?.unique, uid)
        XCTAssertEqual(uniques.first?.quantity, 1)
        XCTAssertEqual(uniques.first?.origins, [first.record: 1])
        XCTAssertEqual(uniques.first?.stuff, .matter(first.outcome.product))
        // 残りの 1 個は普通の山
        XCTAssertEqual(w.inventory.entries(.base).filter { $0.unique == nil && $0.stuff == .matter(first.outcome.product) }
            .reduce(0) { $0 + $1.quantity }, 1)
        XCTAssertNil(w.notebook.trials[2].unique)

        // 引き金の条件
        let q = ProvenanceQuery(act: .trialed, tag: InventionTags.smelted)
        let c = Condition.firstTime(query: q)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(c, world: w, content: fx.content, trigger: first.record), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(c, world: w, content: fx.content,
                                                       trigger: w.notebook.trials[2].record), false)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(
            .ledger(query: ProvenanceQuery(tag: InventionTags.firstSmelt), atLeast: 1), world: w, content: fx.content),
            true)
    }

    // MARK: ノート(出典つきの書き留め・図鑑)

    /// 手がかりは条件が成り立った時点で 1 回だけ、出典つきでノートに載る。出典はコンテンツの中立の見出しのまま。
    func testHintsArriveWhenConditionsHoldWithSources() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 6)
        XCTAssertTrue(w.notebook.notes.isEmpty)
        // 最初のステップで、いつでも成り立つ手がかり(端末の断片・図鑑の空欄)
        let r0 = fx.rig.simulation.runSteps(1, &w)
        XCTAssertEqual(Set(w.notebook.notes.compactMap(\.hint)),
                       ["hint.test.terminal", "hint.test.codex.fine", "hint.test.codex.hard"])
        XCTAssertEqual(r0.events.filter { $0.hook == "hint" }.count, 3)

        // 最初の試作の後に、手が知っていた手順
        let r1 = fx.trial([.millstone], &w)
        XCTAssertTrue(r1.events.contains { if case .hintHeard("hint.test.hand.lime", nil, _) = $0 { true } else { false } })
        XCTAssertEqual(w.notebook.notes.last?.source, "source:hand")
        XCTAssertEqual(w.notebook.notes.last?.text, "text.test.hint.hand_lime")

        // 仲間の案は関係ランク 3 から(1 時間ごとの見回りで載る)
        XCTAssertNil(w.notebook.hints["hint.test.companion"])
        w.people[InventionFixture.companion]?.relation.rank = 3
        let r2 = fx.rig.simulation.runSteps(240, &w)
        let note = try XCTUnwrap(w.notebook.notes.first { $0.hint == "hint.test.companion" })
        XCTAssertEqual(note.source, "source:companion")
        XCTAssertEqual(note.about, "module:mixing_bowl")
        let heard = try XCTUnwrap(w.ledger.record(try XCTUnwrap(note.record)))
        XCTAssertEqual(heard.act, .heardHint)
        XCTAssertEqual(heard.actor, InventionFixture.companion)
        XCTAssertTrue(r2.events.contains(.hintHeard(hint: "hint.test.companion", from: InventionFixture.companion,
                                                    record: heard.id)))
        // 二度は載らない
        let count = w.notebook.notes.count
        _ = fx.rig.simulation.runSteps(480, &w)
        _ = fx.trial([.millstone], &w)
        XCTAssertEqual(w.notebook.notes.count, count + 1)  // 2 回目の試作で「砕いて洗えば」だけが増える
        XCTAssertEqual(w.notebook.notes.last?.hint, "hint.test.hand.crush_wash")
    }

    /// 図鑑: 作った物で埋まり、空欄(命名の手がかり)は影で出て、部品を全部含む物を作ると埋まる。
    func testCodexFillsAndKeepsBlanks() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 7)
        _ = fx.rig.simulation.runSteps(1, &w)
        var rows = Codex.rows(w.notebook, content: fx.content)
        XCTAssertEqual(rows.filter { !$0.made }.count, 2)

        XCTAssertNil(fx.trial([.millstone, .sluice, .lime, .charcoalFurnace, .anvil], &w).rejection)
        rows = Codex.rows(w.notebook, content: fx.content)
        let made = try XCTUnwrap(rows.first { $0.made })
        XCTAssertEqual(made.name.grade, .fine)
        XCTAssertEqual(made.hints, ["hint.test.codex.fine"])
        XCTAssertEqual(rows.filter { !$0.made }.map(\.hints), [["hint.test.codex.hard"]])

        // 同じ名前は 1 行で、最良の純度を覚える
        XCTAssertNil(fx.trial([.millstone, .sluice, .lime, .charcoalFurnace, .anvil], &w).rejection)
        XCTAssertEqual(w.notebook.codex.count, 1)
    }

    // MARK: ライン札と工程表(物のライン専用にしない)

    func testDesignFromTrialAndSheets() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 8)
        let lime: [ProcessStep] = [.millstone, .sluice, .lime, .charcoalFurnace, .anvil]
        XCTAssertNil(fx.trial(lime, &w).rejection)
        let trial = try XCTUnwrap(w.notebook.trials.last)

        let r = fx.rig.simulation.apply(.invention(.makeDesign(steps: [.minehead] + lime)), to: &w)
        XCTAssertNil(r.rejection)
        // 採掘口を先頭に足した並びは試していないので見込みは無い
        let (id0, d0) = try XCTUnwrap(w.invention.designs.first)
        XCTAssertNil(d0.expected)
        XCTAssertTrue(r.events.contains(.designed(design: id0, record: d0.origin)))

        XCTAssertNil(fx.rig.simulation.apply(.invention(.makeDesign(steps: lime)), to: &w).rejection)
        let (id, d) = try XCTUnwrap(w.invention.designs.max { $0.key < $1.key })
        XCTAssertEqual(d.expected, trial.outcome.product)
        XCTAssertEqual(d.trial, trial.record)
        XCTAssertEqual(w.ledger.record(d.origin)?.inputs, [trial.record])

        // ライン札の工程表: 行ごとに見込みがあり、全体の見込みは試作の結果と同じ名前
        let sheet = try XCTUnwrap(Sheets.model(.design(id), world: w, content: fx.content))
        XCTAssertEqual(sheet.rows.map(\.subject), lime.map { Subject.module($0.module) })
        XCTAssertEqual(sheet.rows[2].inputs, [.limestone])
        XCTAssertTrue(sheet.rows.allSatisfy { $0.forecast != nil })
        XCTAssertEqual(sheet.expected?.name, trial.outcome.name)
        XCTAssertEqual(sheet.head?.sensed, HandSense.estimate(trial.input))

        // 試作の工程表は結果カードつき
        let ts = try XCTUnwrap(Sheets.model(.trial(trial.record), world: w, content: fx.content))
        XCTAssertEqual(ts.card?.name, trial.outcome.name)
        XCTAssertEqual(ts.rows.count, lime.count)

        // 下書き: 試した所まで見込みが出て、その先は「？」
        let draft = try XCTUnwrap(Sheets.model(.draft(steps: lime + [.quench], input: trial.input), world: w,
                                               content: fx.content))
        XCTAssertEqual(draft.rows.map { $0.forecast != nil }, [true, true, true, true, true, false])
        XCTAssertNil(draft.expected)
        XCTAssertEqual(draft.rows[1].forecast?.name, NameGenerator.name(for: trial.outcome.trace[1].after))
        // 入力の見当が違えば見込みは出ない
        let other = Sheets.forecast(lime, input: .ironOre(purity: Purity(percent: 60)), notebook: w.notebook)
        XCTAssertTrue(other.allSatisfy { $0 == nil })

        // コンテンツの記録も同じ形で開ける(条件が成り立つまで開けない)
        XCTAssertNil(Sheets.model(.record("sheet.test.record"), world: w, content: fx.content))
        var ctx = StepContext(world: w, content: fx.content)
        ctx.learn("fact.test.alpha")
        w = ctx.world
        let rec = try XCTUnwrap(Sheets.model(.record("sheet.test.record"), world: w, content: fx.content))
        XCTAssertEqual(rec.title, .subject("sheet:sheet.test.record"))
        XCTAssertEqual(rec.rows, [SheetRow(subject: "module:furnace", note: "text.test.row")])

        // 札を捨てる
        XCTAssertNil(fx.rig.simulation.apply(.invention(.discardDesign(design: id)), to: &w).rejection)
        XCTAssertNil(w.invention.designs[id])
        XCTAssertEqual(fx.rig.simulation.apply(.invention(.discardDesign(design: id)), to: &w).rejection?.reason,
                       InventionReasons.noDesign)
    }

    /// 世界状態(ノート・ライン札)は保存して戻せる。
    func testNotebookRoundTrips() throws {
        let fx = try InventionFixture()
        var w = fx.world(seed: 9)
        _ = fx.rig.simulation.runSteps(1, &w)
        _ = fx.trial([.millstone, .sluice, .lime, .charcoalFurnace, .anvil, .quench], &w)
        _ = fx.rig.simulation.apply(.invention(.makeDesign(steps: [.charcoalFurnace])), to: &w)
        let data = try JSONEncoder().encode(w)
        XCTAssertEqual(try JSONDecoder().decode(WorldState.self, from: data), w)
    }

    /// 手がかりの主張はコンテンツの JSON で書ける(非公開の層が本物の手がかりを書く形)。
    func testHintClaimsDecodeFromContentJSON() throws {
        let json = """
        {"hints": [{"id": "hint.test.json", "from": "person.test_b",
          "when": {"person": {"id": "person.test_b", "test": {"relationAtLeast": {"rank": 3}}}},
          "about": "module:mixing_bowl", "text": "text.test.hint.json", "source": "source:companion",
          "claims": [
            {"says": {"before": {"first": {"module": "mixing_bowl", "input": "limestone"}, "then": {"module": "furnace"}}},
             "toward": {"grade": {"grade": "fine", "category": "metal"}}},
            {"says": {"includes": {"step": {"module": "quench_tank"}}}, "toward": {"temper": {"temper": "hard"}}},
            {"says": {"gradeMeans": {"threshold": 8500}}}
          ],
          "target": {"parts": [{"temper": {"temper": "hard"}}, {"substance": {"substance": "Fe"}}, {"shape": {"shape": "plate"}}]}
        }]}
        """
        var db = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(json.utf8), to: &db)
        let h = try XCTUnwrap(db.hints["hint.test.json"])
        XCTAssertEqual(h.claims, [
            HintClaim(.before(first: StepPattern(.mixingBowl, input: .limestone), then: StepPattern(.furnace)),
                      toward: .grade(.fine, .metal)),
            HintClaim(.includes(step: StepPattern(.quenchTank)), toward: .temper(.hard)),
            HintClaim(.gradeMeans(threshold: Purity(percent: 85))),
        ])
        XCTAssertEqual(h.target, MatterName([.temper(.hard), .substance(.iron), .shape(.plate)]))
        XCTAssertEqual(ClaimKind.before(first: StepPattern(.mixingBowl, input: .limestone), then: StepPattern(.furnace))
            .holds(in: [.charcoalFurnace, .lime]), false)
        XCTAssertEqual(ClaimKind.next(first: StepPattern(.millstone), then: StepPattern(.sluice))
            .holds(in: [.millstone, .lime, .sluice]), false)
    }
}
