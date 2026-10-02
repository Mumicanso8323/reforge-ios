import Foundation
import RFCombat
import RFContent
import RFKernel
import RFMap
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U16: 人の集団どうしの戦い(効果 groupBattle。D11)。1 次元の帯を人と人で使う。
final class GroupBattleTests: XCTestCase {
    let fort: GroupID = "group.test.fort"

    func setUp(_ rig: TestRig, foeHealth: Int64) -> WorldState {
        var w = rig.factory.newWorld(seed: 4)
        Fixture.clearPeople(&w, except: [.noah])
        Fixture.arm(&w, .noah)
        let noahAt = w.people[.noah]!.position!
        for (i, id) in ["person.test_f1", "person.test_f2"].enumerated() {
            var ps = PersonState(id: PersonID(id), presence: .met(at: .zero))
            ps.group = fort
            ps.position = WorldPoint(noahAt.layer, GridPoint(noahAt.point.x + 2, noahAt.point.y + i))
            ps.body.health = Milli(raw: foeHealth)
            w.people[PersonID(id)] = ps
        }
        return w
    }

    func fight(_ rig: TestRig, _ w: inout WorldState, lethal: Bool) -> StepReport {
        var ctx = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.groupBattle(group: fort, at: .person(id: .noah), lethal: lethal)], &ctx, cause: nil)
        w = ctx.world
        var r = StepReport()
        for c in ctx.followUps { r.merge(rig.simulation.apply(c, to: &w)) }
        for _ in 0..<400 where !w.combat.battles.isEmpty { r.merge(rig.simulation.runSteps(1, &w)) }
        r.merge(rig.simulation.runSteps(2, &w))
        return r
    }

    /// 死ぬ戦い: 倒れた相手は死に、来歴に死因が残り、集団の旗で結果が分かる。
    func testLethalGroupBattleKillsAndFlagsResult() throws {
        let rig = try Fixture.rig()
        var w = setUp(rig, foeHealth: 50_000)
        let r = fight(rig, &w, lethal: true)
        let started = try XCTUnwrap(r.events.first { if case .battleStarted = $0 { true } else { false } })
        guard case .battleStarted(_, let rec) = started else { return }
        XCTAssertEqual(w.ledger.record(rec)?.detail["group"], .string(fort.rawValue))
        XCTAssertTrue(r.events.contains { if case .battleEnded(_, true, _, _) = $0 { true } else { false } })
        XCTAssertEqual(w.combat.lastBattle?.kind, .group(fort))
        XCTAssertTrue(w.people.groups[fort]?.flags.contains("battle.won") ?? false)
        let dead = ["person.test_f1", "person.test_f2"].filter { w.people[PersonID($0)]?.presence.isAlive == false }
        XCTAssertFalse(dead.isEmpty, "死ぬ戦いで倒れた相手は死ぬ")
        XCTAssertTrue(w.people[.noah]!.presence.isAlive)
    }

    /// 死なない戦い: 相手は倒れても生きている(傷を負う)。
    func testNonLethalGroupBattleLeavesFoesAlive() throws {
        let rig = try Fixture.rig()
        var w = setUp(rig, foeHealth: 50_000)
        _ = fight(rig, &w, lethal: false)
        XCTAssertTrue(w.people.groups[fort]?.flags.contains("battle.won") ?? false)
        for id in ["person.test_f1", "person.test_f2"] { XCTAssertTrue(w.people[PersonID(id)]!.presence.isAlive) }
    }

    /// 相手の集団に戦える人がいなければ戦いにならない(断る)。
    func testNoFoesRejected() throws {
        let rig = try Fixture.rig()
        var w = rig.factory.newWorld(seed: 4)
        let r = rig.simulation.apply(.combat(.startGroupBattle(group: fort, near: w.people[.noah]!.position!, members: nil,
                                                               lethal: true, cause: nil)), to: &w)
        XCTAssertNotNil(r.rejection)
    }
}
