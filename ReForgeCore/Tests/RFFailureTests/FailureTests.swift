import Foundation
import RFContent
import RFFailure
import RFKernel
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class FailureTests: XCTestCase {
    struct Setup {
        let rig: TestRig
        let book: SaveBook
        let recovery: Recovery
    }

    func setup(_ content: ContentDB? = nil) throws -> Setup {
        let rig = try content.map(TestRig.init(content:)) ?? TestRig.publicOnly()
        let book = SaveBook(storage: MemorySaveStorage(), content: [ContentStamp(layer: "public", version: "fixture-1")])
        let factory = rig.factory
        return Setup(rig: rig, book: book,
                     recovery: Recovery(content: rig.content, book: book, newWorld: { factory.newWorld(seed: $0) }))
    }

    /// 失敗の規則を成り立たせて 1 ステップ進め、失敗させる。
    func fail(_ w: inout WorldState, _ rig: TestRig) {
        w.narrative.counters["counter.test.doom"] = 1
        _ = rig.simulation.runSteps(1, &w)
    }

    func dejaVuLine(_ w: WorldState, _ c: ContentDB) -> Bool? {
        ConditionEvaluator.evaluatePure(c.lines["line.test.deja_vu"]!.when!, world: w, content: c)
    }

    /// 失敗の規則(値で判定)が成り立つと周回が失敗になり、本体は進まなくなる。
    func testFailureRuleEndsRun() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        w.narrative.counters["counter.test.doom"] = 1
        let r = rig.simulation.runSteps(3, &w)
        XCTAssertEqual(r.steps, 1)
        XCTAssertEqual(w.run.outcome, .failed(cause: "text.test.cause", record: w.ledger.records.last?.id))
        XCTAssertEqual(w.ledger.records.last?.detail["rule"], .string("failure.test.doom"))
        XCTAssertNotNil(rig.simulation.apply(.time(.sleep), to: &w).rejection)
        XCTAssertEqual(r.events.last, .runFailed(cause: "text.test.cause"))
    }

    /// TEST-R1-07 巻き戻しの持ち越しと仲間の「前にも」。
    /// 1 日目を遊んで寝る(夜明けの自動セーブ)→ 2 日目に事実を知り・ノートを書き・地図を見て・物を集め・関係が上がり・
    /// 仲間が死んで → 失敗 → 記憶を持って巻き戻す。在庫・生死は 2 日目の夜明けに戻り、知った事実(記憶)・ノート・
    /// 地図の既知・関係・残る記憶は残る。仲間に「前にも」の記憶が付き、その一言の条件が成り立つ。
    /// 巻き戻した後の最初のステップで run.resumed が出る。回数は来歴と run に残る。
    func testR1_07_RewindCarriesMemoryAndCompanionsRemember() throws {
        let s = try setup()
        let rig = s.rig
        var w = rig.factory.newWorld(seed: 1)
        try s.book.startNew(w)
        _ = rig.playDay(&w)
        let dawnReport = rig.simulation.apply(.time(.sleep), to: &w)
        XCTAssertTrue(dawnReport.events.contains(.dawn(day: 2)))
        try s.book.autosaveDawn(w)                       // GameHost が夜明けの出来事を見て呼ぶ
        let dawn = w

        // 2 日目
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.revealed")
        ctx.learn("fact.test.timeline")
        ctx.addStock(.item("wood"), 50, to: .base)
        let trial = ctx.record(.trialed, .item("test_ore"), actor: .noah)
        ctx.world.notebook.notes.append(NoteEntry(about: "subject.test.ore", text: "text.test.line1",
                                                  source: "subject.test.noah_hand", record: trial,
                                                  at: ctx.world.clock.now, run: 1))
        ctx.world.people["person.test_a"]?.relation.points = 40
        ctx.world.people["person.test_a"]?.relation.rank = 2
        let saw = ctx.record(.observed, .none, tags: ["tag.test.memorable"])
        ctx.world.people["person.test_a"]?.memories.append(
            MemoryRecord(kind: "memory.test.saw", at: ctx.world.clock.now, run: 1, about: saw, persistsAcrossRewind: true))
        ctx.world.people["person.test_a"]?.memories.append(
            MemoryRecord(kind: "memory.test.saw", at: ctx.world.clock.now, run: 1, about: nil, persistsAcrossRewind: false))
        let died = ctx.record(.died, .person("person.test_b"), tags: ["tag.test.memorable"])
        ctx.world.people["person.test_b"]?.presence = .dead(at: ctx.world.clock.now, record: died)
        var known = ctx.world.knowledge.mapKnown[.surface] ?? GridBitset(size: GridSize(width: 32, height: 32))
        known[GridPoint(30, 30)] = true
        ctx.world.knowledge.mapKnown[.surface] = known
        w = ctx.world
        _ = rig.simulation.advance(&w, realSeconds: 0.5)
        fail(&w, rig)
        let failed = w
        XCTAssertFalse(failed.run.isActive)
        XCTAssertEqual(dejaVuLine(failed, rig.content), false)

        // 4 択: どれも並び、ここではどれも選べる
        let choices = try s.recovery.choices(for: failed)
        XCTAssertEqual(choices.map(\.option), RecoveryOption.allCases)
        XCTAssertTrue(choices.allSatisfy(\.available))
        XCTAssertEqual(choices[1].targets, [.dawn(day: 2), .dawn(day: 1)])

        let result = try s.recovery.perform(.rewindWithMemory, failed: failed, newSeed: 0)
        var r = result.world
        XCTAssertTrue(r.run.isActive)
        // 戻す
        XCTAssertEqual(r.inventory, dawn.inventory)
        XCTAssertEqual(r.clock, dawn.clock)
        XCTAssertEqual(r.narrative, dawn.narrative, "出来事の進みは夜明けのまま(巻き戻しは物語の引き金を変えない)")
        XCTAssertTrue(r.people["person.test_b"]?.presence.isAlive == true, "生死は夜明けに戻る")
        // 残す
        XCTAssertTrue(r.knowledge.knows("fact.test.revealed"))
        XCTAssertFalse(r.knowledge.knows("fact.test.timeline"), "その時間軸だけの事実は消える")
        XCTAssertEqual(r.notebook, failed.notebook)
        XCTAssertTrue(r.knowledge.mapKnown[.surface]?[GridPoint(30, 30)] == true)
        XCTAssertEqual(r.people["person.test_a"]?.relation.points, 40)
        XCTAssertEqual(r.people["person.test_a"]?.relation.rank, 2)
        XCTAssertEqual(r.people["person.test_a"]?.memories.filter { $0.kind == "memory.test.saw" }.count, 1)
        // 前の周回の記録: 覚えておく印・失敗の記録・持ち越した物が指す記録
        let life = try XCTUnwrap(r.run.pastLives.last)
        XCTAssertEqual(life.run, 1)
        XCTAssertEqual(life.endedDay, 2)
        XCTAssertEqual(life.rewoundToDay, 2)
        XCTAssertEqual(life.cause, "text.test.cause")
        XCTAssertTrue(life.memorable.map(\.id).contains(died))
        XCTAssertTrue(life.memorable.map(\.id).contains(saw))
        XCTAssertEqual(r.run.pastRecord(trial)?.act, .trialed, "ノートの出典の記録は前の周回の記録として引ける")
        XCTAssertEqual(r.run.pastRecord(saw)?.act, .observed)
        XCTAssertNil(r.ledger.record(died), "来歴そのものは夜明けまで")
        // 周回と回数
        XCTAssertEqual(r.run.index, 2)
        XCTAssertEqual(r.run.rewinds, 1)
        let rewound = try XCTUnwrap(r.ledger.records.last)
        XCTAssertEqual(rewound.act, .rewound)
        XCTAssertEqual(rewound.run, 2)
        XCTAssertGreaterThan(rewound.id, failed.ledger.records.last!.id, "来歴の番号は前の周回の続きから")
        XCTAssertGreaterThanOrEqual(r.ids.nextValue, failed.ids.nextValue)
        // 仲間の「前にも」: 夜明けの一員(ノア以外)に記憶が付き、一言の条件が成り立つ
        for id in r.people.members where id != .noah {
            let m = r.people[id]?.memories.last
            XCTAssertEqual(m?.kind, "memory.test.deja_vu")
            XCTAssertEqual(m?.about, rewound.id)
        }
        XCTAssertNil(r.people[.noah]?.memories.first { $0.kind == "memory.test.deja_vu" })
        XCTAssertEqual(dejaVuLine(r, rig.content), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(.runAtLeast(index: 2), world: r, content: rig.content), true)
        // 保存: 2 日目の夜明けは巻き戻した世界で上書き、続きも
        XCTAssertEqual(try s.book.load(.dawn(day: 2))?.world, r)
        XCTAssertEqual(try s.book.readResume()?.world, r)
        // 最初のステップで出来事
        let step = rig.simulation.runSteps(1, &r)
        XCTAssertTrue(step.events.contains(.runResumed(act: .rewound, record: rewound.id)))
        XCTAssertNil(r.run.resumeNotice)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    /// 2 度目の失敗も同じ夜明けへ巻き戻せ、前の周回の記録は積み上がる(上書きされた夜明けから戻る)。
    func testSecondRewindStacksPastLives() throws {
        let s = try setup()
        var w = s.rig.factory.newWorld(seed: 2)
        try s.book.startNew(w)
        fail(&w, s.rig)
        var r = try s.recovery.perform(.rewindWithMemory, failed: w, newSeed: 0).world
        fail(&r, s.rig)
        let r2 = try s.recovery.perform(.rewindWithMemory, failed: r, newSeed: 0).world
        XCTAssertEqual(r2.run.index, 3)
        XCTAssertEqual(r2.run.rewinds, 2)
        XCTAssertEqual(r2.run.pastLives.map(\.run), [1, 2])
        XCTAssertEqual(r2.ledger.records.filter { $0.act == .rewound }.count, 2, "巻き戻しの回数は来歴に残る")
        XCTAssertEqual(r2.people["person.test_a"]?.memories.filter { $0.kind == "memory.test.deja_vu" }.count, 2)
    }

    /// 最新の夜明けがすぐ失敗に落ちる場合のため、残っている夜明けから選べる。選んだ日より先の夜明けは消える。
    func testRewindToAnOlderDawn() throws {
        let s = try setup()
        var w = s.rig.factory.newWorld(seed: 3)
        try s.book.startNew(w)
        for _ in 0..<2 {
            _ = s.rig.playDay(&w)
            _ = s.rig.simulation.apply(.time(.sleep), to: &w)
            try s.book.autosaveDawn(w)
        }
        XCTAssertEqual(w.clock.day, 3)
        fail(&w, s.rig)
        let r = try s.recovery.perform(.rewindWithMemory, failed: w, target: .dawn(day: 2), newSeed: 0).world
        XCTAssertEqual(r.clock.day, 2)
        XCTAssertEqual(try s.book.savePoints().map(\.slot), [.dawn(day: 2), .dawn(day: 1)])
        XCTAssertThrowsError(try s.recovery.perform(.rewindWithMemory, failed: w, target: .dawn(day: 9), newSeed: 0))
    }

    /// 巻き戻しは物語の引き金を変えない: 夜明けより前にした行為(炉を置いた)を問う条件は、巻き戻しの後も成り立つ。
    func testRewindKeepsLedgerConditionsBeforeDawn() throws {
        let s = try setup()
        var ctx = StepContext(world: s.rig.factory.newWorld(seed: 4), content: s.rig.content)
        ctx.record(.placed, .module("furnace", nil), actor: .noah)
        var w = ctx.world
        try s.book.startNew(w)
        let placedFurnace = Condition.ledger(query: ProvenanceQuery(act: .placed, module: "furnace"), atLeast: 1)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(placedFurnace, world: w, content: s.rig.content), true)
        fail(&w, s.rig)
        let r = try s.recovery.perform(.rewindWithMemory, failed: w, newSeed: 0).world
        XCTAssertEqual(ConditionEvaluator.evaluatePure(placedFurnace, world: r, content: s.rig.content), true,
                       "夜明け前の行為は巻き戻し後も来歴の条件で数えられる")
    }

    /// 失って続ける: 関係の最も低い仲間が去り(away)、拠点の蓄えを半分失い、失敗の原因の値が戻って、その場から続く。
    /// 死んだ仲間は戻らない。失ったことは来歴に残り、最初のステップで run.resumed が出る。
    func testContinueWithLoss() throws {
        let s = try setup()
        var ctx = StepContext(world: s.rig.factory.newWorld(seed: 5), content: s.rig.content)
        ctx.addStock(.item("wood"), 17, to: .base)
        ctx.addStock(.item("wood"), 1, to: .base, unique: ctx.world.newEntityID())
        ctx.addStock(.item("test_ore"), 2, to: .person("person.test_a"))
        ctx.world.people["person.test_b"]?.relation.points = 30
        ctx.world.people["person.noah"]?.relation.points = -100
        ctx.world.people["person.test_c"]?.presence = .dead(at: .zero, record: nil)
        var w = ctx.world
        let wood = w.inventory.quantity("wood")
        fail(&w, s.rig)
        let failed = w

        let result = try s.recovery.perform(.continueWithLoss, failed: failed, newSeed: 0)
        var r = result.world
        XCTAssertTrue(r.run.isActive)
        XCTAssertEqual(r.run.index, 1, "同じ周回のまま続く")
        XCTAssertEqual(r.run.losses, 1)
        XCTAssertEqual(r.narrative.counters["counter.test.doom"], 0, "原因の値が戻る(onContinue)")
        XCTAssertEqual(r.people["person.test_a"]?.presence, .away(since: failed.clock.now))
        XCTAssertNil(r.people["person.test_a"]?.position)
        XCTAssertTrue(r.people["person.test_b"]?.presence.isMember == true)
        XCTAssertTrue(r.people[.noah]?.presence.isMember == true, "ノアは去らない")
        XCTAssertEqual(r.people["person.test_c"]?.presence, .dead(at: .zero, record: nil), "死んだ人は戻らない")
        let uniqueWood = 1
        XCTAssertEqual(r.inventory.quantity("wood"), (wood - uniqueWood) - (wood - uniqueWood) / 2 + uniqueWood)
        XCTAssertEqual(r.inventory.quantity("test_ore"), (2 + 2) / 2, "去った人の持ち物は拠点に置いていき、その後に半分失う")
        XCTAssertNil(r.inventory.holders[.person("person.test_a")])
        let acts = r.ledger.records.suffix(3).map(\.act)
        XCTAssertEqual(acts, [.continuedWithLoss, .left, .consumed])
        XCTAssertEqual(try s.book.readResume()?.world, r)
        let step = s.rig.simulation.runSteps(1, &r)
        XCTAssertTrue(step.events.contains { if case .runResumed(.continuedWithLoss, _) = $0 { true } else { false } })
        XCTAssertTrue(r.run.isActive, "すぐ同じ失敗に戻らない")
        XCTAssertTrue(result.warnings.isEmpty)
    }

    /// 失敗の原因を解く効果が無いと、失って続けるは選べない(灰色・理由つき)。
    func testContinueUnavailableWhileStillFailing() throws {
        var content = try TestContent.publicOnly()
        content.failureRules["failure.test.doom"]?.onContinue = nil
        let s = try setup(content)
        var w = s.rig.factory.newWorld(seed: 6)
        fail(&w, s.rig)
        let c = try s.recovery.choices(for: w)[2]
        XCTAssertEqual(c.option, .continueWithLoss)
        XCTAssertFalse(c.available)
        XCTAssertEqual(c.reason, "reason.recovery.still_failing")
        XCTAssertThrowsError(try s.recovery.perform(.continueWithLoss, failed: w, newSeed: 0)) {
            XCTAssertEqual($0 as? RecoveryError, .unavailable(.continueWithLoss, reason: "reason.recovery.still_failing"))
        }
    }

    /// コンテンツが失うものを書いたら、既定の喪失(去る・半分)の代わりにそれだけを適用する。
    func testLossEffectsReplaceDefaults() throws {
        var content = try TestContent.publicOnly()
        content.rewind.lossEffects = [.counter(id: "counter.test.lost", add: 1)]
        let s = try setup(content)
        var w = s.rig.factory.newWorld(seed: 7)
        fail(&w, s.rig)
        let r = try s.recovery.perform(.continueWithLoss, failed: w, newSeed: 0).world
        XCTAssertEqual(r.narrative.counters["counter.test.lost"], 1)
        XCTAssertEqual(r.people.members.count, w.people.members.count)
        XCTAssertEqual(r.inventory, w.inventory)
    }

    /// 最初から: 新しい seed の世界。前の走行の夜明けを消し、手動は残す。
    /// セーブ地点からロード: 持ち越しなし(知った事実も保存の時点)。先の夜明けを消す。
    func testRestartAndLoadSavePoint() throws {
        let s = try setup()
        var w = s.rig.factory.newWorld(seed: 8)
        try s.book.startNew(w)
        try s.book.saveManual(w, index: 0)
        _ = s.rig.playDay(&w)
        _ = s.rig.simulation.apply(.time(.sleep), to: &w)
        try s.book.autosaveDawn(w)
        var ctx = StepContext(world: w, content: s.rig.content)
        ctx.learn("fact.test.revealed")
        w = ctx.world
        fail(&w, s.rig)

        let loadChoice = try s.recovery.choices(for: w)[3]
        XCTAssertEqual(loadChoice.targets, [.dawn(day: 2), .dawn(day: 1), .manual(index: 0)])
        let loaded = try s.recovery.perform(.loadSavePoint, failed: w, target: .manual(index: 0), newSeed: 0).world
        XCTAssertEqual(loaded.clock.day, 1)
        XCTAssertFalse(loaded.knowledge.knows("fact.test.revealed"))
        XCTAssertEqual(try s.book.savePoints().map(\.slot), [.dawn(day: 1), .manual(index: 0)])
        XCTAssertThrowsError(try s.recovery.perform(.loadSavePoint, failed: w, target: .manual(index: 2), newSeed: 0))

        let fresh = try s.recovery.perform(.restart, failed: w, newSeed: 77).world
        XCTAssertEqual(fresh.seed, 77)
        XCTAssertEqual(fresh, s.rig.factory.newWorld(seed: 77))
        XCTAssertEqual(try s.book.savePoints().map(\.slot), [.dawn(day: 1), .manual(index: 0)])
        XCTAssertEqual(try s.book.load(.dawn(day: 1))?.summary.seed, 77)
        XCTAssertThrowsError(try s.recovery.choices(for: fresh)) { XCTAssertEqual($0 as? RecoveryError, .notFailed) }
    }

    /// 夜明けの保存が無いと巻き戻しは選べない(理由つき)。最初からはいつでも選べる。
    func testRewindUnavailableWithoutDawn() throws {
        let s = try setup()
        var w = s.rig.factory.newWorld(seed: 9)
        fail(&w, s.rig)
        let c = try s.recovery.choices(for: w)
        XCTAssertTrue(c[0].available)
        XCTAssertFalse(c[1].available)
        XCTAssertEqual(c[1].reason, "reason.recovery.no_dawn")
        XCTAssertFalse(c[3].available)
    }
}
