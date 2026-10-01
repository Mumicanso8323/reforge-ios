import RFContent
import RFKernel
import RFMap
import RFMatter
import RFProduction
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U16: 置いた物を壊す効果(destroyPlacements)と、直す(repair)。
final class DestructionTests: XCTestCase {
    /// 効果は持ち主のシステムへのコマンドになる(モジュールは生産、建造物は拠点)。
    func testEffectQueuesCommandsForOwners() throws {
        let f = try ProductionFixture()
        let w = f.world()
        var ctx = StepContext(world: w, content: f.content)
        let at = ProductionFixture.wp(16, 16)
        EffectApplier.apply([.destroyPlacements(near: .point(at: at), radius: 2, module: "millstone")], &ctx, cause: nil)
        XCTAssertEqual(ctx.followUps, [.production(.destroyFromEffect(near: at, radius: 2, module: "millstone", max: nil,
                                                                       cause: nil))])
        ctx.followUps = []
        EffectApplier.apply([.destroyPlacements(near: .point(at: at), radius: 1)], &ctx, cause: nil)
        XCTAssertEqual(ctx.followUps.count, 2)
    }

    /// 近いものから壊れ、地図に残って止まり、来歴に残る。直せば動き、片付ければ材料が全部戻る。
    func testDestroyNearestLeaveOnMapAndRepair() throws {
        let f = try ProductionFixture()
        var w = f.world(wood: 10)
        let near = f.place(.millstone, 16, 16, &w)
        let far = f.place(.millstone, 19, 16, &w)
        let woodAfterPlacing = w.inventory.quantity(.wood, in: .base)
        let r = f.apply(.production(.destroyFromEffect(near: ProductionFixture.wp(15, 16), radius: 5, module: nil, max: 1,
                                                       cause: nil)), &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.placements.items[near]?.status, .broken)
        XCTAssertNotEqual(w.placements.items[far]?.status, .broken, "遠い方は壊れない")
        let rec = try XCTUnwrap(w.placements.items[near]?.destroyedBy)
        XCTAssertEqual(w.ledger.record(rec)?.act, .destroyed)
        XCTAssertTrue(w.ledger.record(rec)!.inputs.contains(w.placements.items[near]!.origin))
        XCTAssertTrue(r.events.contains(.placementDestroyed(placement: near, record: rec)))
        // 壊れている間は動かない
        _ = f.run(seconds: 3600, &w)
        XCTAssertEqual(w.placements.items[near]?.status, .broken)
        // 直す: 置くときと同じ材料を払う
        let rr = f.apply(.production(.repair(placement: near)), &w)
        XCTAssertNil(rr.rejection)
        XCTAssertNotEqual(w.placements.items[near]?.status, .broken)
        XCTAssertNil(w.placements.items[near]?.destroyedBy)
        XCTAssertEqual(w.inventory.quantity(.wood, in: .base), woodAfterPlacing - 1)
        let repaired = try XCTUnwrap(w.ledger.records.last { $0.act == .repaired })
        XCTAssertTrue(repaired.inputs.contains(rec))
        // 直したものを片付けると、2 回分の材料が戻る
        XCTAssertEqual(f.apply(.production(.repair(placement: near)), &w).rejection?.reason, ProductionText.notBroken)
        _ = f.apply(.production(.dismantle(placement: near)), &w)
        XCTAssertEqual(w.inventory.quantity(.wood, in: .base), woodAfterPlacing + 1)
    }
}
