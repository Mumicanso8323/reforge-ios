import Foundation
import RFContent
import RFKernel
import RFNarrative
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U15 物語の核の仕組みの受け入れテスト(結合設計 BEAT-05・06・07・29・拠点の段階)。
/// 公開の試験用コンテンツ content/public/narrative/sheets.json(物語は無い。中立の ID)を使う。
final class SheetMechanicsTests: XCTestCase {
    private let ledger: SheetID = "sheet.test.ledger"
    private let verse: SheetID = "sheet.test.verse"
    private let roster: SheetID = "sheet.test.roster"

    private func world(_ rig: TestRig, facts: [FactID] = []) -> WorldState {
        var ctx = StepContext(world: rig.factory.newWorld(seed: 3), content: rig.content)
        for f in facts { ctx.learn(f) }
        return ctx.world
    }

    private func cond(_ c: Condition, _ w: WorldState, _ rig: TestRig) -> Bool? {
        ConditionEvaluator.evaluatePure(c, world: w, content: rig.content)
    }

    // MARK: - BEAT-05 記録の並びと空いた席

    /// 空いた席は並びの中で数えられ、開ける。開いたことが来歴に残り、出来事が世界を変える(文だけで終わらない)。
    func testOpeningTheEmptySlotIsAnActThatChangesTheWorld() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        // 工程表を直す前は開けない
        XCTAssertEqual(rig.simulation.apply(.narrative(.openSheet(sheet: ledger, slot: nil)), to: &w).rejection?.reason,
                       "reason.sheet.closed")
        w = world(rig, facts: ["fact.test.device_fixed"])
        let def = try XCTUnwrap(rig.content.sheets[ledger])
        XCTAssertEqual(SheetRules.emptySlots(def, w, rig.content), [4])

        var r = rig.simulation.apply(.narrative(.openSheet(sheet: ledger, slot: 2)), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(cond(.sheet(id: ledger, test: .opened(slot: 2)), w, rig), true)
        XCTAssertEqual(cond(.sheet(id: ledger, test: .emptySlotsSeen(atLeast: 1)), w, rig), false)
        XCTAssertFalse(r.events.contains { if case .eventFired("event.test.memory_seen", _) = $0 { true } else { false } })

        r = rig.simulation.apply(.narrative(.openSheet(sheet: ledger, slot: 4)), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(r.warnings, [])
        XCTAssertTrue(r.events.contains { if case .sheetOpened(_, 4, true, _) = $0 { true } else { false } })
        XCTAssertTrue(r.events.contains { if case .eventFired("event.test.memory_seen", _) = $0 { true } else { false } })
        // 世界が変わる: 仲間が覚え、配属を離れてノアのところへ来る
        let a = try XCTUnwrap(w.people["person.test_a"])
        XCTAssertTrue(a.memories.contains { $0.kind == "memory.test.kind_b" })
        XCTAssertNotNil(a.override)
        // 来歴: 空いた席を開いたこと
        let rec = try XCTUnwrap(w.ledger.records.last { $0.act == .analyzed && $0.subject == .sheet(ledger) })
        XCTAssertEqual(rec.detail["empty"], .bool(true))
        XCTAssertEqual(rec.detail["slot"], .int(4))
        // 無い席は開けない
        XCTAssertEqual(rig.simulation.apply(.narrative(.openSheet(sheet: ledger, slot: 9)), to: &w).rejection?.reason,
                       "reason.sheet.no_slot")
    }

    // MARK: - BEAT-06 工程表で技能を付ける

    func testSkillGrantAddsSkillWithOpinionsAndRefusalIsRecorded() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        XCTAssertEqual(rig.simulation.apply(.narrative(.grant(sheet: ledger, person: "person.test_a",
                                                                  skill: "skill.test.kindling")), to: &w).rejection?.reason,
                       "reason.grant.closed")
        w = world(rig, facts: ["fact.test.device_fixed"])
        // 使う: 習得の時間なしに技能が付き、仲間が思想で賛否を言う
        var r = rig.simulation.apply(.narrative(.grant(sheet: ledger, person: "person.test_a", skill: "skill.test.kindling")),
                                     to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertTrue(w.people["person.test_a"]!.skills.contains("skill.test.kindling"))
        XCTAssertTrue(r.events.contains { if case .opinion = $0 { true } else { false } })
        XCTAssertEqual(cond(.sheet(id: ledger, test: .granted(person: "person.test_a", atLeast: nil)), w, rig), true)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .used && $0.subject == .person("person.test_a") })
        // 本人が断る(思想): 技能は付かず、断ったことが本人の行為として残る
        r = rig.simulation.apply(.narrative(.grant(sheet: ledger, person: "person.test_b", skill: "skill.test.kindling")),
                                 to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertFalse(w.people["person.test_b"]!.skills.contains("skill.test.kindling"))
        XCTAssertEqual(w.narrative.sheet(ledger).declined["person.test_b"], true)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .kept && $0.actor == "person.test_b" })
        // 一員でない人には使えない
        XCTAssertEqual(rig.simulation.apply(.narrative(.grant(sheet: ledger, person: "person.test_c",
                                                                  skill: "skill.test.kindling")), to: &w).rejection?.reason,
                       "reason.grant.no_target")
    }

    func testPlayerMayChooseNotToUseTheDevice() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig, facts: ["fact.test.device_fixed"])
        let r = rig.simulation.apply(.narrative(.grant(sheet: ledger, person: "person.test_a", skill: nil)), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.narrative.sheet(ledger).declined["person.test_a"], false)
        XCTAssertEqual(cond(.sheet(id: ledger, test: .declined(person: "person.test_a", atLeast: nil)), w, rig), true)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .kept && $0.actor == .noah })
        // 後から考え直して使うことはできる
        XCTAssertNil(rig.simulation.apply(.narrative(.grant(sheet: ledger, person: "person.test_a",
                                                                skill: "skill.test.kindling")), to: &w).rejection)
    }

    // MARK: - BEAT-07 行に来歴を行に置く

    func testPlaceOwnRecordAsAnswer() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 3), content: rig.content)
        let made = ctx.record(.crafted, .item("wood"), actor: .noah, detail: ["purity": .int(7300)])
        ctx.record(.crafted, .item("wood"), actor: .noah, detail: ["purity": .int(5100)])
        var w = ctx.world
        let row = try XCTUnwrap(rig.content.sheets[verse]?.rows.first)
        XCTAssertEqual(SheetRules.answerCandidates(row, w).first?.id, w.ledger.records.last?.id, "新しい順")
        XCTAssertTrue(SheetRules.answerCandidates(row, w).contains { $0.id == made })
        XCTAssertEqual(SheetRules.measure(row.measure!, w), 2)
        XCTAssertEqual(SheetRules.measure(rig.content.sheets[verse]!.rows[1].measure!, w), 7300)

        // 合わない来歴は置けない
        XCTAssertEqual(rig.simulation.apply(.narrative(.placeAnswer(sheet: verse, row: "line.keep", record: made)),
                                            to: &w).rejection?.reason, "reason.sheet.not_an_answer")
        let r = rig.simulation.apply(.narrative(.placeAnswer(sheet: verse, row: "line.make", record: made)), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.narrative.sheet(verse).answers["line.make"], made)
        XCTAssertEqual(cond(.sheet(id: verse, test: .answered(row: "line.make", query: ProvenanceQuery(act: .crafted))), w, rig),
                       true)
        XCTAssertEqual(cond(.sheet(id: verse, test: .answered(row: "line.make", query: ProvenanceQuery(act: .died))), w, rig),
                       false)
        // 置いたことが来歴に残り、置いた来歴を指す
        let rec = try XCTUnwrap(w.ledger.records.last)
        XCTAssertEqual(rec.inputs, [made])
    }

    // MARK: - BEAT-29 選ぶ表

    func testCrewDeclareAndPlayerDecidesWhoBoards() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        XCTAssertEqual(rig.simulation.apply(.narrative(.setRosterPick(sheet: roster, person: .noah, included: true)), to: &w)
            .rejection?.reason, "reason.roster.closed")
        w = world(rig, facts: ["fact.test.roster_open"])
        // 選ぶ表を開くと、仲間が自分で言う(思想で含めない・一員なので含める)
        let r = rig.simulation.apply(.narrative(.openSheet(sheet: roster, slot: nil)), to: &w)
        XCTAssertNil(r.rejection)
        let p = w.narrative.sheet(roster)
        XCTAssertEqual(p.declared["person.test_a"], false)
        XCTAssertEqual(p.declared["person.test_b"], true)
        XCTAssertTrue(w.ledger.records.contains { $0.actor == "person.test_a" && $0.subject == .sheet(roster) })
        // 譲らない人は逆にできない
        XCTAssertEqual(rig.simulation.apply(.narrative(.setRosterPick(sheet: roster, person: "person.test_a", included: true)),
                                            to: &w).rejection?.reason, "reason.roster.firm")
        XCTAssertNil(rig.simulation.apply(.narrative(.setRosterPick(sheet: roster, person: .noah, included: true)), to: &w).rejection)
        XCTAssertEqual(cond(.sheet(id: roster, test: .included(person: nil, atLeast: 2)), w, rig), true)
        // 席は 2 つ。仲間を降ろすこともできる
        XCTAssertNil(rig.simulation.apply(.narrative(.setRosterPick(sheet: roster, person: "person.test_b", included: false)),
                                          to: &w).rejection)
        XCTAssertEqual(cond(.sheet(id: roster, test: .excluded(person: "person.test_b", atLeast: nil)), w, rig), true)
        XCTAssertNil(rig.simulation.apply(.narrative(.setRosterPick(sheet: roster, person: "person.test_b", included: true)),
                                          to: &w).rejection)
        // 確定: 来歴に含める人と含めない人
        let l = rig.simulation.apply(.narrative(.confirmRoster(sheet: roster)), to: &w)
        XCTAssertNil(l.rejection)
        XCTAssertTrue(l.events.contains { if case .rosterConfirmed = $0 { true } else { false } })
        XCTAssertEqual(cond(.sheet(id: roster, test: .locked), w, rig), true)
        XCTAssertEqual(cond(.sheet(id: roster, test: .excluded(person: "person.test_a", atLeast: nil)), w, rig), true)
        XCTAssertEqual(rig.simulation.apply(.narrative(.setRosterPick(sheet: roster, person: .noah, included: false)), to: &w)
            .rejection?.reason, "reason.roster.confirmed")
    }

    // MARK: - 拠点の段階

    func testBaseGradeFromContentConditions() throws {
        var rig = try TestRig.publicOnly()
        var content = rig.content
        content.base.grades = try JSONDecoder().decode([BaseGradeDef].self, from: Data("""
        [ { "grade": 2, "when": { "members": { "atLeast": 3 } } },
          { "grade": 3, "when": { "members": { "atLeast": 30 } } },
          { "grade": 4, "when": { "members": { "atLeast": 1 } } } ]
        """.utf8))
        rig = TestRig(content: content)
        var w = rig.factory.newWorld(seed: 1)
        XCTAssertEqual(BaseGrades.current(w, content), 2, "格 3 が成り立たなければ格 4 にも届かない")
        XCTAssertEqual(ConditionEvaluator.evaluatePure(.baseGrade(atLeast: 2), world: w, content: content), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(.baseGrade(atLeast: 3), world: w, content: content), false)
        w.base.grade = 4
        XCTAssertEqual(BaseGrades.current(w, content), 4)
    }

    // MARK: - 保存

    func testOldSaveWithoutSheetsDecodes() throws {
        var n = NarrativeState()
        let enc = try JSONEncoder().encode(n)
        XCTAssertFalse(String(decoding: enc, as: UTF8.self).contains("sheets"))
        n.updateSheet(ledger) { $0.openedSlots.insert(4) }
        let back = try JSONDecoder().decode(NarrativeState.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back, n)
        XCTAssertEqual(try JSONDecoder().decode(NarrativeState.self, from: enc).sheet(ledger), SheetProgress())
    }
}
