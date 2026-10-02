import RFContent
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// 夜の地図の灯りの範囲(VisionRadiusRule.lightAreas。W-02b)。
final class HearthLightTests: XCTestCase {
    func testLightAreasFollowHearthLevel() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        let id = w.newEntityID()
        let c = w.map.spawn.point
        var p = Placement(id: id, kind: .structure("structure.campfire"), at: WorldPoint(.surface, c), facing: .north,
                          origin: ProvenanceLedger.unknownOrigin, status: .running)
        var rt = StructureRuntime()
        rt.hearth = HearthState(fuel: 43_200_000, lit: true)
        p.structure = rt
        w.placements.items[id] = p
        func areas() -> [VisionArea] { VisionRadiusRule.lightAreas(w, content: rig.content, layer: .surface) }
        XCTAssertEqual(areas(), [VisionArea(center: c, radius: 5)])
        XCTAssertTrue(areas()[0].contains(c + GridPoint(5, 0)))
        XCTAssertFalse(areas()[0].contains(c + GridPoint(6, 0)), "灯りの外は範囲に入らない")
        w.placements.items[id]?.structure?.hearth = HearthState(fuel: 3_600_000, lit: true)
        XCTAssertEqual(areas(), [VisionArea(center: c, radius: 2)], "くすぶりで縮む")
        XCTAssertFalse(areas()[0].contains(c + GridPoint(3, 0)))
        w.placements.items[id]?.structure?.hearth = HearthState()
        XCTAssertTrue(areas().isEmpty, "消えれば灯りは無い")
    }
}
