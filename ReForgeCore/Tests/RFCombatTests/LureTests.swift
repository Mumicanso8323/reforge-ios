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

/// 獣が寄る 3 つの入力(煙・縄張り・闇)としきい値(序盤の設計 W-02c)。
final class LureTests: XCTestCase {
    private static let lured = """
    {"enemies": [{"id": "enemy.test.small", "health": 15, "attack": 3, "drops": [],
      "steals": [{"item": "test_stash", "quantity": 1}],
      "raid": {"perNight": 0, "lure": {"smoke": 1, "territory": 1, "dark": 3, "threshold": 6,
                                       "fellingCounter": "counter.test.felled"}}}]}
    """

    private func world(_ rig: TestRig, felled: Int, fuelSeconds: Int?) -> (WorldState, EntityID) {
        var w = rig.factory.newWorld(seed: 3)
        Fixture.clearPeople(&w)
        let id = Fixture.build(&w, "structure.campfire", at: GridPoint(14, 14))
        if let f = fuelSeconds {
            var rt = StructureRuntime()
            rt.hearth = HearthState(fuel: f * 1000, lit: f > 0)
            w.placements.items[id]?.structure = rt
        }
        w.narrative.counters["counter.test.felled"] = felled
        return (w, id)
    }

    /// 合計がしきい値に届かない夜は来ず、届いた夜は必ず来る(確率で振らない)。
    func testThresholdDecidesTheNight() throws {
        let rig = try Fixture.rig(Self.lured)
        // 燃えている焚き火(煙 1)+ 伐採 4 = 5 → 来ない
        var (a, _) = world(rig, felled: 4, fuelSeconds: nil)
        _ = Fixture.toDusk(rig, &a)
        XCTAssertTrue(a.combat.plannedRaids.isEmpty)
        // 煙 1 + 伐採 5 = 6 → 来る
        var (b, _) = world(rig, felled: 5, fuelSeconds: nil)
        _ = Fixture.toDusk(rig, &b)
        XCTAssertEqual(b.combat.plannedRaids.count, 1)
        // 火が消えている(闇 3)+ 伐採 3 = 6 → 来る
        var (c, _) = world(rig, felled: 3, fuelSeconds: 0)
        _ = Fixture.toDusk(rig, &c)
        XCTAssertEqual(c.combat.plannedRaids.count, 1)
    }

    /// 日没には届かなくても、夜のうちに火が消えたら闇の重みを入れて振り直す。夜明けに伐採の数は 0 に戻る。
    func testFireGoingOutAtNightRerolls() throws {
        let rig = try Fixture.rig(Self.lured)
        var (w, id) = world(rig, felled: 3, fuelSeconds: nil)
        _ = Fixture.toDusk(rig, &w)
        XCTAssertTrue(w.combat.plannedRaids.isEmpty, "煙 1 + 伐採 3 = 4")
        var rt = w.placements.items[id]!.structure ?? StructureRuntime()
        rt.hearth = HearthState(fuel: 30_000, lit: true)
        w.placements.items[id]?.structure = rt
        _ = rig.simulation.runSteps(4, &w)
        XCTAssertEqual(w.combat.plannedRaids.count, 1, "闇 3 + 伐採 3 = 6")
        _ = Fixture.throughNight(rig, &w)
        XCTAssertEqual(w.narrative.counters["counter.test.felled"], 0)
    }
}
