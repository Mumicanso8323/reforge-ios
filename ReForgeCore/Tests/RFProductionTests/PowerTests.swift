import Foundation
import RFContent
import RFKernel
import RFMap
import RFMatter
@testable import RFProduction
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U16: 電力の最小の形(ModuleDef.power。原作 PowerGrid・Generator・PowerDraw)。
final class PowerTests: XCTestCase {
    static let overlay = """
    {
      "modules": [
        { "id": "millstone", "cost": [ { "item": "wood", "quantity": 1 } ], "placement": {},
          "ports": [ { "side": "south", "flow": "input" }, { "side": "north", "flow": "output" } ],
          "cycleSeconds": 9600, "batch": 2, "power": { "draw": 80 } },
        { "id": "test.generator", "cost": [ { "item": "wood", "quantity": 1 } ], "placement": {},
          "ports": [ { "side": "south", "flow": "input" } ], "cycleSeconds": 9600,
          "power": { "output": 100, "fuel": "charcoal", "fuelPerDay": 2 } },
        { "id": "test.crank", "cost": [ { "item": "wood", "quantity": 1 } ], "placement": {},
          "ports": [ { "side": "south", "flow": "input" } ], "cycleSeconds": 9600,
          "power": { "output": 50, "needsWorker": true } }
      ]
    }
    """

    func fixture() throws -> ProductionFixture {
        try ProductionFixture { db in
            try? ContentLoader.apply(json: Data(Self.overlay.utf8), to: &db, name: "u16.power")
        }
    }

    func unlock(_ w: inout WorldState) {
        w.research.unlocked.modules.formUnion(["test.generator", "test.crank"])
    }

    /// 発電機が無ければ、電力を使うモジュールは「電気が来ていない」で止まる。電力を持たないモジュールは変わらない。
    func testConsumerStopsWithoutSupplyAndRunsWithGenerator() throws {
        let f = try fixture()
        var w = f.world(charcoal: 10)
        unlock(&w)
        let mill = f.place(.millstone, 16, 16, &w)
        _ = f.run(seconds: 60, &w)
        XCTAssertEqual(w.placements.items[mill]?.status, .stopped(reason: ProductionText.noPower))
        XCTAssertEqual(w.logistics.powerDemand, 80)
        XCTAssertEqual(w.logistics.powerSupply, 0)
        // 発電機(拠点の中なので燃料は蓄えから届く)
        let gen = f.place("test.generator", 13, 15, &w)
        _ = f.run(seconds: 120, &w)
        XCTAssertEqual(w.placements.items[gen]?.status, .running)
        XCTAssertEqual(w.logistics.powerSupply, 100)
        XCTAssertNotEqual(w.placements.items[mill]?.status, .stopped(reason: ProductionText.noPower))
        XCTAssertEqual(Modules.speed(mill, w, f.content), 1000)
        // 需要が供給を上回ると半分の速さ
        let mill2 = f.place(.millstone, 19, 16, &w)
        _ = f.run(seconds: 60, &w)
        XCTAssertEqual(w.logistics.powerDemand, 160)
        XCTAssertEqual(Modules.speed(mill2, w, f.content), 500)
    }

    /// 燃料は 1 日あたり fuelPerDay 個ずつ減り、切れたら発電機は止まる。
    func testGeneratorBurnsFuelAndStopsWhenOut() throws {
        let f = try fixture()
        var w = f.world(charcoal: 2)
        unlock(&w)
        let gen = f.place("test.generator", 13, 15, &w)
        let day = f.content.clock.dayGameSeconds + f.content.clock.nightGameSeconds
        _ = f.run(seconds: Int64(day) * 2, &w)
        XCTAssertEqual(w.inventory.quantity(.charcoal, in: .base), 0)
        XCTAssertEqual(w.placements.items[gen]?.status, .stopped(reason: ProductionText.noAux))
        XCTAssertEqual(w.logistics.powerSupply, 0)
    }

    /// 人の手で回す発電機は、付いている人がいる間だけ出す。
    func testCrankNeedsWorker() throws {
        let f = try fixture()
        var w = f.world()
        unlock(&w)
        let crank = f.place("test.crank", 13, 15, &w)
        _ = f.run(seconds: 60, &w)
        XCTAssertEqual(w.placements.items[crank]?.status, .stopped(reason: ProductionText.noWorker))
        _ = f.apply(.crew(.assign(person: "person.test_a", assignment: .operate(placement: crank))), &w)
        _ = f.run(seconds: 1200, &w)
        XCTAssertEqual(w.placements.items[crank]?.status, .running)
        XCTAssertGreaterThan(w.logistics.powerSupply, 0)
    }
}
