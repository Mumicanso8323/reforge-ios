import Foundation
import RFContent
import RFExploration
import RFKernel
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U19 の受け入れテスト(HNT-08 遠くの灯り): 効果 beacon が地図に光の点を置き、clearBeacon で消える。
/// 画面には MapView.beacons で届く。古いセーブ(beacons の無い探索の状態)も読める。
final class BeaconTests: XCTestCase {
    func testBeaconEffectPlacesAndClearsLightThroughStandardSystems() throws {
        let rig = try ExploreRig()
        var ctx = StepContext(world: rig.world, content: rig.content)
        let cause = ctx.record(.chose, .none)
        EffectApplier.apply([.beacon(id: "beacon.test.far", at: .base)], &ctx, cause: cause)
        var r = StepReport()
        rig.sim.settle(&ctx, &r)
        XCTAssertEqual(r.warnings, [])
        let center = try XCTUnwrap(Places.resolve(.base, world: ctx.world, trigger: nil))
        XCTAssertEqual(ctx.world.exploration.beacons["beacon.test.far"], center)
        XCTAssertTrue(r.changes.dirtyTiles.contains(center), "光の点のマスの区画を描き直す")

        let frame = FrameBuilder(content: rig.content).build(ctx.world, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(frame.map.beacons, [center.point])

        EffectApplier.apply([.clearBeacon(id: "beacon.test.far")], &ctx, cause: cause)
        var r2 = StepReport()
        rig.sim.settle(&ctx, &r2)
        XCTAssertEqual(r2.warnings, [])
        XCTAssertTrue(ctx.world.exploration.beacons.isEmpty)
        XCTAssertEqual(FrameBuilder(content: rig.content).build(ctx.world, revision: 2, previous: frame, report: r2).map.beacons, [])
    }

    func testOldExplorationStateWithoutBeaconsDecodes() throws {
        var s = ExplorationState()
        s.range = 3
        s.beacons["beacon.test.a"] = WorldPoint(.surface, GridPoint(1, 2))
        let data = try JSONEncoder().encode(s)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["beacons"])
        obj["beacons"] = nil
        let old = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(ExplorationState.self, from: old)
        XCTAssertEqual(back.range, 3)
        XCTAssertEqual(back.beacons, [:], "古いセーブは光の点なしで読む")
        XCTAssertEqual(try JSONDecoder().decode(ExplorationState.self, from: data), s, "新しい形は往復する")
    }
}
