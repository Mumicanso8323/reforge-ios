import RFContent
import RFKernel
import RFLogistics
import RFMap
import RFMatter
import RFProduction
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// RFLogistics の受け入れテスト(離れていれば仲間が運ぶ: 1 人 1 日 10 個、距離 8 マスを超えると 5 マスごとに 2 割落ちる)。
final class LogisticsSystemTests: XCTestCase {
    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(LogisticsSystem().handle(foreign, &ctx), .notMine)
    }

    func testDistanceFactor() {
        XCTAssertEqual(HaulRules.factor(distance: 0), 1000)
        XCTAssertEqual(HaulRules.factor(distance: 8), 1000)
        XCTAssertEqual(HaulRules.factor(distance: 9), 800)
        XCTAssertEqual(HaulRules.factor(distance: 13), 800)
        XCTAssertEqual(HaulRules.factor(distance: 14), 640)
        XCTAssertEqual(HaulRules.perDay(crewMilli: 1000, distance: 3), 10, "1 人 1 日 10 個")
        XCTAssertEqual(HaulRules.perDay(crewMilli: 2000, distance: 14), 12)
    }

    /// 札の次の段を離して置くと、その間が自動で運搬の経路になり、仲間が運ぶ。
    func testGapBecomesHaulRouteAndCrewCarries() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let dep = Deposit(id: "deposit.test", position: GridPoint(4, 16), category: .iron, appearanceVariant: 0,
                          composition: [DepositComponent(.fe2o3, Purity(percent: 30))], extractions: 70)
        w.map[.surface]?.deposits.add(dep)
        _ = rig.simulation.apply(.invention(.makeDesign(steps: [.minehead, .charcoalFurnace])), to: &w)
        let d = try XCTUnwrap(w.invention.designs.keys.first)
        XCTAssertNil(rig.simulation.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: wp(4, 16), facing: .east)), to: &w).rejection)
        XCTAssertNil(rig.simulation.apply(.production(.placeFromDesign(design: d, stepIndex: 1, at: wp(16, 16), facing: .east)), to: &w).rejection)
        let mine = w.placements.at(wp(4, 16))[0], furnace = w.placements.at(wp(16, 16))[0]
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(mine) })
        XCTAssertEqual(route.to, .placement(furnace))
        XCTAssertEqual(route.origin, .auto)
        XCTAssertEqual(route.distance, 12)
        XCTAssertEqual(route.factorPermille, 800)
        XCTAssertEqual(route.path.first, GridPoint(4, 16))
        XCTAssertEqual(route.path.last, GridPoint(16, 16))
        // 拠点の中の炉は燃料を蓄えから直に取る(経路は要らない)
        XCTAssertFalse(w.logistics.routes.values.contains { $0.to == .placement(furnace) && $0.from == .base })

        // 運ぶ人がいなければ運ばない(運んでいる人 = activity が carrying の一員。RFCrew が歩かせる)
        _ = rig.simulation.runSteps(Int(2 * 9600 / SimStep.gameSeconds), &w)
        XCTAssertEqual(w.logistics.routes[route.id]!.movedToday, 0)
        XCTAssertEqual(w.logistics.routes[route.id]!.blocked, HaulRules.noHaulers)
        // 2 人が運ぶと、鉱石が炉へ届いて炉が動く
        for p in ["person.test_a", "person.test_b"] as [PersonID] { w.people[p]?.activity = .carrying(route: route.id) }
        _ = rig.simulation.runSteps(Int(8 * 3600 / SimStep.gameSeconds), &w)
        XCTAssertGreaterThan(w.logistics.routes[route.id]!.movedToday, 0)
        XCTAssertNil(w.logistics.routes[route.id]!.blocked)
        XCTAssertGreaterThan(w.placements.items[furnace]!.module!.lifetimeProduced, 0, "運ばれた鉱石で炉が動く")
        // 専任の配属は表示用に写す
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertEqual(w.logistics.routes[route.id]!.haulers, ["person.test_a"])
        // 見込み: 専任 1 人 + 配属の無い 1 人(経路 1 本)・距離 12 → 1 日 16 個
        XCTAssertEqual(LogisticsQueries.perDay(route.id, world: w), 16)
    }

    /// 1 人 1 日(昼)10 個 × 距離の落ち。
    func testHaulRateIsTenPerPersonPerDayWithDistanceFalloff() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        // 拠点(x 11〜21)から 11 マス離れた叩き台。出口に板を 40 枚溜めておく(行き先が無いので拠点へ運ぶ)
        XCTAssertNil(rig.simulation.apply(.production(.place(module: .anvil, at: wp(0, 16), facing: .east)), to: &w).rejection)
        let anvil = w.placements.at(wp(0, 16))[0]
        var ctx = StepContext(world: w, content: rig.content)
        let plate = Matter(substance: .iron, purity: Purity(percent: 50), stage: .metal, shape: .plate)
        ModuleRuntime.put(StockEntry(stuff: .matter(plate), quantity: 40), into: &ctx.world.placements.items[anvil]!.module!.output)
        w = ctx.world
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(anvil) && $0.to == .base })
        XCTAssertEqual(route.distance, 11)
        XCTAssertEqual(route.factorPermille, 800)
        for p in ["person.test_a", "person.test_b"] as [PersonID] { w.people[p]?.activity = .carrying(route: route.id) }
        _ = rig.simulation.runSteps(Int(8 * 3600 / SimStep.gameSeconds), &w)
        let moved = w.logistics.routes[route.id]!.movedToday
        XCTAssertTrue((15...16).contains(moved), "2 人 × 10 個 × 0.8 = 16(\(moved))")
        XCTAssertEqual(w.inventory.quantity(where: { if case .matter(let m) = $0 { m.shape == .plate } else { false } }), moved)
    }

    /// 離れたモジュールには拠点から燃料が運ばれ、行き先の無い物は拠点へ運ばれる(蓄えに入ると冷える)。
    func testRemoteModulesGetSuppliedAndDeliver() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.addStock(.item(.charcoal), 10, to: .base)
        w = ctx.world
        let furnaceAt = wp(3, 3)
        _ = rig.simulation.apply(.invention(.makeDesign(steps: [.charcoalFurnace])), to: &w)
        let d = try XCTUnwrap(w.invention.designs.keys.first)
        XCTAssertNil(rig.simulation.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: furnaceAt, facing: .east)), to: &w).rejection)
        let furnace = w.placements.at(furnaceAt)[0]
        ctx = StepContext(world: w, content: rig.content)
        ModuleRuntime.put(StockEntry(stuff: .matter(.ironOre(purity: Purity(percent: 30))), quantity: 2),
                          into: &ctx.world.placements.items[furnace]!.module!.input)
        w = ctx.world
        _ = rig.simulation.runSteps(1, &w)
        let supply = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .base && $0.to == .placement(furnace) })
        let deliver = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(furnace) && $0.to == .base })
        w.people["person.test_a"]?.activity = .carrying(route: supply.id)
        w.people["person.test_b"]?.activity = .carrying(route: deliver.id)
        _ = rig.simulation.runSteps(Int(26 * 3600 / SimStep.gameSeconds), &w)
        let lumps = w.inventory.entries(.base).filter { if case .matter(let m) = $0.stuff { m.stage == .metal } else { false } }
        XCTAssertEqual(lumps.reduce(0) { $0 + $1.quantity }, 2)
        if case .matter(let m) = lumps.first?.stuff { XCTAssertEqual(m.thermal, .airCooled, "蓄えに入ると冷える") }
    }

    func testManualLinkAndUnlink() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        _ = rig.simulation.apply(.production(.place(module: .anvil, at: wp(14, 16), facing: .east)), to: &w)
        _ = rig.simulation.apply(.production(.place(module: .anvil, at: wp(18, 16), facing: .east)), to: &w)
        let a = w.placements.at(wp(14, 16))[0], b = w.placements.at(wp(18, 16))[0]
        XCTAssertNil(rig.simulation.apply(.logistics(.connect(from: a, to: b)), to: &w).rejection)
        _ = rig.simulation.runSteps(1, &w)
        let r = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(a) })
        XCTAssertEqual(r.origin, .manual)
        XCTAssertEqual(r.distance, 4)
        XCTAssertEqual(rig.simulation.apply(.logistics(.connect(from: a, to: a)), to: &w).rejection?.reason, HaulRules.sameEnds)
        XCTAssertNil(rig.simulation.apply(.logistics(.disconnect(route: r.id)), to: &w).rejection)
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertNil(w.logistics.routes[r.id])
        // 片付けると経路も消える
        _ = rig.simulation.apply(.logistics(.connect(from: a, to: b)), to: &w)
        _ = rig.simulation.apply(.production(.dismantle(placement: b)), to: &w)
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertFalse(w.logistics.routes.values.contains { $0.to == .placement(b) })
    }

    // MARK: 道具

    func world(_ rig: TestRig) -> WorldState {
        var w = rig.factory.newWorld(seed: 3)
        for m: ModuleKindID in [.minehead, .furnace, .anvil] { w.research.unlocked.modules.insert(m) }
        var ctx = StepContext(world: w, content: rig.content)
        ctx.addStock(.item(.wood), 20, to: .base)
        ctx.addStock(.item(.charcoal), 20, to: .base)
        w = ctx.world
        return w
    }

    func wp(_ x: Int, _ y: Int) -> WorldPoint { WorldPoint(.surface, GridPoint(x, y)) }
}
