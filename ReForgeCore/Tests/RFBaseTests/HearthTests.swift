import RFBase
import RFContent
import RFCrew
import RFKernel
import RFMap
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 火床(序盤の設計 W-02a・W-02b・W-02c)。TEST-O3(火床)・TEST-O17(火の効き目)。
final class HearthTests: XCTestCase {
    static let def = HearthDef(capSeconds: 43_200, fuels: ["stick": 10_800, "wood": 21_600],
                               thresholds: [0, 10_800, 21_600, 32_400], light: [0, 2, 3, 4, 5],
                               burnPermille: [0, 500, 750, 1000, 1500], pileItem: "stick",
                               nightsCounter: "counter.nights_lit")

    /// 何秒燃えて消えるか(15 秒ずつ)。
    func secondsUntilOut(_ s0: HearthState, structures: Int, tended: Bool = false, limit: Int = 200_000) -> Int {
        var s = s0
        var t = 0
        while s.lit && t < limit {
            s = HearthRule.burn(s, Self.def, seconds: 15, structuresInLight: structures, nightWork: false, tended: tended)
            t += 15
        }
        return t
    }

    // MARK: TEST-O3 規則

    /// 枝 1 本で 3 時間。上限 12 時間。
    func testFuelValuesAndCap() {
        var s = HearthState()
        s = HearthRule.add(s, Self.def, item: "stick", quantity: 1)!
        XCTAssertEqual(s.fuel, 10_800_000)
        s = HearthRule.add(s, Self.def, item: "stick", quantity: 10)!
        XCTAssertEqual(s.fuel, 43_200_000)
        XCTAssertNil(HearthRule.add(s, Self.def, item: "stone", quantity: 1))
    }

    /// 番がいなければ、満タンでも建造物 0 で 15.0 時間、4 で 10.7 時間で消える。
    func testUntendedFullFireGoesOut() {
        let full = HearthState(fuel: 43_200_000, lit: true)
        XCTAssertEqual(secondsUntilOut(full, structures: 0), 54_000)
        let four = secondsUntilOut(full, structures: 4)
        XCTAssertEqual(Double(four) / 3600, 10.71, accuracy: 0.02)
    }

    /// 番がいて薪の山に枝があれば、18 時間の夜を越える。
    func testTendedFireLastsTheNight() {
        var s = HearthState(fuel: 43_200_000, lit: true, pile: 6)
        s = HearthRule.burn(s, Self.def, seconds: 18 * 3600, structuresInLight: 4, nightWork: false, tended: true)
        XCTAssertTrue(s.lit)
        XCTAssertLessThan(s.pile, 6)
        // 番がいなければ同じ山があっても消える
        var u = HearthState(fuel: 43_200_000, lit: true, pile: 6)
        u = HearthRule.burn(u, Self.def, seconds: 18 * 3600, structuresInLight: 4, nightWork: false, tended: false)
        XCTAssertFalse(u.lit)
        XCTAssertEqual(u.pile, 6)
    }

    /// 刻み方によらず同じ(昼のリアルタイムでも、寝るの一括でも、夜明けの燃料が同じ)。
    func testBurnIsStepInvariant() {
        let s0 = HearthState(fuel: 40_000_000, lit: true, pile: 3)
        for (n, nw, tended) in [(0, false, false), (3, true, false), (2, false, true)] {
            let once = HearthRule.burn(s0, Self.def, seconds: 30_000, structuresInLight: n, nightWork: nw, tended: tended)
            var step = s0
            for _ in 0..<(30_000 / 15) {
                step = HearthRule.burn(step, Self.def, seconds: 15, structuresInLight: n, nightWork: nw, tended: tended)
            }
            XCTAssertEqual(once, step)
            var odd = s0
            var left = 30_000
            for k in [7, 1, 333, 4000, 11] + Array(repeating: 977, count: 40) where left > 0 {
                let d = min(k, left)
                odd = HearthRule.burn(odd, Self.def, seconds: d, structuresInLight: n, nightWork: nw, tended: tended)
                left -= d
            }
            if left > 0 { odd = HearthRule.burn(odd, Self.def, seconds: left, structuresInLight: n, nightWork: nw, tended: tended) }
            XCTAssertEqual(once, odd)
        }
    }

    /// 段と灯りの半径(くすぶり 2・ちらつき 3・燃えている 4・盛ん 5)。埋めると灯り 1・減りが 3 分の 1。
    func testLevelsLightAndBanking() {
        func st(_ h: Int) -> HearthState { HearthState(fuel: h * 3_600_000, lit: true) }
        XCTAssertEqual(HearthRule.level(st(12), Self.def), .roaring)
        XCTAssertEqual(HearthRule.lightRadius(st(12), Self.def), 5)
        XCTAssertEqual(HearthRule.lightRadius(st(7), Self.def), 4)
        XCTAssertEqual(HearthRule.lightRadius(st(4), Self.def), 3)
        XCTAssertEqual(HearthRule.lightRadius(st(1), Self.def), 2)
        XCTAssertEqual(HearthRule.level(HearthState(fuel: 5, lit: false), Self.def), .out)
        var b = st(3)
        b.banked = true
        XCTAssertEqual(HearthRule.lightRadius(b, Self.def), 1)
        let after = HearthRule.burn(b, Self.def, seconds: 9 * 3600, structuresInLight: 0, nightWork: false, tended: false)
        XCTAssertTrue(after.lit, "埋み火は 3 時間の燃料で 9 時間近く持つ")
    }

    // MARK: 世界の中で

    fileprivate struct Rig {
        var content: ContentDB
        var sim: Simulation
        var world: WorldState

        init() throws {
            var c = try TestContent.publicOnly()
            c.structures["structure.campfire"]?.buildSeconds = 0
            c.structures["structure.storage"]?.buildSeconds = 0
            content = c
            sim = Simulation(content: c)
            world = WorldFactory(content: c, mapGenerator: FlatMapGenerator()).newWorld(seed: 1)
            for s in ["structure.campfire", "structure.storage"] {
                world.research.unlocked.structures.insert(StructureKindID(s))
            }
            give("stick", 30)
            give("plant_fiber", 10)
            give("wood", 30)
        }

        var center: GridPoint { world.map.spawn.point }

        mutating func give(_ item: ItemID, _ n: Int) {
            var ctx = StepContext(world: world, content: content)
            let r = ctx.record(.gathered, .item(item), actor: .noah)
            ctx.addStock(.item(item), n, to: .base, origin: r)
            world = ctx.world
        }

        mutating func campfire(_ g: GridPoint) -> EntityID {
            let r = sim.apply(.base(.build(structure: "structure.campfire", at: WorldPoint(.surface, g), facing: .north)),
                              to: &world)
            XCTAssertNil(r.rejection)
            return world.placements.items.sorted { $0.key < $1.key }.last!.key
        }

        func level(_ id: EntityID) -> HearthLevel { Hearths.level(of: world.placements.items[id]!, content) ?? .out }

        /// 燃料を直に置く(試験の準備)。
        mutating func setFuel(_ id: EntityID, hours: Int, lit: Bool = true) {
            var ctx = StepContext(world: world, content: content)
            var s = Hearths.state(world.placements.items[id]!, content)!
            s.fuel = hours * 3_600_000
            s.lit = lit
            Hearths.write(id, s, &ctx)
            world = ctx.world
        }
    }

    /// 灯りの半径は段から読む。燃料が尽きれば消え、灯りも見張りも範囲の効果も効かない。点け直すと効く(TEST-O17)。
    func testFireEffectsOnlyWhileLit() throws {
        var rig = try Rig()
        let id = rig.campfire(rig.center + GridPoint(2, 0))
        _ = rig.sim.runSteps(1, &rig.world)
        let p = { rig.world.placements.items[id]! }
        XCTAssertEqual(rig.level(id), .roaring)
        XCTAssertEqual(Hearths.lightRadius(p(), rig.content), 5)
        XCTAssertEqual(Hearths.provides(p(), rig.content)["watch"], 3)
        XCTAssertTrue(rig.world.auras.active.values.contains { $0.kind == "aura.test.campfire" })
        let near = WorldPoint(.surface, rig.center + GridPoint(5, 0))
        XCTAssertTrue(Hearths.isLit(near, in: rig.world, content: rig.content))

        rig.setFuel(id, hours: 1)
        XCTAssertEqual(Hearths.lightRadius(p(), rig.content), 2, "くすぶりは灯り 2")
        XCTAssertFalse(Hearths.isLit(near, in: rig.world, content: rig.content))

        let r = rig.sim.runSteps(2 * 3600 / 15 + 2, &rig.world)
        XCTAssertEqual(rig.level(id), .out)
        XCTAssertTrue(r.events.contains { $0 == .hearthLevelChanged(placement: id, level: .out) })
        XCTAssertTrue(Hearths.provides(p(), rig.content).isEmpty, "消えている間は灯り・見張りが効かない")
        XCTAssertFalse(rig.world.auras.active.values.contains { $0.kind == "aura.test.campfire" }, "範囲の効果も消える")
        XCTAssertEqual(BaseRules.total("watch", rig.world, rig.content), 0)

        // くべても点かない。点け直しには火種が要る
        XCTAssertNil(rig.sim.apply(.base(.hearth(placement: id, op: .stoke(item: "stick"))), to: &rig.world).rejection)
        XCTAssertEqual(rig.level(id), .out)
        XCTAssertEqual(rig.sim.apply(.base(.hearth(placement: id, op: .ignite(from: nil))), to: &rig.world).rejection?.reason,
                       "reason.hearth.no_flame")
        let other = rig.campfire(rig.center + GridPoint(-3, 0))
        _ = rig.sim.runSteps(1, &rig.world)
        XCTAssertNil(rig.sim.apply(.base(.hearth(placement: id, op: .ignite(from: other))), to: &rig.world).rejection)
        _ = rig.sim.runSteps(1, &rig.world)
        XCTAssertEqual(rig.level(id), .smoldering, "枝 1 本の 3 時間はくすぶり")
        XCTAssertEqual(Hearths.provides(p(), rig.content)["watch"], 3)
        XCTAssertTrue(rig.world.auras.active.values.contains { $0.kind == "aura.test.campfire" && $0.source == .placement(id) })
    }

    /// 拠点が育つほど速く燃える(灯りの中のほかの建造物)。
    func testMoreStructuresBurnFaster() throws {
        var a = try Rig()
        let fa = a.campfire(a.center)
        var b = try Rig()
        let fb = b.campfire(b.center)
        for d in [GridPoint(2, 0), GridPoint(-2, 0), GridPoint(0, 2)] {
            _ = b.sim.apply(.base(.build(structure: "structure.storage", at: WorldPoint(.surface, b.center + d), facing: .north)),
                            to: &b.world)
        }
        XCTAssertEqual(Hearths.structuresInLight(fb, in: b.world, content: b.content), 3)
        _ = a.sim.runSteps(240, &a.world)
        _ = b.sim.runSteps(240, &b.world)
        let ra = Hearths.state(a.world.placements.items[fa]!, a.content)!.fuel
        let rb = Hearths.state(b.world.placements.items[fb]!, b.content)!.fuel
        XCTAssertLessThan(rb, ra)
    }

    func testNearbyHearthSupportChangesPileRateAndOutlook() throws {
        var rig = try Rig()
        rig.content.structures["structure.storage"]?.provides["hearth.pile"] = 4
        rig.content.structures["structure.storage"]?.provides["hearth.burn_permille"] = 900
        rig.sim = Simulation(content: rig.content)
        let fire = rig.campfire(rig.center)
        let supportPoint = rig.center + GridPoint(1, 0)
        XCTAssertNil(rig.sim.apply(.base(.build(structure: "structure.storage", at: WorldPoint(.surface, supportPoint), facing: .north)),
                                   to: &rig.world).rejection)
        let modifiers = Hearths.modifiers(fire, in: rig.world, content: rig.content)
        XCTAssertEqual(modifiers, HearthModifiers(pileMaxAdd: 4, burnPermille: 900))
        XCTAssertEqual(Hearths.structuresInLight(fire, in: rig.world, content: rig.content), 0)
        XCTAssertNil(rig.sim.apply(.base(.hearth(placement: fire, op: .stack(item: "stick", count: 16))), to: &rig.world).rejection)
        XCTAssertEqual(Hearths.state(rig.world.placements.items[fire]!, rig.content)?.pile, 16)

        let state = HearthState(fuel: 14_400_000, lit: true, pile: 4)
        let ordinary = HearthRule.burn(state, Self.def, seconds: 15, structuresInLight: 0, nightWork: false, tended: false)
        let supported = HearthRule.burn(state, Self.def, seconds: 15, structuresInLight: 0, nightWork: false, tended: false,
                                        modifiers: modifiers)
        XCTAssertEqual(state.fuel - supported.fuel, (state.fuel - ordinary.fuel) * 9 / 10)

        let now = GameTime(seconds: 40_000)
        let untilDawn = Int(rig.content.clock.dayGameSeconds + rig.content.clock.nightGameSeconds - now.seconds)
        let outlook = HearthRule.outlookWithPile(state, Self.def, now: now, clock: rig.content.clock, structuresInLight: 0,
                                                 tended: true, modifiers: modifiers)
        let burned = HearthRule.burn(state, Self.def, seconds: untilDawn, structuresInLight: 0, nightWork: false,
                                     tended: true, modifiers: modifiers)
        XCTAssertEqual(outlook == .throughNight, burned.lit)

        let farPoint = WorldPoint(.surface, rig.center + GridPoint(8, 0))
        if let support = rig.world.placements.items.values.first(where: { $0.id != fire && $0.at.point == supportPoint }) {
            rig.world.placements.items[support.id]?.at = farPoint
        }
        XCTAssertEqual(Hearths.modifiers(fire, in: rig.world, content: rig.content).pileMaxAdd, 0)
    }

    /// 番は配属(火床に付く)で決まり、薪の山からくべる。番がいなければ山があっても減らない。
    func testTenderUsesPile() throws {
        var rig = try Rig()
        let id = rig.campfire(rig.center)
        XCTAssertNil(rig.sim.apply(.base(.hearth(placement: id, op: .stack(item: "stick", count: 5))), to: &rig.world).rejection)
        XCTAssertEqual(Hearths.state(rig.world.placements.items[id]!, rig.content)!.pile, 5)
        rig.setFuel(id, hours: 5)
        _ = rig.sim.runSteps(10, &rig.world)
        XCTAssertEqual(Hearths.state(rig.world.placements.items[id]!, rig.content)!.pile, 5)
        rig.world.people["person.test_a"]?.assignment = .operate(placement: id)
        let at = WorldPoint(.surface, rig.center + GridPoint(1, 0))
        rig.world.people["person.test_a"]?.position = at
        _ = rig.sim.runSteps(1, &rig.world)
        XCTAssertEqual(Hearths.state(rig.world.placements.items[id]!, rig.content)!.pile, 4)
    }

    /// 火が夜明けまで消えなかった夜を数える(埋み火の夜も数える)。消えた夜は数えない。
    func testNightsLitCounter() throws {
        var rig = try Rig()
        let id = rig.campfire(rig.center)
        rig.world.people["person.test_a"]?.assignment = .operate(placement: id)
        let at = WorldPoint(.surface, rig.center + GridPoint(1, 0))
        rig.world.people["person.test_a"]?.position = at
        _ = rig.sim.apply(.base(.hearth(placement: id, op: .stack(item: "stick", count: 12))), to: &rig.world)
        let dayLen = Int(rig.content.clock.dayGameSeconds + rig.content.clock.nightGameSeconds)
        _ = rig.sim.runSteps(dayLen / 15 + 2, &rig.world)
        XCTAssertEqual(rig.world.narrative.counters["counter.nights_lit"], 1)
        // 2 晩目: 番を外し、薪も尽きれば消える
        rig.world.people["person.test_a"]?.assignment = .idle
        rig.setFuel(id, hours: 1)
        _ = rig.sim.runSteps(dayLen / 15, &rig.world)
        XCTAssertEqual(rig.world.narrative.counters["counter.nights_lit"], 1)
        // 3 晩目: 埋み火で越える
        rig.setFuel(id, hours: 9)
        _ = rig.sim.apply(.base(.hearth(placement: id, op: .bank)), to: &rig.world)
        _ = rig.sim.runSteps(dayLen / 15, &rig.world)
        XCTAssertEqual(rig.world.narrative.counters["counter.nights_lit"], 2)
    }

    /// 消えていれば夜に灯りの +4 が無い(視界は灯りの外で狭い)。
    func testDarkWhenOut() throws {
        var rig = try Rig()
        let id = rig.campfire(rig.center)
        let at = WorldPoint(.surface, rig.center + GridPoint(1, 0))
        rig.world.people[.noah]?.position = at
        rig.world.clock.phase = .nightWork
        let lit = Vision.visibleNow(rig.world, content: rig.content, layer: .surface).count
        rig.setFuel(id, hours: 0, lit: false)
        let dark = Vision.visibleNow(rig.world, content: rig.content, layer: .surface).count
        XCTAssertLessThan(dark, lit)
    }

    /// 効果 hearth(内容の「くべる」「火を起こす」「火を埋める」)。
    func testHearthEffects() throws {
        var rig = try Rig()
        let id = rig.campfire(rig.center)
        rig.setFuel(id, hours: 0, lit: false)
        var ctx = StepContext(world: rig.world, content: rig.content)
        let here = PlaceSelector.point(at: WorldPoint(.surface, rig.center + GridPoint(1, 1)))
        EffectApplier.apply([.hearth(at: here, op: .addFuel(item: "wood", quantity: 1)), .hearth(at: here, op: .ignite())],
                            &ctx, cause: nil)
        XCTAssertTrue(ctx.warnings.isEmpty)
        rig.world = ctx.world
        XCTAssertEqual(rig.level(id), .flickering)
    }

    /// 点けると igniteSeconds まで燃料が入る(残り火から移した火は 4 時間。必ず点く)。
    func testIgniteGivesFuel() throws {
        var rig = try Rig()
        rig.content.structures["structure.campfire"]?.hearth?.igniteSeconds = 14_400
        rig.sim = Simulation(content: rig.content)
        let id = rig.campfire(rig.center)
        rig.setFuel(id, hours: 0, lit: false)
        var ctx = StepContext(world: rig.world, content: rig.content)
        EffectApplier.apply([.hearth(at: .point(at: WorldPoint(.surface, rig.center)), op: .ignite())], &ctx, cause: nil)
        rig.world = ctx.world
        XCTAssertEqual(rig.level(id), .flickering)
        XCTAssertEqual(Hearths.state(rig.world.placements.items[id]!, rig.content)!.fuel, 14_400_000)
    }

    /// 拠点の範囲の建設は、fire を出す火が燃えている間だけ進む。拠点の外(柵)は火を見ない(TEST-O17)。
    func testConstructionNeedsFire() throws {
        var rig = try Rig()
        rig.content.base.constructionFireTag = "fire"
        rig.content.structures["structure.campfire"]?.provides["fire"] = 1
        rig.content.structures["structure.storage"]?.buildSeconds = 3600
        rig.sim = Simulation(content: rig.content)
        let fire = rig.campfire(rig.center + GridPoint(-3, 0))
        rig.setFuel(fire, hours: 0, lit: false)
        let site = rig.center + GridPoint(3, 0)
        _ = rig.sim.apply(.base(.build(structure: "structure.storage", at: WorldPoint(.surface, site), facing: .north)),
                          to: &rig.world)
        let sid = rig.world.placements.items.sorted { $0.key < $1.key }.last!.key
        for p in rig.world.people.members { rig.world.people[p]?.position = WorldPoint(.surface, GridPoint(1, 1)) }
        let at = WorldPoint(.surface, site + GridPoint(0, 1))
        rig.world.people[.noah]?.position = at
        _ = rig.sim.runSteps(20, &rig.world)
        XCTAssertEqual(rig.world.placements.items[sid]?.status, .underConstruction(progress: 0))
        rig.setFuel(fire, hours: 5)
        _ = rig.sim.runSteps(20, &rig.world)
        XCTAssertNotEqual(rig.world.placements.items[sid]?.status, .underConstruction(progress: 0))
    }

    /// 熱い炉(火床を持つモジュール)も灯りになる。冷えれば灯りは消える。
    func testHotFurnaceGivesLight() throws {
        var rig = try Rig()
        let kind: ModuleKindID = "anvil"
        rig.content.modules[kind]?.hearth = HearthDef(capSeconds: 36_000, fuels: ["charcoal": 36_000],
                                                      thresholds: [0, 1, 2, 3], light: [0, 3, 3, 3, 3],
                                                      burnPermille: [0, 1000, 1000, 1000, 1000])
        let id = rig.world.newEntityID()
        var p = Placement(id: id, kind: .module(kind), at: WorldPoint(.surface, rig.center + GridPoint(6, 6)),
                          facing: .north, origin: ProvenanceLedger.unknownOrigin, status: .running)
        var m = ModuleRuntime(design: nil, step: nil)
        m.hearth = HearthState(fuel: 10_000_000, lit: true)
        p.module = m
        rig.world.placements.items[id] = p
        let near = WorldPoint(.surface, rig.center + GridPoint(8, 6))
        XCTAssertEqual(Hearths.lightRadius(rig.world.placements.items[id]!, rig.content), 3)
        XCTAssertTrue(Hearths.isLit(near, in: rig.world, content: rig.content))
        rig.world.placements.items[id]?.module?.hearth = HearthState()
        XCTAssertEqual(Hearths.lightRadius(rig.world.placements.items[id]!, rig.content), 0)
        XCTAssertFalse(Hearths.isLit(near, in: rig.world, content: rig.content))
    }

    /// 古い形の内容(焚き火に hearth が無い)では、今までどおり provides の灯り・見張り・範囲の効果が常に効く。
    /// 獣の寄り方(lure)と建設の火(constructionFireTag)も、無ければ前と同じ。
    func testOldContentWithoutHearthBehavesAsBefore() throws {
        var rig = try Rig()
        rig.content.structures["structure.campfire"]?.hearth = nil
        rig.sim = Simulation(content: rig.content)
        XCTAssertNil(rig.content.base.constructionFireTag)
        let id = rig.campfire(rig.center)
        _ = rig.sim.runSteps(26 * 3600 / 15 * 2, &rig.world)
        let p = rig.world.placements.items[id]!
        XCTAssertNil(p.structure?.hearth)
        XCTAssertNil(Hearths.level(of: p, rig.content))
        XCTAssertEqual(Hearths.lightRadius(p, rig.content), 4)
        XCTAssertEqual(Hearths.provides(p, rig.content), rig.content.structures["structure.campfire"]!.provides)
        XCTAssertTrue(rig.world.auras.active.values.contains { $0.kind == "aura.test.campfire" })
        XCTAssertTrue(Hearths.isLit(WorldPoint(.surface, rig.center + GridPoint(4, 0)), in: rig.world, content: rig.content))
        XCTAssertFalse(Hearths.isLit(WorldPoint(.surface, rig.center + GridPoint(5, 0)), in: rig.world, content: rig.content))
        let at = WorldPoint(.surface, rig.center + GridPoint(1, 0))
        rig.world.people[.noah]?.position = at
        rig.world.clock.phase = .nightWork
        let withLight = Vision.visibleNow(rig.world, content: rig.content, layer: .surface).count
        rig.world.placements.items[id]?.status = .broken
        XCTAssertLessThan(Vision.visibleNow(rig.world, content: rig.content, layer: .surface).count, withLight)
    }

    /// 火起こしは成功率つき(決定的な乱数)。スキルがあれば率が上がる。失敗しても火は点かないだけ。
    func testIgniteWithChance() throws {
        var rig = try Rig()
        let id = rig.campfire(rig.center)
        func tries(_ chance: Int, skilled: Bool) -> Int {
            var w = rig.world
            if skilled { w.people[.noah]?.skills.insert("skill.test.fire") }
            var lit = 0
            for _ in 0..<200 {
                var ctx = StepContext(world: w, content: rig.content)
                var s = Hearths.state(ctx.world.placements.items[id]!, rig.content)!
                s.fuel = 3_600_000
                s.lit = false
                Hearths.write(id, s, &ctx)
                let cause = ctx.record(.chose, .none, actor: .noah)
                EffectApplier.apply([.hearth(at: .point(at: WorldPoint(.surface, rig.center)),
                                             op: .ignite(chancePermille: chance, skill: "skill.test.fire",
                                                         skillChancePermille: 900))], &ctx, cause: cause)
                if Hearths.state(ctx.world.placements.items[id]!, rig.content)!.lit { lit += 1 }
                w = ctx.world
            }
            return lit
        }
        let plain = tries(500, skilled: false)
        XCTAssertTrue((70...130).contains(plain), "5 割: \(plain)")
        let skilled = tries(500, skilled: true)
        XCTAssertGreaterThan(skilled, 160)
        XCTAssertEqual(tries(500, skilled: false), plain, "同じ世界からなら同じ結果(決定的)")
        XCTAssertEqual(tries(0, skilled: false), 0)
    }

    /// 最初の「火を起こす」: 効果 placeStructure で焚き火台をそばの空いたマスに置き、同じ並びの ignite がそれに効く。
    func testPlaceStructureThenIgnite() throws {
        var rig = try Rig()
        rig.content.structures["structure.campfire"]?.hearth?.initialSeconds = 0
        rig.content.structures["structure.campfire"]?.hearth?.igniteSeconds = 14_400
        let here = WorldPoint(.surface, rig.center)
        _ = rig.sim.apply(.base(.build(structure: "structure.storage", at: here, facing: .north)), to: &rig.world)
        var ctx = StepContext(world: rig.world, content: rig.content)
        let cause = ctx.record(.chose, .none, actor: .noah, place: here)
        EffectApplier.apply([.placeStructure(structure: "structure.campfire", at: .trigger, built: true),
                             .hearth(at: .trigger, op: .ignite())], &ctx, cause: cause)
        XCTAssertTrue(ctx.warnings.isEmpty, "\(ctx.warnings)")
        let fire = ctx.world.placements.items.values.first { $0.kind == .structure("structure.campfire") }!
        XCTAssertEqual(fire.at.point, rig.center + GridPoint(-1, -1), "空いたマスを決定的に選ぶ")
        XCTAssertEqual(fire.status, .running)
        XCTAssertEqual(Hearths.level(of: fire, rig.content), .flickering, "置いたその場で灯る")
        XCTAssertTrue(ctx.drainEvents().contains { if case .built = $0 { true } else { false } })
    }
}
