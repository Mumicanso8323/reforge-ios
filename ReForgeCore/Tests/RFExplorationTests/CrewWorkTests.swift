import RFContent
import RFFailure
import RFKernel
import RFMap
import RFRules
import RFWorld
import XCTest

/// 人の自動化(序盤の設計 W-04)。TEST-O13 手が先・TEST-O14 働ける人数・TEST-O5 の人の速さ。
final class CrewWorkTests: XCTestCase {
    static let a: PersonID = "person.test_a"
    static let b: PersonID = "person.test_b"

    func rig() throws -> ExploreRig {
        var r = try ExploreRig { c in c.crewWork = CrewWorkDef() }
        let n = r.noahPos.point
        r.put(Self.a, n + GridPoint(0, 2))
        r.put(Self.b, n + GridPoint(0, 3))
        return r
    }

    @discardableResult
    func build(_ r: inout ExploreRig, _ kind: StructureKindID, at g: GridPoint) -> EntityID {
        let e = r.world.newEntityID()
        r.world.placements.items[e] = Placement(id: e, kind: .structure(kind), at: WorldPoint(.surface, g), facing: .north,
                                                origin: ProvenanceLedger.unknownOrigin, status: .running)
        return e
    }

    /// 焚き火を置き、燃料を seconds にする(既定 8.9 時間 =「燃えている」。12 時間の満タンは「盛ん」)。
    @discardableResult
    func fire(_ r: inout ExploreRig, at g: GridPoint, seconds: Int = 32_000) -> EntityID {
        let e = build(&r, "structure.campfire", at: g)
        var rt = StructureRuntime()
        rt.hearth = HearthState(fuel: seconds * 1000, lit: true)
        r.world.placements.items[e]?.structure = rt
        return e
    }

    func assign(_ r: inout ExploreRig, _ p: PersonID, _ a: Assignment) -> Rejection? {
        r.apply(.crew(.assign(person: p, assignment: a))).rejection
    }

    /// TEST-O13: ノアが 1 度もやっていない行為は頼めない。1 度やると頼める。巻き戻しても残る。
    func testHandFirst() throws {
        var r = try rig()
        fire(&r, at: r.noahPos.point + GridPoint(-4, 0))
        let spot = r.noahPos.point + GridPoint(1, 0)
        r.world.map[.surface]?.setTerrain("forest", at: spot)
        let gather = Assignment.gather(interaction: "interaction.pick_sticks", at: WorldPoint(.surface, spot))
        XCTAssertEqual(CrewWork.refusal(gather, for: Self.a, r.world, r.content)?.reason, "reason.assign.not_done_by_hand")
        XCTAssertEqual(assign(&r, Self.a, gather)?.reason, "reason.assign.not_done_by_hand")

        XCTAssertNil(r.interact("interaction.pick_sticks", at: spot))
        XCTAssertTrue(r.world.knowledge.handDone.contains("interaction.pick_sticks"))
        XCTAssertNil(assign(&r, Self.a, gather))
        // 仲間がやっても「手でやった」にはならない
        XCTAssertFalse(r.world.knowledge.handDone.contains("interaction.draw_water"))

        // 巻き戻し(記憶を持って)でも残る(知識の側)
        var dawn = r.world
        dawn.knowledge = KnowledgeState()
        let back = MemoryCarry.rewind(failed: r.world, dawn: dawn, content: r.content)
        XCTAssertTrue(back.knowledge.handDone.contains("interaction.pick_sticks"))
        // 保存の往復
        let data = try JSONEncoder().encode(r.world.knowledge)
        XCTAssertEqual(try JSONDecoder().decode(KnowledgeState.self, from: data), r.world.knowledge)
    }

    /// TEST-O14: シェルターの前は火の枠しか頼めない。シェルターが建つと寝床の枠(5 − ノア 1 = 4)が足される。
    func testWorkableByFireAndBeds() throws {
        var r = try rig()
        let guardA = Assignment.guardArea(center: r.noahPos, radius: 2)
        // 火も寝床も無い: 誰も働けない
        XCTAssertEqual(CrewWork.workable(r.world, r.content), 0)
        XCTAssertEqual(assign(&r, Self.a, guardA)?.reason, "reason.assign.no_slot")
        // 焚き火が燃えている: 1 人
        fire(&r, at: r.noahPos.point + GridPoint(-4, 0))
        XCTAssertEqual(CrewWork.workable(r.world, r.content), 1)
        XCTAssertNil(assign(&r, Self.a, guardA))
        XCTAssertEqual(assign(&r, Self.b, guardA)?.reason, "reason.assign.no_slot")
        // 休ませれば枠が空く
        XCTAssertNil(assign(&r, Self.a, .rest))
        XCTAssertNil(assign(&r, Self.b, guardA))
        XCTAssertNil(assign(&r, Self.a, .rest))
        // 火が「盛ん」なら 2 人
        fire(&r, at: r.noahPos.point + GridPoint(-6, 0), seconds: 40_000)
        XCTAssertEqual(CrewWork.workable(r.world, r.content), 2)
        XCTAssertNil(assign(&r, Self.a, guardA))
        // シェルター(寝床 5): 寝床の枠 4。起きている仲間は 2 人なので 2
        build(&r, "structure.shelter", at: r.noahPos.point + GridPoint(5, 0))
        XCTAssertEqual(CrewWork.bedSlots(r.world, r.content, CrewWorkDef()), 4)
        XCTAssertEqual(CrewWork.workable(r.world, r.content), 2)
        XCTAssertNil(assign(&r, Self.a, guardA))
    }

    /// 枠が減ったら、最後に頼んだ人から休む(1 ステップごとに数え直す。INV-O10 v0.4)。
    func testLastAskedRestsFirst() throws {
        var r = try rig()
        fire(&r, at: r.noahPos.point + GridPoint(-4, 0))
        let shelter = build(&r, "structure.shelter", at: r.noahPos.point + GridPoint(5, 0))
        let g = Assignment.guardArea(center: r.noahPos, radius: 2)
        XCTAssertNil(assign(&r, Self.b, g))
        XCTAssertNil(assign(&r, Self.a, g))
        XCTAssertEqual(CrewWork.working(r.world, r.content), [Self.a, Self.b])
        r.world.placements.items[shelter] = nil
        XCTAssertEqual(CrewWork.working(r.world, r.content), [Self.b])
        // 頼み直すと、その人が最後になる
        XCTAssertNil(assign(&r, Self.b, .rest))
        XCTAssertEqual(CrewWork.working(r.world, r.content), [Self.a])
        XCTAssertEqual(assign(&r, Self.b, g)?.reason, "reason.assign.no_slot")
    }

    /// 種類で数える: 同じ種類の行為を 1 度やれば、別の行為でも頼める。運ぶ・建てるは本体が決める種類。
    func testHandFamily() throws {
        var r = try ExploreRig { c in
            c.crewWork = CrewWorkDef()
            c.interactions["interaction.draw_water"]?.handFamily = "family.test.water"
            c.interactions["interaction.pick_sticks"]?.handFamily = "family.test.water"
        }
        let spot = r.noahPos.point + GridPoint(1, 1)
        r.world.map[.surface]?.setTerrain("water", at: spot)
        XCTAssertNil(r.interact("interaction.draw_water", at: spot))
        XCTAssertEqual(r.world.knowledge.handDone, ["family.test.water"])
        let def = CrewWorkDef()
        let sticks = Assignment.gather(interaction: "interaction.pick_sticks", at: WorldPoint(.surface, spot))
        XCTAssertEqual(CrewWork.family(of: sticks, def, r.content), "family.test.water")
        XCTAssertEqual(CrewWork.family(of: .haul(route: EntityID(1)), def, r.content), HandFamilyID.haul)
        XCTAssertEqual(CrewWork.family(of: .build(placement: EntityID(1)), def, r.content), HandFamilyID.build)
        XCTAssertEqual(CrewWork.refusal(.build(placement: EntityID(1)), for: Self.a, r.world, r.content)?.reason,
                       "reason.assign.not_done_by_hand")
    }

    /// 働ける人数を超えた仲間は焚き火のそばで休み、配属は残る。
    func testOverflowRestsByTheFire() throws {
        var r = try rig()
        let campfire = fire(&r, at: r.noahPos.point + GridPoint(-4, 0))
        let guardA = Assignment.guardArea(center: WorldPoint(.surface, r.noahPos.point + GridPoint(8, 0)), radius: 0)
        XCTAssertNil(assign(&r, Self.a, guardA))
        // 火が消えた(焚き火が無くなった)
        r.world.placements.items[campfire] = nil
        r.steps(200)
        XCTAssertEqual(r.world.people[Self.a]?.assignment, guardA)
        if case .guarding = r.world.people[Self.a]?.activity { XCTFail("枠の外なのに見張っている") }
    }

    /// 人の速さ: 仲間の採取はノアの 0.6 倍(運搬・建設は掛けない)。
    func testCrewGathersAtSixTenths() throws {
        var r = try rig()
        fire(&r, at: r.noahPos.point + GridPoint(-4, 0))
        let spot = r.noahPos.point + GridPoint(1, 1)
        r.world.map[.surface]?.setTerrain("water", at: spot)
        XCTAssertNil(r.interact("interaction.draw_water", at: spot))
        let gather = Assignment.gather(interaction: "interaction.draw_water", at: WorldPoint(.surface, spot))
        XCTAssertNil(assign(&r, Self.a, gather))
        XCTAssertEqual(CrewWork.gatherPermille(Self.a, r.world, r.content), 600)
        XCTAssertEqual(CrewWork.gatherPermille(.noah, r.world, r.content), 1000)
        XCTAssertEqual(CrewWork.gatherPermille(Self.b, r.world, r.content), 1000)
        // 歩いて着き、行為が始まるまで進める
        var n = 0
        while r.world.exploration.active[Self.a] == nil && n < 400 { r.steps(1); n += 1 }
        let before = r.world.exploration.active[Self.a]?.progress ?? -1
        r.steps(1)
        let after = r.world.exploration.active[Self.a]?.progress ?? -1
        XCTAssertEqual(after - before, SimStep.gameSeconds * 600 / 1000)
    }

    /// crewWork の無いコンテンツは今どおり(縛らない・速さを掛けない)。
    func testNoRulesNoLimits() throws {
        var r = try ExploreRig()
        XCTAssertNil(CrewWork.workable(r.world, r.content))
        r.put(Self.a, r.noahPos.point + GridPoint(0, 2))
        XCTAssertNil(r.apply(.crew(.assign(person: Self.a, assignment: .guardArea(center: r.noahPos, radius: 2)))).rejection)
        XCTAssertEqual(CrewWork.gatherPermille(Self.a, r.world, r.content), 1000)
    }
}
