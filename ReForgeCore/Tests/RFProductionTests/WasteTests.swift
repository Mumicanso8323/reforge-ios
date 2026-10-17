import RFContent
import RFKernel
import RFMatter
import RFPresent
import RFProduction
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class WasteTests: XCTestCase {
    typealias F = ProductionFixture
    private let slag: ItemID = "item.test.slag"

    private func fixture(batch: Int? = nil) throws -> F {
        try F { content in
            try ContentLoader.apply(json: Data(#"""
            {"byproductItems":{"slag":"item.test.slag"},"structures":[
              {"id":"test.dump","cost":[],"buildSeconds":1,"provides":{"dump":60},"requiresBaseArea":false}
            ]}
            """#.utf8), to: &content)
            content.modules[.furnace]?.batch = batch
            content.modules[.furnace]?.cycleSeconds = Int(F.cycle)
        }
    }

    private func furnace(_ fx: F, _ w: inout WorldState, at point: GridPoint = F.base) -> EntityID {
        let id = fx.place(.furnace, point.x, point.y, &w)
        w.placements.items[id]?.module?.step = .charcoalFurnace
        w.placements.items[id]?.module?.auxPerUnit = [.charcoal: 1]
        return id
    }

    private func feed(_ id: EntityID, limestone: Bool, count: Int, _ w: inout WorldState) {
        var ctx = StepContext(world: w, content: .init())
        let matter = Matter(substance: .hematite, purity: Purity(percent: 30), stage: .ore, shape: .lump,
                            additives: limestone ? [.limestone] : [])
        ModuleRuntime.put(StockEntry(stuff: .matter(matter), quantity: count), into: &ctx.world.placements.items[id]!.module!.input)
        w = ctx.world
    }

    private func waste(_ w: WorldState, furnace: EntityID) -> Int {
        w.placements.items[furnace]?.module?.output.reduce(0) { total, entry in
            entry.stuff == .item(slag) ? total + entry.quantity : total
        } ?? 0
    }

    private func dump(_ w: inout WorldState, at point: GridPoint, status: PlacementStatus = .running) -> EntityID {
        let id = w.newEntityID()
        var placement = Placement(id: id, kind: .structure("test.dump"), at: F.wp(point.x, point.y), facing: .north,
                                  origin: ProvenanceID(0), status: status)
        placement.structure = StructureRuntime()
        w.placements.items[id] = placement
        return id
    }

    func testOnlyLimestoneSmeltingMakesOneWastePerCycleIncludingBatch() throws {
        let fx = try fixture(batch: 2)
        var w = fx.world()
        let withLimestone = furnace(fx, &w)
        feed(withLimestone, limestone: true, count: 4, &w)
        _ = fx.run(seconds: F.cycle * 2, &w)
        XCTAssertEqual(waste(w, furnace: withLimestone), 2)

        let withoutLimestone = furnace(fx, &w, at: GridPoint(18, 16))
        feed(withoutLimestone, limestone: false, count: 4, &w)
        _ = fx.run(seconds: F.cycle * 2, &w)
        XCTAssertEqual(waste(w, furnace: withoutLimestone), 0)
        XCTAssertGreaterThan(w.placements.items[withoutLimestone]?.module?.lifetimeProduced ?? 0, 0, "実際に処理した")

        let reheating = furnace(fx, &w, at: GridPoint(20, 16))
        let metal = Matter(substance: .iron, purity: Purity(percent: 80), stage: .metal, shape: .lump)
        var ctx = StepContext(world: w, content: fx.content)
        ModuleRuntime.put(StockEntry(stuff: .matter(metal), quantity: 2), into: &ctx.world.placements.items[reheating]!.module!.input)
        w = ctx.world
        _ = fx.run(seconds: F.cycle, &w)
        XCTAssertEqual(waste(w, furnace: reheating), 0)
        XCTAssertGreaterThan(w.placements.items[reheating]?.module?.lifetimeProduced ?? 0, 0, "実際に処理した")
    }

    func testWasteStopsSeparatelyWhileProductsStillLeave() throws {
        let fx = try fixture()
        var w = fx.world()
        let id = furnace(fx, &w)
        feed(id, limestone: true, count: 20, &w)
        let report = fx.run(seconds: F.cycle * 13, &w)
        XCTAssertEqual(waste(w, furnace: id), 12)
        XCTAssertEqual(w.placements.items[id]?.status, .stopped(reason: ProductionText.wasteFull))
        XCTAssertEqual(report.events.filter { $0 == .moduleStopped(placement: id, reason: ProductionText.wasteFull) }.count, 1)
        XCTAssertGreaterThan(w.inventory.quantity(where: { if case .matter = $0 { true } else { false } }), 0)
        XCTAssertLessThanOrEqual(w.placements.items[id]!.module!.outputCount - waste(w, furnace: id), 12)
        let progress = w.placements.items[id]?.module?.progress
        _ = fx.run(seconds: F.cycle, &w)
        XCTAssertEqual(w.placements.items[id]?.module?.progress, progress)
    }

    func testWasteDoesNotAutoStoreAndDumpAcceptsOnlyAdjacentBuiltStructures() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 200)
        let id = furnace(fx, &w)
        feed(id, limestone: true, count: 80, &w)
        _ = fx.run(seconds: F.cycle, &w)
        XCTAssertEqual(w.inventory.quantity(slag), 0)

        let diagonal = dump(&w, at: GridPoint(17, 17))
        let unfinished = dump(&w, at: GridPoint(15, 16), status: .underConstruction(progress: 0))
        let broken = dump(&w, at: GridPoint(16, 15), status: .broken)
        XCTAssertEqual(Dumps.adjacent(of: id, in: w, content: fx.content), [])
        XCTAssertNotNil(w.placements.items[diagonal])
        XCTAssertNotNil(w.placements.items[unfinished])
        XCTAssertNotNil(w.placements.items[broken])

        // 建造中の物の拒みは別のテストで本物の経路を通す。ここでは走らせる間、受けない状態(壊れた)にしておく。
        w.placements.items[unfinished]?.status = .broken
        let accepted = dump(&w, at: GridPoint(17, 16))
        _ = fx.run(seconds: F.cycle * 72, &w)
        XCTAssertEqual(w.placements.items[accepted]?.structure?.parameters["dump.held"], 60)
        for other in [diagonal, unfinished, broken] { XCTAssertNil(w.placements.items[other]?.structure?.parameters["dump.held"]) }
        XCTAssertEqual(waste(w, furnace: id), 12)
        XCTAssertEqual(w.placements.items[id]?.status, .stopped(reason: ProductionText.wasteFull))
        XCTAssertGreaterThan(w.placements.items[accepted]?.structure?.parameters["dump.held"] ?? 0, 0)
        let saved = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: w, content: []))
        XCTAssertEqual(try SaveCodec.decode(saved).world, w)
    }

    /// 副産物の表が空でも、どの副産物にも当たらない表でも、世界は同じに進む(W-06 より前の動きと同じ)。
    func testEmptyTableMatchesTableThatNeverMatches() throws {
        let empty = try F { $0.modules[.furnace]?.cycleSeconds = Int(F.cycle) }
        let never = try F { content in
            try ContentLoader.apply(json: Data(#"{"byproductItems":{"unused":"item.test.unused"}}"#.utf8), to: &content)
            content.modules[.furnace]?.cycleSeconds = Int(F.cycle)
        }
        func play(_ fx: F) -> WorldState {
            var world = fx.world(seed: 9)
            let id = furnace(fx, &world)
            feed(id, limestone: true, count: 50, &world)
            _ = fx.run(seconds: F.cycle * 50, &world)
            return world
        }
        let a = play(empty), b = play(never)
        XCTAssertEqual(a, b)
        let id = try XCTUnwrap(a.placements.moduleIDs.first)
        XCTAssertGreaterThan(a.placements.items[id]?.module?.lifetimeProduced ?? 0, 10)
        XCTAssertEqual(a.inventory.quantity(slag), 0)
        XCTAssertNotEqual(a.placements.items[id]?.status, .stopped(reason: ProductionText.wasteFull))
    }

    func testWorldRemainsDeterministicAndSavable() throws {
        let fx = try fixture()
        func play() -> WorldState {
            var world = fx.world(seed: 9)
            let id = furnace(fx, &world)
            feed(id, limestone: true, count: 20, &world)
            _ = fx.run(seconds: F.cycle * 13, &world)
            return world
        }
        let world = play()
        XCTAssertEqual(world, play())
        let saved = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))
        XCTAssertEqual(try SaveCodec.decode(saved).world, world)
    }

    func testDumpBuiltLaterResumesStoppedFurnace() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 200)
        let id = furnace(fx, &w)
        feed(id, limestone: true, count: 40, &w)
        _ = fx.run(seconds: F.cycle * 13, &w)
        XCTAssertEqual(w.placements.items[id]?.status, .stopped(reason: ProductionText.wasteFull))
        let late = dump(&w, at: GridPoint(17, 16))
        let report = fx.run(seconds: F.cycle * 3, &w)
        XCTAssertTrue(report.events.contains { $0 == .moduleResumed(placement: id) })
        XCTAssertGreaterThan(w.placements.items[late]?.structure?.parameters["dump.held"] ?? 0, 0)
    }

    func testMadeEqualsDumpPlusBuffer() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 200)
        let id = furnace(fx, &w)
        let d = dump(&w, at: GridPoint(17, 16))
        feed(id, limestone: true, count: 30, &w)
        _ = fx.run(seconds: F.cycle * 20, &w)
        let made = w.placements.items[id]?.module?.lifetimeProduced ?? 0
        let held = w.placements.items[d]?.structure?.parameters["dump.held"] ?? 0
        XCTAssertGreaterThan(made, 5)
        XCTAssertEqual(made, held + waste(w, furnace: id) + w.inventory.quantity(slag))
    }

    func testProductBufferIsSeparateFromWasteCount() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 200)
        let id = furnace(fx, &w)
        feed(id, limestone: true, count: 4, &w)
        var ctx = StepContext(world: w, content: fx.content)
        let product = Matter(substance: .iron, purity: Purity(percent: 80), stage: .metal, shape: .lump)
        ModuleRuntime.put(StockEntry(stuff: .item(slag), quantity: 11), into: &ctx.world.placements.items[id]!.module!.output)
        ModuleRuntime.put(StockEntry(stuff: .matter(product), quantity: 11), into: &ctx.world.placements.items[id]!.module!.output)
        w = ctx.world
        _ = fx.run(seconds: F.cycle, &w)
        XCTAssertGreaterThan(w.placements.items[id]?.module?.lifetimeProduced ?? 0, 0, "製品が 11 あっても鉱滓の数には入らない")
        XCTAssertEqual(waste(w, furnace: id), 12)
    }

    func testUnderConstructionDumpIsRejectedByRealAcceptPath() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 200)
        let id = furnace(fx, &w)
        let unfinished = dump(&w, at: GridPoint(17, 16), status: .underConstruction(progress: 0))
        feed(id, limestone: true, count: 30, &w)
        for p in w.people.members { w.people[p]?.assignment = .rest }   // 誰も建てない
        _ = fx.run(seconds: F.cycle * 20, &w)
        guard case .underConstruction = w.placements.items[unfinished]?.status else { return XCTFail("建造中のまま") }
        XCTAssertEqual(w.placements.items[unfinished]?.structure?.parameters["dump.held"] ?? 0, 0)
        XCTAssertEqual(waste(w, furnace: id), 12)
        XCTAssertEqual(w.placements.items[id]?.status, .stopped(reason: ProductionText.wasteFull))
    }

    func testStopKindKeyMatchesProductionText() {
        XCTAssertEqual(StopKind.of(reason: ProductionText.wasteFull), .wasteFull)
        XCTAssertNil(StopKind.of(reason: ProductionText.outputFull))
    }

    func testHaulerCarriesWasteAwayAndFurnaceResumes() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 200)
        let id = furnace(fx, &w, at: GridPoint(0, 16))
        feed(id, limestone: true, count: 40, &w)
        var fuel = StepContext(world: w, content: fx.content)
        ModuleRuntime.put(StockEntry(stuff: .item(.charcoal), quantity: 40), into: &fuel.world.placements.items[id]!.module!.input)
        w = fuel.world
        _ = fx.run(seconds: F.cycle, &w)   // 経路ができるまで
        for p in w.people.members where p != .noah { w.people[p]?.assignment = .rest }
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(id) && $0.to == .base })
        _ = fx.run(seconds: F.cycle * 13, &w)
        XCTAssertEqual(w.placements.items[id]?.status, .stopped(reason: ProductionText.wasteFull))
        XCTAssertEqual(w.inventory.quantity(slag), 0, "運び手が無い間は蓄えに自動では入らない")
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        let report = fx.run(seconds: 86_400, &w)
        XCTAssertGreaterThan(w.inventory.quantity(slag), 0)
        XCTAssertTrue(report.events.contains { $0 == .moduleResumed(placement: id) })
    }

    func testNightBatchMatchesSingleSteps() throws {
        let fx = try fixture()
        func play(sleep: Bool) -> (WorldState, Int) {
            var world = fx.world(seed: 5, charcoal: 100)
            let id = furnace(fx, &world)
            feed(id, limestone: true, count: 20, &world)
            _ = fx.rig.playDay(&world)
            if sleep {
                _ = fx.apply(.time(.sleep), &world)
            } else {
                var guardCount = 0
                var dawned = false
                while !dawned, guardCount < 20_000 {
                    dawned = fx.rig.simulation.runSteps(1, &world).events.contains(.dawn(day: 2))
                    guardCount += 1
                }
            }
            return (world, waste(world, furnace: id))
        }
        let slept = play(sleep: true), stepped = play(sleep: false)
        XCTAssertGreaterThan(slept.1, 0)
        XCTAssertEqual(slept.1, stepped.1)
        XCTAssertEqual(play(sleep: true).0, slept.0)
    }
}
