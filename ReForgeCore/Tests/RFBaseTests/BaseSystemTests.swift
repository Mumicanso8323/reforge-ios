import RFBase
import RFContent
import RFKernel
import RFMap
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// RFBase の受け入れテスト(F-work-units.md U8: 建造物を建てる(仲間が手伝うと速い)/ 迎えられる人数はシェルターの数)。
final class BaseSystemTests: XCTestCase {
    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .time(.sleep)
        XCTAssertEqual(BaseSystem().handle(foreign, &ctx), .notMine)
    }

    private struct Rig {
        var content: ContentDB
        var sim: Simulation
        var world: WorldState

        init(edit: (inout ContentDB) -> Void = { _ in }) throws {
            var c = try TestContent.publicOnly()
            edit(&c)
            content = c
            sim = Simulation(content: c)
            world = WorldFactory(content: c, mapGenerator: FlatMapGenerator()).newWorld(seed: 1)
            for s in ["structure.shelter", "structure.campfire", "structure.fence", "structure.storage"] {
                world.research.unlocked.structures.insert(StructureKindID(s))
            }
            give("stick", 20)
            give("plant_fiber", 10)
            give("wood", 20)
        }

        var center: GridPoint { world.map.spawn.point }

        mutating func give(_ item: ItemID, _ n: Int) {
            var ctx = StepContext(world: world, content: content)
            let r = ctx.record(.gathered, .item(item), actor: .noah)
            ctx.addStock(.item(item), n, to: .base, origin: r)
            world = ctx.world
        }

        mutating func put(_ p: PersonID, _ g: GridPoint) {
            world.people[p]?.position = WorldPoint(.surface, g)
            world.people[p]?.motion = nil
        }

        @discardableResult
        mutating func build(_ kind: StructureKindID, _ g: GridPoint) -> StepReport {
            sim.apply(.base(.build(structure: kind, at: WorldPoint(.surface, g), facing: .north)), to: &world)
        }

        var last: (EntityID, Placement)? {
            world.placements.items.sorted { $0.key < $1.key }.last.map { ($0.key, $0.value) }
        }

        /// 建ち終わるまでのステップ数。
        mutating func stepsUntilBuilt(_ id: EntityID, limit: Int = 5000) -> Int {
            var n = 0
            while world.placements.items[id]?.status != .running && n < limit {
                _ = sim.runSteps(1, &world)
                n += 1
            }
            return n
        }
    }

    /// 建てる: 費用を取り、そばにいる人が建てる。仲間(配属 build)が手伝うと速い。置いた・建てたが来歴に残る。
    func testBuildingIsFasterWithHelpers() throws {
        var solo = try Rig()
        // 他の 2 人は遠くにいる(手伝わない)
        solo.put("person.test_a", GridPoint(2, 2))
        solo.put("person.test_b", GridPoint(2, 3))
        let site = solo.center + GridPoint(3, 0)
        solo.put(.noah, site + GridPoint(1, 0))
        let r = solo.build("structure.shelter", site)
        XCTAssertNil(r.rejection)
        let (id, p) = solo.last!
        XCTAssertEqual(p.status, .underConstruction(progress: 0))
        XCTAssertEqual(solo.world.inventory.quantity("stick"), 16)
        XCTAssertEqual(solo.world.inventory.quantity("plant_fiber"), 8)
        let soloSteps = solo.stepsUntilBuilt(id)
        XCTAssertEqual(soloSteps, 7200 / 15, "1 人なら buildSeconds ちょうど")

        var team = try Rig()
        team.put(.noah, site + GridPoint(1, 0))
        team.build("structure.shelter", site)
        let (tid, _) = team.last!
        team.put("person.test_a", site + GridPoint(-1, 0))
        team.world.people["person.test_a"]?.assignment = .build(placement: tid)
        team.put("person.test_b", GridPoint(2, 2))
        let teamSteps = team.stepsUntilBuilt(tid)
        XCTAssertEqual(teamSteps, 7200 / 30, "2 人なら半分")

        // 来歴: 置いた(材料の来歴が inputs)→ 建てた(置いたの来歴が inputs)
        let placed = team.world.ledger.records.first { $0.act == .placed && $0.subject == .structure("structure.shelter", tid) }!
        let built = team.world.ledger.records.first { $0.act == .built && $0.subject == .structure("structure.shelter", tid) }!
        XCTAssertFalse(placed.inputs.isEmpty)
        XCTAssertEqual(built.inputs, [placed.id])
        XCTAssertEqual(team.world.placements.items[tid]?.origin, placed.id)
        XCTAssertNotNil(team.world.ledger.first(.built, .structure("structure.shelter", nil)))
    }

    /// 誰もそばにいなければ進まない。進みは 0...1000 で見える。
    func testNoWorkersNoProgress() throws {
        var rig = try Rig()
        for p in rig.world.people.members { rig.put(p, GridPoint(1, 1)) }
        rig.build("structure.storage", rig.center)
        let (id, _) = rig.last!
        _ = rig.sim.runSteps(50, &rig.world)
        XCTAssertEqual(rig.world.placements.items[id]?.status, .underConstruction(progress: 0))
        rig.put(.noah, rig.center + GridPoint(0, 1))
        _ = rig.sim.runSteps(120, &rig.world)
        XCTAssertEqual(rig.world.placements.items[id]?.status, .underConstruction(progress: 500))
    }

    /// 置けない: 解禁していない / 拠点の外 / 重なる / 材料が足りない。断っても何も取らない。
    func testBuildRejections() throws {
        var rig = try Rig()
        XCTAssertEqual(rig.build("structure.research_desk", rig.center).rejection?.reason, "reason.base.locked")
        XCTAssertEqual(rig.build("structure.shelter", GridPoint(1, 1)).rejection?.reason, "reason.base.outside")
        // 柵は拠点の外にも建てられる
        XCTAssertNil(rig.build("structure.fence", GridPoint(1, 1)).rejection)
        XCTAssertNil(rig.build("structure.shelter", rig.center + GridPoint(3, 0)).rejection)
        XCTAssertEqual(rig.build("structure.campfire", rig.center + GridPoint(3, 0)).rejection?.reason, "reason.base.occupied")
        var poor = try Rig()
        let wood = poor.world.inventory.quantity("wood")
        poor.world.inventory.holders[.base]?.removeAll { $0.stuff == .item("plant_fiber") }
        XCTAssertEqual(poor.build("structure.campfire", poor.center).rejection?.reason, "reason.base.missing_cost")
        XCTAssertEqual(poor.world.inventory.quantity("wood"), wood)
    }

    /// 片付けると材料は全部、同じ来歴で戻る。
    func testDemolishRefundsEverything() throws {
        var rig = try Rig()
        let before = rig.world.inventory.entries(.base)
        let wood = rig.world.inventory.quantity("wood"), fiber = rig.world.inventory.quantity("plant_fiber")
        rig.build("structure.campfire", rig.center + GridPoint(2, 2))
        let (id, _) = rig.last!
        let r = rig.sim.apply(.base(.demolish(placement: id)), to: &rig.world)
        XCTAssertNil(r.rejection)
        XCTAssertNil(rig.world.placements.items[id])
        XCTAssertEqual(rig.world.inventory.quantity("wood"), wood)
        XCTAssertEqual(rig.world.inventory.quantity("plant_fiber"), fiber)
        XCTAssertEqual(Set(rig.world.inventory.entries(.base).flatMap { $0.origins.keys }),
                       Set(before.flatMap { $0.origins.keys }))
        XCTAssertTrue(r.events.contains { if case .dismantled(id, _) = $0 { true } else { false } })
        XCTAssertEqual(rig.world.ledger.records.last?.act, .demolished)
    }

    /// 迎えられる人数はシェルターの数(収容の合計)で決まり、食料が要る。迎えると RFCrew に合流を渡す。
    func testWelcomeNeedsHousingAndFood() throws {
        var rig = try Rig()
        let guest: PersonID = "person.test_c"
        rig.world.people[guest]?.presence = .met(at: .zero)
        rig.put(guest, rig.center + GridPoint(1, 1))
        func tryWelcome(_ rig: inout Rig) -> CommandResult {
            var ctx = StepContext(world: rig.world, content: rig.content)
            let r = BaseSystem().handle(.base(.welcome(person: guest)), &ctx)
            if r == .done { rig.world = ctx.world }
            if r == .done { XCTAssertEqual(ctx.followUps.count, 1) }
            if case .crew(.joinFromEffect(let p, let cause))? = ctx.followUps.first {
                XCTAssertEqual(p, guest)
                XCTAssertEqual(rig.world.ledger.record(cause!)?.act, .rescued)
            }
            return r
        }
        // 寝床が無い(シェルター 0)
        XCTAssertEqual(tryWelcome(&rig), .rejected(Rejection("reason.base.welcome.no_room")))
        // シェルター 1 つ = 5 人まで。一員は 3 人
        rig.build("structure.shelter", rig.center + GridPoint(3, 0))
        let (sid, _) = rig.last!
        rig.put(.noah, rig.center + GridPoint(4, 1))
        _ = rig.stepsUntilBuilt(sid)
        XCTAssertEqual(BaseRules.housing(rig.world, rig.content), 5)
        // 食料が無い
        XCTAssertEqual(tryWelcome(&rig), .rejected(Rejection("reason.base.welcome.no_food")))
        rig.give("ration", 3)
        XCTAssertEqual(tryWelcome(&rig), .done)
        XCTAssertEqual(rig.world.inventory.quantity("ration"), 1)

        // 一員が収容いっぱいなら迎えられない
        var full = try Rig { c in c.structures["structure.shelter"]?.provides["housing"] = 3 }
        full.world.people[guest]?.presence = .met(at: .zero)
        full.put(guest, full.center + GridPoint(1, 1))
        full.give("ration", 3)
        full.build("structure.shelter", full.center + GridPoint(3, 0))
        let (fid, _) = full.last!
        full.put(.noah, full.center + GridPoint(4, 1))
        _ = full.stepsUntilBuilt(fid)
        XCTAssertEqual(tryWelcome(&full), .rejected(Rejection("reason.base.welcome.no_room")))
    }
}
