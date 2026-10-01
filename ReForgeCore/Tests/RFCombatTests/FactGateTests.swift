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

/// 夜の群れと昼の出会いを、日数でなく知ったこと(事実)と見つけた巣で始め・止める(結合設計 §3.1)。
final class FactGateTests: XCTestCase {
    private func know(_ w: inout WorldState, _ facts: FactID...) {
        for f in facts { w.knowledge.facts[f] = FactRecord(learnedAt: w.clock.now, run: w.run.index, via: nil) }
    }

    /// 1 晩を日没まで進めて、今夜の群れの予定を返す。
    private func plannedTonight(_ rig: TestRig, _ w: inout WorldState) -> [PlannedRaid] {
        _ = Fixture.toDusk(rig, &w)
        return w.combat.plannedRaids
    }

    private static let gatedRaid = """
    {"enemies": [{"id": "enemy.test.small", "health": 15, "attack": 3, "drops": [],
      "steals": [{"item": "test_stash", "quantity": 1}],
      "raid": {"perNight": 10000, "requiresFact": "fact.test.first_threat", "untilFact": "fact.test.calm",
               "factModifiers": [{"fact": "fact.test.scared", "add": -10000}]}}]}
    """

    func testRaidStartsAfterTheFactAndStopsWithAnother() throws {
        let rig = try Fixture.rig(Self.gatedRaid)
        var before = rig.factory.newWorld(seed: 1)
        XCTAssertTrue(plannedTonight(rig, &before).isEmpty, "事実を知るまでは来ない(何日たっても)")

        var after = rig.factory.newWorld(seed: 1)
        know(&after, "fact.test.first_threat")
        XCTAssertEqual(plannedTonight(rig, &after).count, 1, "知った夜から来る")

        var stopped = rig.factory.newWorld(seed: 1)
        know(&stopped, "fact.test.first_threat", "fact.test.calm")
        XCTAssertTrue(plannedTonight(rig, &stopped).isEmpty, "止める事実を知ったら来ない")

        var lowered = rig.factory.newWorld(seed: 1)
        know(&lowered, "fact.test.first_threat", "fact.test.scared")
        XCTAssertTrue(plannedTonight(rig, &lowered).isEmpty, "事実で率が 0 まで下がる")
    }

    /// 巣を見つける(knowledge.discovered に入る)までは、その巣の獣は来ない。見つけたら巣から来る。
    func testRaidComesOnlyFromAKnownNest() throws {
        let json = """
        {"enemies": [{"id": "enemy.test.pack", "health": 35, "attack": 8, "drops": [], "nests": ["poi.test.den"],
          "raid": {"perNight": 10000, "requiresKnownNest": true}}]}
        """
        let rig = try Fixture.rig(json)
        func world() -> WorldState {
            var w = rig.factory.newWorld(seed: 2)
            _ = w.map[.surface]?.placements.place(MapPlacement(id: "nest.test", kind: .nest, templateID: "poi.test.den",
                                                               anchor: GridPoint(4, 4), entity: EntityID(9_999)))
            Fixture.clearPeople(&w)
            return w
        }
        var unseen = world()
        XCTAssertTrue(plannedTonight(rig, &unseen).isEmpty, "見つけていない巣からは来ない")

        var seen = world()
        seen.knowledge.discovered.insert(EntityID(9_999))
        let plan = plannedTonight(rig, &seen)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.nest, EntityID(9_999), "見つけた巣から来る")
    }

    /// 昼の出会いも事実で下がる・止まる(例: 獣の行動の記録を得たら下がる)。
    func testEncounterRateFollowsFacts() {
        let mods = [FactRateModifier(fact: .fact("fact.test.notes"), permille: 250)]
        XCTAssertEqual(FactRate.rate(8000, requires: nil, until: nil, modifiers: mods, known: []), 8000)
        XCTAssertEqual(FactRate.rate(8000, requires: nil, until: nil, modifiers: mods, known: ["fact.test.notes"]), 2000)
        XCTAssertEqual(FactRate.rate(8000, requires: .fact("fact.test.a"), until: nil, modifiers: nil, known: []), 0)
        XCTAssertEqual(FactRate.rate(8000, requires: nil, until: .fact("fact.test.b"), modifiers: nil, known: ["fact.test.b"]), 0)
    }

    func testForestEncounterStopsAfterTheFact() throws {
        let json = """
        {"enemies": [{"id": "enemy.test.pack", "health": 35, "attack": 8, "drops": [], "nocturnal": false,
          "habitats": ["forest"], "encounterPerHour": 10000, "encounterUntilFact": "fact.test.notes"}]}
        """
        let rig = try Fixture.rig(json)
        func run(knowing: Bool) -> Bool {
            var w = rig.factory.newWorld(seed: 2)
            Fixture.clearPeople(&w, except: [.noah])
            let spot = GridPoint(5, 5)
            for dy in -4...4 { for dx in -4...4 { w.map[.surface]?.setTerrain("forest", at: spot + GridPoint(dx, dy)) } }
            w.people[.noah]?.position = Fixture.at(spot)
            if knowing { know(&w, "fact.test.notes") }
            let r = rig.simulation.runSteps(240 * 6, &w)
            return r.events.contains { if case .threatAppeared = $0 { true } else { false } }
        }
        XCTAssertTrue(run(knowing: false))
        XCTAssertFalse(run(knowing: true), "記録を得たら森で出会わない")
    }
}
