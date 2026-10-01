import RFContent
import RFKernel
import RFNarrative
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class NarrativeTests: XCTestCase {
    /// 行動(事実を知る)が引き金 → 効果で世界が変わる → 連鎖した出来事が決断を出す → 決めると効果と来歴が残る。
    func testHookConditionEffectDecisionChain() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.alpha")
        var report = StepReport()
        rig.simulation.settle(&ctx, &report)
        w = ctx.world

        XCTAssertTrue(w.knowledge.knows("fact.test.beta"))
        XCTAssertTrue(w.knowledge.knows("fact.test.gamma"), "implies で連鎖する")
        XCTAssertEqual(w.narrative.counters["counter.test.chain"], 1)
        XCTAssertEqual(w.narrative.fired["event.test.chain"]?.count, 1)
        let decision = try XCTUnwrap(w.narrative.pending.first)
        XCTAssertEqual(decision.choices, ["choice.test.yes", "choice.test.no"])
        XCTAssertFalse(decision.blocking, "既定では止めない")
        XCTAssertEqual(report.warnings, [])

        let r = rig.simulation.apply(.narrative(.decide(decision: decision.id, choice: "choice.test.yes")), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertTrue(w.knowledge.knows("fact.test.revealed"))
        XCTAssertEqual(w.people["person.test_a"]?.relation.points, 5)
        // 来歴: 選んだ記録 → それを inputs に持つ「知った」記録
        let chose = try XCTUnwrap(w.ledger.records.last { $0.act == .chose && $0.subject == .choice("event.test.decision", "choice.test.yes") })
        XCTAssertTrue(chose.tags.contains("tag.test.build"))
        let learned = try XCTUnwrap(w.ledger.records.first { $0.act == .learned && $0.subject == .fact("fact.test.revealed") })
        XCTAssertTrue(learned.inputs.contains(chose.id), "効果の変化は引き金の来歴を指す")
        XCTAssertEqual(w.ledger.descendants(of: chose.id).map(\.id), [learned.id])
    }

    /// 一度きりの出来事は二度起きない。
    func testOnceEventFiresOnce() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        ctx.learn("fact.test.alpha")
        var report = StepReport()
        rig.simulation.settle(&ctx, &report)
        ctx.emit(.factLearned(fact: "fact.test.alpha", record: nil))
        rig.simulation.settle(&ctx, &report)
        XCTAssertEqual(ctx.world.narrative.fired["event.test.chain"]?.count, 1)
    }

    /// 「工業の初めて」: 最初の記録だけが firstTime に合う。
    func testFirstTimeCondition() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let q = ProvenanceQuery(act: .built, structure: "structure.test.shelter")
        let first = ctx.record(.built, .structure("structure.test.shelter", nil))
        let second = ctx.record(.built, .structure("structure.test.shelter", nil))
        XCTAssertTrue(ConditionEvaluator.evaluatePure(.firstTime(query: q), world: ctx.world, content: rig.content, trigger: first) == true)
        XCTAssertTrue(ConditionEvaluator.evaluatePure(.firstTime(query: q), world: ctx.world, content: rig.content, trigger: second) == false)
        XCTAssertEqual(ctx.world.ledger.first(.built, .structure("structure.test.shelter", nil)), first)
    }

    /// 範囲の効果: 付けると中だけに効き、半分にでき、消せる。
    func testAuraAddScaleRemove() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        EffectApplier.apply([.addAura(kind: "aura.test.smoke", at: .person(id: .noah), radius: 2, hours: nil)], &ctx, cause: nil)
        let at = try XCTUnwrap(ctx.world.people[.noah]?.position)
        XCTAssertEqual(Auras.covering(at, in: ctx.world).count, 1)
        XCTAssertEqual(Auras.covering(WorldPoint(at.layer, at.point.moved(.east, by: 3)), in: ctx.world).count, 0)
        EffectApplier.apply([.scaleAura(kind: "aura.test.smoke", permille: 500)], &ctx, cause: nil)
        XCTAssertEqual(ctx.world.auras.active.values.first?.strength, 500)
        EffectApplier.apply([.removeAura(kind: "aura.test.smoke")], &ctx, cause: nil)
        XCTAssertTrue(ctx.world.auras.active.isEmpty)
    }
}
