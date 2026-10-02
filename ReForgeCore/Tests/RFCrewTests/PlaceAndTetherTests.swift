import Foundation
import RFContent
import RFCrew
import RFKernel
import RFMap
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U16: 居場所(PersonDef.home)・人の距離の縛り(PersonDef.tether)・範囲の距離の縛り(AuraDef.requiresNear)。
final class PlaceAndTetherTests: XCTestCase {
    static let overlay = """
    {
      "people": [
        { "id": "person.test_a", "name": "person:person.test_a", "specialties": ["smith"], "ideology": { "axis.test.make": 3 },
          "tether": { "person": "person.noah", "radius": 3 } },
        { "id": "person.test_r", "name": "person:person.test_a", "specialties": [], "ideology": {}, "home": "site.test.fort" },
        { "id": "person.test_q", "name": "person:person.test_a", "specialties": [], "ideology": {},
          "auras": ["aura.test.calm"] }
      ],
      "auras": [
        { "id": "aura.test.calm", "modifiers": [ { "repelEnemies": {} } ], "radius": 2,
          "requiresNear": { "person": "person.noah", "radius": 4 } }
      ]
    }
    """

    func rig() throws -> TestRig {
        var db = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(Self.overlay.utf8), to: &db, name: "u16")
        return TestRig(content: db)
    }

    func at(_ w: WorldState, _ dx: Int, _ dy: Int) -> WorldPoint {
        WorldPoint(w.map.spawn.layer, GridPoint(w.map.spawn.point.x + dx, w.map.spawn.point.y + dy))
    }

    /// 縛る人(ノア)から遠い間は働けない(速さ 0。生産は付いていないのと同じ)。近づけば普通に働く。
    func testTetheredPersonWorksOnlyNearAnchor() throws {
        let rig = try rig()
        var w = rig.factory.newWorld(seed: 1)
        let id = w.newEntityID()
        w.placements.items[id] = Placement(id: id, kind: .module("furnace"), at: at(w, 8, 0), facing: .north,
                                           origin: ProvenanceLedger.unknownOrigin, status: .running)
        w.placements.items[id]?.module = ModuleRuntime(design: nil, step: nil)
        _ = rig.simulation.apply(.crew(.assign(person: "person.test_a", assignment: .operate(placement: id))), to: &w)
        _ = rig.simulation.runSteps(60, &w)
        XCTAssertEqual(w.people["person.test_a"]!.activity, .working(at: id))
        XCTAssertEqual(w.people["person.test_a"]!.workSpeed, 0, "ノアから 3 マスより遠い")
        XCTAssertEqual(w.people.workSpeedPermille(at: id), 0)
        // ノアがそばへ行くと働ける
        _ = rig.simulation.apply(.crew(.walk(to: at(w, 7, 1))), to: &w)
        _ = rig.simulation.runSteps(80, &w)
        XCTAssertEqual(w.people["person.test_a"]!.workSpeed, 1300)
    }

    /// まだ会っていない人は、居場所の POI に置かれる(会う前に動かさない)。
    func testUnmetPersonLivesAtHomePOI() throws {
        let rig = try rig()
        var w = rig.factory.newWorld(seed: 1)
        let e = w.newEntityID()
        let fortAt = GridPoint(w.map.spawn.point.x + 10, w.map.spawn.point.y + 10)
        var layer = w.map.surface
        XCTAssertTrue(layer.placements.place(MapPlacement(id: "site.test.fort", kind: .settlement, templateID: "site.test.fort",
                                                          anchor: fortAt, footprint: .rect(width: 2, height: 2),
                                                          isDiscovered: false, entity: e)))
        w.map.surface = layer
        w.people["person.test_r"] = PersonState(id: "person.test_r", presence: .unmet)
        _ = rig.simulation.runSteps(2, &w)
        XCTAssertEqual(w.people["person.test_r"]!.position, WorldPoint(.surface, fortAt))
        XCTAssertFalse(w.people.membersOnMap.contains("person.test_r"))
    }

    /// 範囲の距離の縛り: 中心の人がノアのそばにいる間だけ、獣を寄せない。
    func testAuraWorksOnlyWhileSourceNearAnchor() throws {
        let rig = try rig()
        var w = rig.factory.newWorld(seed: 1)
        var ps = PersonState(id: "person.test_q", presence: .member(since: .zero))
        ps.position = at(w, 2, 0)
        w.people["person.test_q"] = ps
        _ = rig.simulation.runSteps(1, &w)
        let spot = at(w, 3, 0)
        XCTAssertTrue(Auras.repelsEnemies(at: spot, in: w, content: rig.content))
        let far = at(w, 9, 0)
        w.people["person.test_q"]?.position = far
        XCTAssertFalse(Auras.repelsEnemies(at: at(w, 10, 0), in: w, content: rig.content), "ノアから 4 マスより遠い")
        XCTAssertTrue(Auras.covering(at(w, 10, 0), in: w).contains { $0.kind == "aura.test.calm" }, "範囲そのものは残る")
    }
}
