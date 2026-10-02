import RFContent
import RFExploration
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U19 の受け入れテスト(HNT-14): 鉱脈の種類と刃の段。硬すぎる鉱脈は理由つきで断り、刃の段が上がると掘れる。
final class MiningTierTests: XCTestCase {
    static let sharp: FactID = "fact.test.sharp_blade"

    func rig() throws -> ExploreRig {
        try ExploreRig { c in
            c.mining = MiningDef(blades: [BladeTier(tier: 1, when: .always),
                                          BladeTier(tier: 2, when: .known(expr: .fact(Self.sharp)))],
                                 hardness: [DepositHardness(category: .rare, tier: 2, reason: "reason.test.too_hard")])
        }
    }

    func put(_ rig: inout ExploreRig, _ cat: DepositCategory, _ id: DepositID, dy: Int = 1) -> GridPoint {
        let spot = rig.noahPos.point + GridPoint(0, dy)
        var rng = SeededRandom(state: 5)
        _ = rig.world.map[.surface]?.deposits.add(DepositGenerator.make(id: id, at: spot, category: cat, rng: &rng))
        return spot
    }

    func testTooHardRefusesWithReasonUntilBladeTierRises() throws {
        var r = try rig()
        let spot = put(&r, .rare, "deposit.test.hard")
        let rej = r.interact("interaction.mine_by_hand", at: spot)
        XCTAssertEqual(rej?.reason, "reason.test.too_hard")
        XCTAssertEqual(rej?.detail["need"], .int(2))
        XCTAssertEqual(rej?.detail["have"], .int(1))
        XCTAssertEqual(r.records(.mined).count, 0)
        var ctx = StepContext(world: r.world, content: r.content)
        ctx.learn(Self.sharp)
        r.world = ctx.world
        XCTAssertEqual(MiningRules.bladeTier(world: r.world, content: r.content), 2)
        XCTAssertNil(r.interact("interaction.mine_by_hand", at: spot))
        XCTAssertEqual(r.records(.mined).count, 1)
    }

    func testSoftDepositNeedsNoBlade() throws {
        var r = try rig()
        let spot = put(&r, .iron, "deposit.test.soft")
        XCTAssertNil(r.interact("interaction.mine_by_hand", at: spot))
    }

    /// 行為の側の条件: 掘れる種類と、行為に要る刃の段(既定の理由)。
    func testInteractionDepositCategoriesAndBladeTier() throws {
        var r = try rig()
        var def = r.content.interactions["interaction.mine_by_hand"]!
        def.depositCategories = [.copper]
        r.content.interactions[def.id] = def
        r.sim = Simulation(content: r.content)
        let iron = put(&r, .iron, "deposit.test.iron")
        XCTAssertEqual(r.interact("interaction.mine_by_hand", at: iron)?.reason, "reason.explore.no_target")
        def.depositCategories = nil
        def.bladeTier = 3
        r.content.interactions[def.id] = def
        r.sim = Simulation(content: r.content)
        XCTAssertEqual(r.interact("interaction.mine_by_hand", at: iron)?.reason, MiningDef.tooHardDefault)
    }

    /// 掘る規則の無いコンテンツは今までどおり(どれでも掘れる)。
    func testNoMiningRulesKeepsOldBehavior() throws {
        var r = try ExploreRig()
        let spot = put(&r, .rare, "deposit.test.rare")
        XCTAssertNil(r.interact("interaction.mine_by_hand", at: spot))
    }
}
