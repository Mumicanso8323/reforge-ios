import Foundation
import RFContent
import RFKernel
import RFMap
import RFRules
import RFSim
import RFSurvival
import RFTestSupport
import RFTime
import RFWorld
import XCTest

/// 掘った量で上がる項(StatDef.mined。U16・OPEN-S2・BEAT-18)。
/// 掘らなければ日ごとの進み方は変わらず、掘った回数だけ上積みが付き、絞れば上がり方が緩む。
final class MinedStatTests: XCTestCase {
    static let overlay = """
    {
      "stats": [
        { "id": "stat.test.gas2", "initial": 805, "perDay": 5, "mined": { "ores": ["coal"], "per": 2, "amount": 3 } },
        { "id": "stat.test.plain", "initial": 805, "perDay": 5 }
      ]
    }
    """

    func addDeposit(_ w: inout WorldState, _ id: String, _ cat: DepositCategory, at p: GridPoint) {
        var rng = SeededRandom(state: 7)
        var layer = w.map.surface
        _ = layer.deposits.add(DepositGenerator.make(id: DepositID(id), at: p, category: cat, rng: &rng))
        w.map.surface = layer
    }

    func mine(_ w: inout WorldState, _ id: String, times: Int) {
        var rng = SeededRandom(state: 9)
        var layer = w.map.surface
        for _ in 0..<times { _ = layer.deposits.extract(DepositID(id), rng: &rng) }
        w.map.surface = layer
    }

    func testNoMiningKeepsDailyPace() throws {
        let rig = try Fixture.rig(Self.overlay)
        var w = rig.factory.newWorld(seed: 3)
        addDeposit(&w, "deposit.test.coal", .coal, at: GridPoint(2, 2))
        _ = rig.simulation.runSteps(rig.stepsPerDay * 3, &w)
        XCTAssertEqual(w.survival.stat("stat.test.gas2"), w.survival.stat("stat.test.plain"))
        XCTAssertEqual(w.survival.stat("stat.test.plain").raw, 805 + 15)
    }

    func testMiningAddsHiddenTermAndOnlyMatchingOres() throws {
        let rig = try Fixture.rig(Self.overlay)
        var w = rig.factory.newWorld(seed: 3)
        addDeposit(&w, "deposit.test.coal", .coal, at: GridPoint(2, 2))
        addDeposit(&w, "deposit.test.iron", .iron, at: GridPoint(4, 2))
        mine(&w, "deposit.test.coal", times: 5)  // 5 回 → 2 回ぶん(per 2)の 6、端数 1 回は持ち越し
        mine(&w, "deposit.test.iron", times: 4)  // 種類が違うので数えない
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)
        let diff = w.survival.stat("stat.test.gas2").raw - w.survival.stat("stat.test.plain").raw
        XCTAssertEqual(diff, 6)
        mine(&w, "deposit.test.coal", times: 1)  // 持ち越しの 1 回と合わせて 2 回
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)
        XCTAssertEqual(w.survival.stat("stat.test.gas2").raw - w.survival.stat("stat.test.plain").raw, 9)
        // 掘らない間は増えない(上がり方が緩む)
        _ = rig.simulation.runSteps(rig.stepsPerDay, &w)
        XCTAssertEqual(w.survival.stat("stat.test.gas2").raw - w.survival.stat("stat.test.plain").raw, 9)
    }

    /// 物質の ID でも数えられる(組成に含む鉱脈)。
    func testMatchBySubstance() throws {
        let rig = try Fixture.rig("""
        { "stats": [ { "id": "stat.test.cu", "initial": 0, "mined": { "ores": ["CuS"], "amount": 10 } } ] }
        """)
        var w = rig.factory.newWorld(seed: 3)
        addDeposit(&w, "deposit.test.cu", .copper, at: GridPoint(2, 2))
        mine(&w, "deposit.test.cu", times: 2)
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)
        XCTAssertEqual(w.survival.stat("stat.test.cu").raw, 20)
    }
}
