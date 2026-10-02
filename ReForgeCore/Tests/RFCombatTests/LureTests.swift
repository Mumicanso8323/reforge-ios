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
      "raid": {"perNight": 0, "lure": {"smoke": 1, "territory": 1, "dark": 3, "threshold": 6}}}]}
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
        w.combat.felledToday = felled > 0 ? ["enemy.test.small": felled] : nil
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
        let r = Fixture.toDusk(rig, &b)
        XCTAssertEqual(b.combat.plannedRaids.count, 1)
        XCTAssertTrue(r.events.contains(.lured(enemy: "enemy.test.small")), "寄った夜は引き金 lured が出る")
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
        XCTAssertNil(w.combat.felledToday)
    }

    /// 木を伐る行為(felling)の場所が、巣(見つけていなくても)から半径以内なら、その日の縄張りに数える。
    func testFellingNearANestCounts() throws {
        let rig = try Fixture.rig(Self.lured, """
        {"enemies": [{"id": "enemy.test.small", "health": 15, "attack": 3, "drops": [], "nests": ["poi.test.den"],
          "raid": {"perNight": 0, "lure": {"territory": 1, "territoryRadius": 5, "threshold": 6}}}],
         "interactions": [{"id": "interaction.test.fell", "target": {"terrain": {"tag": "forest"}}, "seconds": 60,
                           "hold": false, "yields": [], "felling": true}]}
        """)
        var w = rig.factory.newWorld(seed: 2)
        _ = w.map[.surface]?.placements.place(MapPlacement(id: "nest.test", kind: .nest, templateID: "poi.test.den",
                                                           anchor: GridPoint(4, 4), entity: EntityID(9_999)))
        var ctx = StepContext(world: w, content: rig.content)
        let rec = ctx.record(.chose, .none)
        let sys = CombatSystem()
        sys.react(to: .interacted(person: .noah, interaction: "interaction.test.fell", at: Fixture.at(GridPoint(8, 4)),
                                  record: rec), &ctx)
        sys.react(to: .interacted(person: .noah, interaction: "interaction.test.fell", at: Fixture.at(GridPoint(20, 20)),
                                  record: rec), &ctx)
        sys.react(to: .interacted(person: .noah, interaction: "interaction.dig", at: Fixture.at(GridPoint(5, 5)),
                                  record: rec), &ctx)
        XCTAssertEqual(ctx.world.combat.felledToday, ["enemy.test.small": 1], "巣のそばで伐った 1 回だけ")
    }
}
