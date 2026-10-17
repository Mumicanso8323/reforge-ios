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

    /// 運搬の数はコンテンツの "hauling" で変えられる(省略した値は R1 の既定)。
    func testHaulingNumbersComeFromContent() throws {
        var c = try TestContent.publicOnly()
        XCTAssertNil(c.hauling)
        try ContentLoader.apply(json: Data(#"{ "hauling": { "perPersonPerDay": 20, "freeDistance": 4 } }"#.utf8), to: &c)
        XCTAssertEqual(c.hauling, HaulingDef(perPersonPerDay: 20, freeDistance: 4))
        XCTAssertEqual(HaulRules.factor(distance: 5, c.hauling), 800, "4 マスを超えたら落ちる")
        XCTAssertEqual(HaulRules.factor(distance: 10, c.hauling), 640, "段の長さは既定の 5")
        XCTAssertEqual(HaulRules.perDay(crewMilli: 1000, distance: 3, c.hauling), 20)
        // 経路の落ちと運ぶ速さにも効く
        let rig = TestRig(content: c)
        var w = world(rig)
        XCTAssertNil(rig.simulation.apply(.production(.place(module: .anvil, at: wp(0, 16), facing: .east)), to: &w).rejection)
        let anvil = w.placements.at(wp(0, 16))[0]
        var ctx = StepContext(world: w, content: rig.content)
        let plate = Matter(substance: .iron, purity: Purity(percent: 50), stage: .metal, shape: .plate)
        ModuleRuntime.put(StockEntry(stuff: .matter(plate), quantity: 40), into: &ctx.world.placements.items[anvil]!.module!.output)
        w = ctx.world
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(anvil) && $0.to == .base })
        XCTAssertEqual(route.distance, 11)
        XCTAssertEqual(route.factorPermille, 640)
        XCTAssertTrue(route.waiting, "運ぶ物がある(共同の手を回す目安)")
        restAll(&w)   // 配属の無い仲間は昼に共同の手として運ぶ(RFCrew)ので、1 人分を見るため休ませる
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        _ = rig.simulation.runSteps(Int(8 * 3600 / SimStep.gameSeconds), &w)
        XCTAssertTrue((12...13).contains(w.logistics.routes[route.id]!.movedToday), "1 人 × 20 個 × 0.64 ≒ 12.8")
        // 空腹など(U4 の作業の速さ)で運ぶ量も落ちる
        XCTAssertEqual(LogisticsQueries.perDay(route.id, world: w, content: c), 12)
        w.survival.work["person.test_a"] = 500
        XCTAssertEqual(LogisticsQueries.perDay(route.id, world: w, content: c), 6)
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

        // 運ぶ人がいなければ運ばない(運んでいる人 = activity が carrying の一員。RFCrew が歩かせる。
        // 配属の無い仲間は昼に共同の手になるので、全員休ませておく)
        restAll(&w)
        _ = rig.simulation.runSteps(Int(2 * 9600 / SimStep.gameSeconds), &w)
        XCTAssertEqual(w.logistics.routes[route.id]!.movedToday, 0)
        XCTAssertEqual(w.logistics.routes[route.id]!.blocked, HaulRules.noHaulers)
        // 2 人が運ぶと、鉱石が炉へ届いて炉が動く
        for p in ["person.test_a", "person.test_b"] as [PersonID] { w.people[p]?.assignment = .haul(route: route.id) }
        _ = rig.simulation.runSteps(Int(8 * 3600 / SimStep.gameSeconds), &w)
        XCTAssertGreaterThan(w.logistics.routes[route.id]!.movedToday, 0)
        XCTAssertNil(w.logistics.routes[route.id]!.blocked)
        XCTAssertGreaterThan(w.placements.items[furnace]!.module!.lifetimeProduced, 0, "運ばれた鉱石で炉が動く")
        // 専任の配属は表示用に写す(test_b は配属を外して共同の手に戻す)
        w.people["person.test_b"]?.assignment = .idle
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
        for p in ["person.test_a", "person.test_b"] as [PersonID] { w.people[p]?.assignment = .haul(route: route.id) }
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
        w.people["person.test_a"]?.assignment = .haul(route: supply.id)
        w.people["person.test_b"]?.assignment = .haul(route: deliver.id)
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

    /// P-12: 建造物の中に溜めた物(窯の木炭)を、経路の始まりにして炉へ運ぶ。終わりにはできない。
    func testStructureStockIsARouteSource() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        XCTAssertNil(rig.simulation.apply(.production(.place(module: .anvil, at: wp(4, 16), facing: .east)), to: &w).rejection)
        let anvil = w.placements.at(wp(4, 16))[0]
        let kiln = w.newEntityID()
        w.placements.items[kiln] = Placement(id: kiln, kind: .structure("structure.shelter"), at: wp(10, 16), facing: .north,
                                             origin: ProvenanceLedger.unknownOrigin, status: .running)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.addStock(.item(.charcoal), 6, to: .placement(kiln))
        w = ctx.world
        let before = w.inventory.quantity(.charcoal)
        // 建造物を終わりにはできない。始まりにはできる(手で結ぶ)
        XCTAssertEqual(rig.simulation.apply(.logistics(.link(from: .placement(anvil), to: .placement(kiln))), to: &w)
            .rejection?.reason, HaulRules.unknownEnd)
        XCTAssertNil(rig.simulation.apply(.logistics(.link(from: .placement(kiln), to: .base)), to: &w).rejection)
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(kiln) })
        XCTAssertEqual(route.origin, .manual)
        restAll(&w)
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        _ = rig.simulation.runSteps(Int(8 * 3600 / SimStep.gameSeconds), &w)
        XCTAssertGreaterThan(w.logistics.routes[route.id]!.movedToday, 0)
        XCTAssertEqual(w.inventory.quantity(.charcoal, in: .placement(kiln)) + w.inventory.quantity(.charcoal) - before, 6,
                       "窯の中から拠点へ移っただけ")
        XCTAssertGreaterThan(w.inventory.quantity(.charcoal), before)
        // 建造物が無くなれば経路も消える
        w.placements.items[kiln] = nil
        w.logistics.builtForTopology = -1
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertNil(w.logistics.routes[route.id])
    }

    // MARK: 炉の燃料(経路は火床の燃料も運ぶ)

    /// 炉に熱の定義(R1 の既定)を付けた内容と、炉・出口に石炭を溜めた置き場(叩き台)のある世界。
    func fuelLine(_ coal: Int) throws -> (rig: TestRig, w: WorldState, furnace: EntityID, source: EntityID) {
        var c = try TestContent.publicOnly()
        c.modules[.furnace]?.hearth = HearthDef(capSeconds: 0, fuels: [:], thresholds: [0, 0, 0, 0],
                                                light: [0, 0, 0, 0, 0], burnPermille: [0, 0, 0, 0, 0],
                                                furnace: FurnaceHeatDef())
        let rig = TestRig(content: c)
        var w = world(rig)
        _ = rig.simulation.apply(.invention(.makeDesign(steps: [.charcoalFurnace])), to: &w)
        let d = try XCTUnwrap(w.invention.designs.keys.first)
        XCTAssertNil(rig.simulation.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: wp(16, 16), facing: .east)), to: &w).rejection)
        XCTAssertNil(rig.simulation.apply(.production(.place(module: .anvil, at: wp(4, 16), facing: .east)), to: &w).rejection)
        let furnace = w.placements.at(wp(16, 16))[0], source = w.placements.at(wp(4, 16))[0]
        var ctx = StepContext(world: w, content: rig.content)
        // 蓄えの木炭は無し(炉は運ばれた石炭だけで熱を保つ)
        _ = ctx.takeStock(ctx.world.inventory.quantity(.charcoal, in: .base), from: .base, where: { $0.stuff == .item(.charcoal) })
        ModuleRuntime.put(StockEntry(stuff: .item("coal"), quantity: coal), into: &ctx.world.placements.items[source]!.module!.output)
        // 熱い炉(予熱は済んでいて、入口に最初の石炭が少しある)
        ModuleRuntime.put(StockEntry(stuff: .item("coal"), quantity: 2), into: &ctx.world.placements.items[furnace]!.module!.input)
        var h = ctx.world.placements.items[furnace]!.module!.hearth ?? HearthState()
        h.heat = 1100 * 1000
        h.lit = true
        ctx.world.placements.items[furnace]!.module!.hearth = h
        return (rig, ctx.world, furnace, source)
    }

    /// 採掘口 → 炉の経路は、炉の火床の燃料(石炭)を運び、炉は 1 日熱いまま。数は消えも増えもしない。
    func testRouteCarriesFurnaceFuelAndKeepsFurnaceHot() throws {
        var (rig, w, furnace, source) = try fuelLine(30)
        XCTAssertNil(rig.simulation.apply(.logistics(.link(from: .placement(source), to: .placement(furnace))), to: &w).rejection)
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(source) && $0.to == .placement(furnace) })
        restAll(&w)
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        var movedTotal = 0
        for _ in 0..<26 {   // 1 時間ごとに見る(movedToday は日が変わると戻る)
            let before = w.logistics.routes[route.id]!.movedToday
            _ = rig.simulation.runSteps(Int(3600 / SimStep.gameSeconds), &w)
            let after = w.logistics.routes[route.id]!.movedToday
            movedTotal += after >= before ? after - before : after
        }
        XCTAssertGreaterThan(movedTotal, 0, "石炭が運ばれる")
        let inFurnace = w.placements.items[furnace]!.module!.inputCount("coal")
        let left = w.placements.items[source]!.module!.output.filter { $0.stuff == .item("coal") }.reduce(0) { $0 + $1.quantity }
        // 数は全部の持ち主(置き場の出口・炉の入口・蓄え)で数える。最初の合計との差が火床で燃えた数
        let base = w.inventory.quantity("coal", in: .base)
        let burned = 32 - left - inFurnace - base
        XCTAssertEqual(base, 0)
        XCTAssertTrue((7...8).contains(burned), "26 時間 × 0.3/時 ≒ 7.8 個が火床で燃えた(\(burned))")
        XCTAssertEqual(inFurnace, 2 + movedTotal - burned, "炉に入った数 = 最初 + 運ばれた数 - 燃えた数")
        XCTAssertLessThanOrEqual(inFurnace, w.placements.items[furnace]!.module!.capacity, "山の上限を超えない")
        XCTAssertGreaterThanOrEqual(FurnaceHeat.temperature(w.placements.items[furnace]!, rig.content) ?? 0, 1100, "熱いまま")
        XCTAssertEqual(w.placements.items[furnace]!.module!.hearth?.fuelItem, "coal")
    }

    /// 受け側の炉の燃料は内容から引く: 薪は燃やす物に無ければ受けない(maxTempByFuel は温度の上限で燃料に数えない)。
    func testAcceptedFuelsAreBurnAndPreheatOnly() throws {
        let f = FurnaceHeatDef(burnPerHour: ["coal": 300], maxTempByFuel: ["wood": 900])
        XCTAssertEqual(FurnaceHeat.fuels(f), ["coal", "charcoal"])
        var m = try JSONDecoder().decode(ModuleRuntime.self, from: Data("{}".utf8))
        m.capacity = 12
        let accepted = FurnaceHeat.fuels(f)
        let wood = m.room(for: .item("wood"), fuels: accepted), coal = m.room(for: .item("coal"), fuels: accepted)
        XCTAssertEqual(wood, 0)
        XCTAssertEqual(coal, 12)
    }

    /// 燃料の山の上限は種類をまとめて数える。段の物(auxPerUnit)にある物は今までの room のまま。
    func testFuelCapacityIsTotalAndAuxUnchanged() throws {
        let fuels: Set<ItemID> = ["coal", "charcoal"]
        var m = try JSONDecoder().decode(ModuleRuntime.self, from: Data("{}".utf8))
        m.capacity = 12
        ModuleRuntime.put(StockEntry(stuff: .item("coal"), quantity: 8), into: &m.input)
        let r1 = m.room(for: .item("charcoal"), fuels: fuels)
        XCTAssertEqual(r1, 4)
        ModuleRuntime.put(StockEntry(stuff: .item("charcoal"), quantity: 4), into: &m.input)
        let r2 = m.room(for: .item("coal"), fuels: fuels), r3 = m.room(for: .item("charcoal"), fuels: fuels)
        XCTAssertEqual(r2, 0)
        XCTAssertEqual(r3, 0)
        // 木炭が段の物にもある炉: 木炭は今までの規則(1 回の処理ぶん × 2 - 持っている数)、石炭だけが燃料の規則
        var a = try JSONDecoder().decode(ModuleRuntime.self, from: Data("{}".utf8))
        a.capacity = 12
        a.batch = 2
        a.auxPerUnit = ["charcoal": 3]
        ModuleRuntime.put(StockEntry(stuff: .item("charcoal"), quantity: 5), into: &a.input)
        let withFuels = a.room(for: .item("charcoal"), fuels: fuels), without = a.room(for: .item("charcoal"))
        let coalRoom = a.room(for: .item("coal"), fuels: fuels)
        XCTAssertEqual(withFuels, without)
        XCTAssertEqual(withFuels, 3 * 2 * 2 - 5)
        XCTAssertEqual(coalRoom, 12 - 5, "燃料の合計に段の物の木炭も入る")
    }

    /// 古い保存(新しい欄が無い)の炉も、運ばれた石炭を受け取る。
    func testLegacyFurnaceJSONReceivesHauledCoal() throws {
        var (rig, w, furnace, source) = try fuelLine(10)
        let data = try JSONEncoder().encode(w.placements.items[furnace]!.module!)
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "hearthFuels")
        XCTAssertNil(obj["hearthFuels"])
        let legacy = try JSONDecoder().decode(ModuleRuntime.self, from: JSONSerialization.data(withJSONObject: obj))
        w.placements.items[furnace]!.module = legacy
        XCTAssertNil(rig.simulation.apply(.logistics(.link(from: .placement(source), to: .placement(furnace))), to: &w).rejection)
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .placement(source) })
        restAll(&w)
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        let moved = haulHours(rig, &w, route.id, hours: 26)
        XCTAssertGreaterThan(moved, 0, "古い保存の炉にも石炭が運ばれる")
    }

    /// 蓄え → 炉の経路も燃料を運ぶ。山の上限を超えず、数は全部の持ち主で合う。
    func testBaseToFurnaceRouteCarriesFuel() throws {
        var (rig, w, furnace, _) = try fuelLine(0)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.addStock(.item("coal"), 20, to: .base)
        w = ctx.world
        let total0 = w.inventory.quantity("coal", in: .base) + w.placements.items[furnace]!.module!.inputCount("coal")
        XCTAssertNil(rig.simulation.apply(.logistics(.link(from: .base, to: .placement(furnace))), to: &w).rejection)
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.from == .base })
        restAll(&w)
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        _ = rig.simulation.runSteps(2, &w)
        XCTAssertTrue(w.logistics.routes[route.id]!.waiting, "蓄えの石炭が炉の燃料の不足として待たれる")
        let moved = haulHours(rig, &w, route.id, hours: 26)
        XCTAssertGreaterThan(moved, 0)
        let m = w.placements.items[furnace]!.module!
        XCTAssertLessThanOrEqual(m.inputCount("coal") + m.inputCount("charcoal"), m.capacity)
        // 全部の持ち主(蓄え・炉の入口)に残った数 + 運ばれてから燃えた数 = 最初の数
        let left = w.inventory.quantity("coal", in: .base) + m.inputCount("coal")
        let burned = total0 - left
        XCTAssertTrue((6...9).contains(burned), "26 時間 × 0.3/時 ≒ 7.8 個が火床で燃えた(\(burned))")
        XCTAssertLessThan(w.inventory.quantity("coal", in: .base), 20, "蓄えから炉へ運ばれた")
    }

    /// 燃料でない物・炉でないモジュールへは、これまでどおり運ばない。
    func testRouteToNonFuelModuleUnchanged() throws {
        var (rig, w, furnace, source) = try fuelLine(10)
        XCTAssertNil(rig.simulation.apply(.production(.place(module: .anvil, at: wp(10, 16), facing: .east)), to: &w).rejection)
        let anvil = w.placements.at(wp(10, 16))[0]
        XCTAssertEqual(w.placements.items[anvil]!.module!.room(for: .item("coal")), 0)
        let fuels = FurnaceHeat.fuels(of: furnace, w, rig.content)
        XCTAssertGreaterThan(w.placements.items[furnace]!.module!.room(for: .item("coal"), fuels: fuels), 0)
        XCTAssertEqual(w.placements.items[furnace]!.module!.room(for: .item("stone"), fuels: fuels), 0)
        XCTAssertNil(rig.simulation.apply(.logistics(.link(from: .placement(source), to: .placement(anvil))), to: &w).rejection)
        _ = rig.simulation.runSteps(1, &w)
        let route = try XCTUnwrap(w.logistics.routes.values.first { $0.to == .placement(anvil) })
        restAll(&w)
        w.people["person.test_a"]?.assignment = .haul(route: route.id)
        _ = rig.simulation.runSteps(Int(8 * 3600 / SimStep.gameSeconds), &w)
        XCTAssertEqual(w.logistics.routes[route.id]!.movedToday, 0)
        XCTAssertEqual(w.placements.items[anvil]!.module!.inputCount("coal"), 0)
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

    /// 1 時間ごとに進めて、経路が運んだ数を足す(movedToday は日が変わると戻る)。
    func haulHours(_ rig: TestRig, _ w: inout WorldState, _ route: EntityID, hours: Int) -> Int {
        var total = 0
        for _ in 0..<hours {
            let before = w.logistics.routes[route]!.movedToday
            _ = rig.simulation.runSteps(Int(3600 / SimStep.gameSeconds), &w)
            let after = w.logistics.routes[route]!.movedToday
            total += after >= before ? after - before : after
        }
        return total
    }

    /// ノア以外の一員を休ませる(.rest は眠るので運ばない。配属の無い仲間は RFCrew が昼に共同の手として経路へ回す)。
    func restAll(_ w: inout WorldState) {
        for p in w.people.members where p != .noah { w.people[p]?.assignment = .rest }
    }

    func wp(_ x: Int, _ y: Int) -> WorldPoint { WorldPoint(.surface, GridPoint(x, y)) }
}
