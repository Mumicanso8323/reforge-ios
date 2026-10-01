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

/// RFProduction の受け入れテスト(F-work-units.md の U7: 置ける場所の規則 / 隣接と向きでつながる /
/// 1 回の処理が RuleBook の 1 工程 / 片付けると材料が全部戻る / 止まった理由)と、手作業・T1・有限の品。
final class ProductionSystemTests: XCTestCase {
    typealias F = ProductionFixture

    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(ProductionSystem().handle(foreign, &ctx), .notMine)
    }

    // MARK: 置ける場所の規則

    func testPlacementRules() throws {
        let fx = try F()
        var w = fx.world()
        // 採掘口は鉱脈の上でないと置けない
        var r = fx.apply(.production(.place(module: .minehead, at: F.wp(5, 5), facing: .east)), &w)
        XCTAssertEqual(r.rejection?.reason, ProductionText.needsDeposit)
        F.addDeposit(&w, at: GridPoint(5, 5))
        r = fx.apply(.production(.place(module: .minehead, at: F.wp(5, 5), facing: .east)), &w)
        XCTAssertNil(r.rejection)
        // 同じマスには置けない
        r = fx.apply(.production(.place(module: .furnace, at: F.wp(5, 5), facing: .east)), &w)
        XCTAssertEqual(r.rejection?.reason, ProductionText.occupied)
        // 洗い樋は水に接していないと置けない
        r = fx.apply(.production(.place(module: .sluice, at: F.wp(8, 8), facing: .east)), &w)
        XCTAssertEqual(r.rejection?.reason, ProductionText.needsWater)
        F.setWater(&w, at: GridPoint(8, 9))
        r = fx.apply(.production(.place(module: .sluice, at: F.wp(8, 8), facing: .east)), &w)
        XCTAssertNil(r.rejection)
        // 水の上には置けない
        r = fx.apply(.production(.place(module: .anvil, at: F.wp(8, 9), facing: .east)), &w)
        XCTAssertEqual(r.rejection?.reason, ProductionText.terrain)
        // 解禁されていない物は置けない
        w.research.unlocked.modules.remove(.anvil)
        r = fx.apply(.production(.place(module: .anvil, at: F.wp(9, 9), facing: .east)), &w)
        XCTAssertEqual(r.rejection?.reason, ProductionText.locked)
        // 材料が足りなければ置けない(画面の影と同じ判定)
        var poor = fx.world(wood: 0)
        F.addDeposit(&poor, at: GridPoint(5, 5))
        XCTAssertEqual(PlacementCheck.check(.minehead, at: F.wp(5, 5), facing: .east, world: poor, content: fx.content)?.reason,
                       ProductionText.noMaterials)
    }

    func testPlacingPaysCostAndRecordsProvenance() throws {
        let fx = try F()
        var w = fx.world(wood: 10)
        let r = fx.apply(.production(.place(module: .furnace, at: F.base_wp, facing: .east)), &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.inventory.quantity(.wood), 8, "炉の費用は薪 2")
        let id = try XCTUnwrap(w.placements.at(F.base_wp).first)
        let p = try XCTUnwrap(w.placements.items[id])
        XCTAssertEqual(p.status, .running, "置いた瞬間から動く(材料が無ければすぐ止まる)")
        XCTAssertEqual(w.ledger.record(p.origin)?.act, .placed)
        XCTAssertTrue(r.events.contains(.placed(placement: id, record: p.origin)))
        // 置いた炉の範囲の効果(排気)が付く
        XCTAssertTrue(w.auras.active.values.contains { $0.source == .placement(id) && $0.kind == "aura.test.smoke" })
    }

    // MARK: 隣接と向きでつながる / 1 回の処理 = RuleBook の 1 工程

    func testAdjacentFacingConnectsAndCycleIsOneRuleBookStep() throws {
        let fx = try F()
        var w = fx.world()
        let dep = F.addDeposit(&w, at: GridPoint(14, 16), percent: 30)
        // 東向きに 採掘口 → 炉(木炭) → 叩き台 を並べる(拠点の中。木炭は蓄えから、板は蓄えへ)
        let d = fx.design([.minehead, .charcoalFurnace, .anvil], &w)
        XCTAssertNil(fx.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: F.wp(14, 16), facing: .east)), &w).rejection)
        XCTAssertNil(fx.apply(.production(.placeFromDesign(design: d, stepIndex: 1, at: F.wp(15, 16), facing: .east)), &w).rejection)
        XCTAssertNil(fx.apply(.production(.placeFromDesign(design: d, stepIndex: 2, at: F.wp(16, 16), facing: .east)), &w).rejection)
        let mine = w.placements.at(F.wp(14, 16))[0], furnace = w.placements.at(F.wp(15, 16))[0], anvil = w.placements.at(F.wp(16, 16))[0]
        XCTAssertEqual(ModuleTopology.directDownstream(of: mine, in: w), furnace)
        XCTAssertEqual(ModuleTopology.directDownstream(of: furnace, in: w), anvil)
        XCTAssertNil(ModuleTopology.directDownstream(of: anvil, in: w))
        XCTAssertEqual(w.map[.surface]?.deposits[dep]?.remainingExtractions, 60)

        // 1 回(9600 秒)で採掘口が 1 回掘り、鉱石が隣の炉へ直に入る(運び手なし)
        _ = fx.run(seconds: F.cycle, &w)
        XCTAssertEqual(w.map[.surface]?.deposits[dep]?.remainingExtractions, 59)
        XCTAssertEqual(w.placements.items[furnace]?.module?.mainInputCount, 2, "1 回 = 2 個(Fe 30% 以下)")
        XCTAssertTrue(w.logistics.routes.isEmpty, "隣接で直結なら運搬の経路は要らない")

        // 3 回ぶん進めると板が蓄えに入る。板は試作(ProcessChain.run)と同じ物
        _ = fx.run(seconds: F.cycle * 3, &w)
        let expected = ProcessChain.run([.minehead, .charcoalFurnace, .anvil], input: Matter.ironOre(purity: Purity(percent: 30)))
        XCTAssertGreaterThan(F.matterCount(w, where: F.isPlate), 0)
        XCTAssertTrue(w.inventory.entries(.base).contains { $0.stuff == .matter(expected.product) },
                      "1 回の処理 = RuleBook の 1 段。蓄えに入ると並びの最後の規則で冷える(試作と同じ結果)")
        // 木炭は 1 個の鉱石ごとに 1 つ(段に入れた物)
        let plates = F.matterCount(w, where: F.isPlate)
        let lumpsOrPlates = plates + (w.placements.items[anvil]?.module?.mainInputCount ?? 0)
            + (w.placements.items[anvil]?.module?.outputCount ?? 0)
        XCTAssertEqual(40 - w.inventory.quantity(.charcoal) - (w.placements.items[furnace]?.module?.inputCount(.charcoal) ?? 0),
                       lumpsOrPlates)

        // 向きが合わなければつながらない(炉を北向きに動かすと入口が南になり、採掘口の出口(東)と向き合わない)
        XCTAssertNil(fx.apply(.production(.move(placement: furnace, to: F.wp(15, 16), facing: .north)), &w).rejection)
        XCTAssertNil(ModuleTopology.directDownstream(of: mine, in: w))
    }

    // MARK: 止まった理由

    func testStoppedReasonWhenFuelDoesNotCome() throws {
        let fx = try F()
        var w = fx.world(charcoal: 0)
        F.addDeposit(&w, at: GridPoint(14, 16))
        let d = fx.design([.minehead, .charcoalFurnace], &w)
        _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: F.wp(14, 16), facing: .east)), &w)
        _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 1, at: F.wp(15, 16), facing: .east)), &w)
        let furnace = w.placements.at(F.wp(15, 16))[0]
        let r = fx.run(seconds: F.cycle + 60, &w)
        XCTAssertEqual(w.placements.items[furnace]?.status, .stopped(reason: ProductionText.noAux))
        XCTAssertEqual(w.placements.items[furnace]?.module?.waitingFor, .charcoal, "燃料が来ていない")
        XCTAssertTrue(r.events.contains(.moduleStopped(placement: furnace, reason: ProductionText.noAux)))
        let rep = try XCTUnwrap(ProductionQueries.module(furnace, world: w, content: fx.content))
        XCTAssertFalse(rep.running)
        XCTAssertEqual(rep.waitingFor, .charcoal)
        // 木炭が来れば動き出す
        var ctx = StepContext(world: w, content: fx.content)
        ctx.addStock(.item(.charcoal), 5, to: .base)
        w = ctx.world
        let r2 = fx.run(seconds: 60, &w)
        XCTAssertEqual(w.placements.items[furnace]?.status, .running)
        XCTAssertTrue(r2.events.contains(.moduleResumed(placement: furnace)))
    }

    func testDepositRunsDryAndMineheadStops() throws {
        let fx = try F()
        var w = fx.world()
        F.addDeposit(&w, at: GridPoint(14, 16), extractions: 2)
        let mine = fx.place(.minehead, 14, 16, &w)
        _ = fx.run(seconds: F.cycle * 3, &w)
        XCTAssertEqual(w.placements.items[mine]?.status, .stopped(reason: ProductionText.depleted), "鉱脈は有限で枯れる")
        XCTAssertEqual(w.map[.surface]?.deposits.deposit(at: GridPoint(14, 16))?.isDepleted, true)
    }

    // MARK: 片付ける(材料は全部戻る)・動かす

    func testDismantleReturnsEverything() throws {
        let fx = try F()
        var w = fx.world(wood: 10, charcoal: 0)
        let furnace = fx.place(.furnace, 16, 16, &w)
        // 待ちに物を入れておく
        var ctx = StepContext(world: w, content: fx.content)
        ModuleRuntime.put(StockEntry(stuff: .matter(.ironOre(purity: Purity(percent: 25))), quantity: 3),
                          into: &ctx.world.placements.items[furnace]!.module!.input)
        w = ctx.world
        XCTAssertEqual(w.inventory.quantity(.wood), 8)
        let r = fx.apply(.production(.dismantle(placement: furnace)), &w)
        XCTAssertNil(r.rejection)
        XCTAssertNil(w.placements.items[furnace])
        XCTAssertEqual(w.inventory.quantity(.wood), 10, "置いた材料は全部戻る")
        XCTAssertEqual(F.matterCount(w) { $0.stage == .ore }, 3, "待ちの物も戻る")
        XCTAssertFalse(w.auras.active.values.contains { $0.source == .placement(furnace) })
        XCTAssertTrue(r.events.contains { if case .dismantled(let p, _) = $0 { p == furnace } else { false } })
    }

    func testMoveKeepsBuffersAndChecksRules() throws {
        let fx = try F()
        var w = fx.world()
        F.addDeposit(&w, at: GridPoint(4, 4))
        F.addDeposit(&w, at: GridPoint(6, 4), id: "deposit.b")
        let mine = fx.place(.minehead, 4, 4, &w)
        XCTAssertEqual(fx.apply(.production(.move(placement: mine, to: F.wp(5, 4), facing: .east)), &w).rejection?.reason,
                       ProductionText.needsDeposit)
        XCTAssertNil(fx.apply(.production(.move(placement: mine, to: F.wp(6, 4), facing: .south)), &w).rejection)
        XCTAssertEqual(w.placements.items[mine]?.module?.deposit, DepositID("deposit.b"))
        XCTAssertEqual(w.placements.items[mine]?.module?.ports.outputs, [.south])
    }

    // MARK: 仲間が付くと速い

    func testOperatorWithMatchingSpecialtyIsFaster() throws {
        let fx = try F()
        func produced(withOperator: Bool) -> (Int, Int?) {
            var w = fx.world(charcoal: 200)
            let furnace = fx.place(.furnace, 15, 16, &w)
            var ctx = StepContext(world: w, content: fx.content)
            ModuleRuntime.put(StockEntry(stuff: .matter(.ironOre(purity: Purity(percent: 30))), quantity: 30),
                              into: &ctx.world.placements.items[furnace]!.module!.input)
            w = ctx.world
            if withOperator {
                // person.test_a の専門は smith(炉の専門と同じ)。配属して、炉のそばにいる
                w.people["person.test_a"]?.assignment = .operate(placement: furnace)
                w.people["person.test_a"]?.position = F.wp(15, 17)
            }
            // 試験用の炉は 1 回 480 秒。10 回ぶんの時間
            _ = fx.run(seconds: 480 * 10, &w)
            return (w.placements.items[furnace]?.module?.lifetimeProduced ?? 0,
                    ProductionQueries.module(furnace, world: w, content: fx.content)?.speedPermille)
        }
        let (alone, s0) = produced(withOperator: false)
        let (helped, s1) = produced(withOperator: true)
        XCTAssertEqual(alone, 10)
        XCTAssertEqual(s0, 1000)
        XCTAssertEqual(helped, 13, "専門一致 +30%")
        XCTAssertEqual(s1, 1300)
    }

    // MARK: 手作業と T1 への昇格

    func testHandworkHoldToFillAndPromotionByT1() throws {
        let fx = try F()
        var w = fx.world()
        let dep = F.addDeposit(&w, at: GridPoint(16, 17))
        // 押し続ける: 採掘は 8 回 × 160 秒 = 1280 秒で 1 回掘る
        XCTAssertNil(fx.apply(.production(.handwork(id: "handwork.mine", input: nil, holding: true)), &w).rejection)
        _ = fx.run(seconds: 1265, &w)
        XCTAssertEqual(F.matterCount(w, .person(.noah)) { $0.stage == .ore }, 0, "まだ満ちていない")
        XCTAssertGreaterThan(ProductionQueries.handworkProgress(world: w, content: fx.content) ?? 0, 900)
        _ = fx.run(seconds: 15, &w)
        XCTAssertEqual(F.matterCount(w, .person(.noah)) { $0.stage == .ore }, 2, "1 回 = 鉱脈 1 回ぶん(2 個)")
        XCTAssertEqual(w.map[.surface]?.deposits[dep]?.remainingExtractions, 59, "手で掘っても同じ有限の鉱脈が減る")
        // 離すと止まる
        _ = fx.apply(.production(.handwork(id: "handwork.mine", input: nil, holding: false)), &w)
        _ = fx.run(seconds: 3000, &w)
        XCTAssertEqual(F.matterCount(w, .person(.noah)) { $0.stage == .ore }, 2)

        // 工程の手作業: 炉(木炭)8 回、叩き台 16 回
        XCTAssertNil(fx.apply(.production(.handwork(id: "handwork.smelt", input: nil, holding: true)), &w).rejection)
        _ = fx.run(seconds: 8 * 160, &w)
        XCTAssertEqual(F.matterCount(w, .person(.noah)) { $0.stage == .metal && $0.shape == .lump }, 1)
        XCTAssertEqual(w.inventory.quantity(.charcoal), 39, "拠点の中なら燃料は蓄えから")
        _ = fx.apply(.production(.handwork(id: "handwork.smelt", input: nil, holding: false)), &w)
        let lump = try XCTUnwrap(w.inventory.entries(.person(.noah)).first { if case .matter(let m) = $0.stuff { m.stage == .metal } else { false } })
        let r = fx.apply(.production(.handwork(id: "handwork.hammer", input: StockSelector(holder: .person(.noah), stuff: lump.stuff), holding: true)), &w)
        XCTAssertNil(r.rejection)
        _ = fx.run(seconds: 16 * 160, &w)
        XCTAssertEqual(F.matterCount(w, .person(.noah), where: F.isPlate), 1)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .crafted }, "手で作ったことが来歴に残る")
        // 鉱石を叩いても変わらない(断る。所見の ID を添える)
        let ore = try XCTUnwrap(w.inventory.entries(.person(.noah)).first { if case .matter(let m) = $0.stuff { m.stage == .ore } else { false } })
        XCTAssertEqual(fx.apply(.production(.handwork(id: "handwork.hammer", input: StockSelector(holder: .person(.noah), stuff: ore.stuff), holding: true)), &w).rejection?.reason,
                       ProductionText.handworkNoEffect)

        // 昇格: 採掘口が動き出すと、採掘の手作業は任意になる
        XCTAssertEqual(ProductionQueries.handwork("handwork.mine", world: w, content: fx.content), .required)
        let mine = fx.place(.minehead, 16, 17, &w)
        _ = fx.run(seconds: 60, &w)
        guard case .optional(let m, let perDay) = ProductionQueries.handwork("handwork.mine", world: w, content: fx.content) else {
            return XCTFail("T1 が動いていれば任意")
        }
        XCTAssertEqual(m, mine)
        XCTAssertEqual(perDay, 19, "1 日 = 93600 秒 / 9600 秒 × 2 個")
        // 任意になっても手作業はできる
        XCTAssertNil(fx.apply(.production(.handwork(id: "handwork.mine", input: nil, holding: true)), &w).rejection)
    }

    func testHandworkIsDayOnlyUnlessAllowed() throws {
        let fx = try F()
        var w = fx.world()
        F.addDeposit(&w, at: GridPoint(16, 17))
        w.clock.phase = .nightWork
        XCTAssertEqual(fx.apply(.production(.handwork(id: "handwork.mine", input: nil, holding: true)), &w).rejection?.reason,
                       ProductionText.handworkNotNow)
        // 夜にもできる手作業は 1 単位ずつ時間を使う
        let before = w.clock.now
        let r = fx.apply(.production(.handwork(id: "handwork.test.forage", input: nil, holding: true)), &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.inventory.quantity("test.ration", in: .person(.noah)), 1)
        XCTAssertEqual((w.clock.now - before).seconds, 5 * 160 + 10, "800 秒をステップ(15 秒)に切り上げ")
    }

    // MARK: T1(工程の無いモジュール)

    func testT1ProducersRunInBase() throws {
        let fx = try F()
        var w = fx.world()
        _ = fx.place("test.gathering_post", 14, 15, &w)
        F.setWater(&w, at: GridPoint(18, 18))
        let boiler = fx.place("test.boiler", 17, 17, &w)
        _ = fx.run(seconds: F.cycle * 2, &w)
        XCTAssertEqual(w.inventory.quantity("test.ration"), 2)
        XCTAssertEqual(w.inventory.quantity("test.boiled_water"), 4, "煮沸場は薪を使って 1 回 2")
        XCTAssertEqual(w.placements.items[boiler]?.module?.today.produced, 4)
    }

    // MARK: 有限の品(使うと速いが、減ったら戻らない)

    func testFiniteBladeIsFastAndDoesNotComeBack() throws {
        let fx = try F()
        var w = fx.world()
        F.addDeposit(&w, at: GridPoint(16, 16), extractions: 70)
        let mine = fx.place(.minehead, 16, 16, &w)
        var ctx = StepContext(world: w, content: fx.content)
        let found = ctx.record(.scavenged, .item("test.relic_blade"))
        ctx.world.inventory.holders[.base, default: []].append(
            StockEntry(stuff: .item("test.relic_blade"), quantity: 1, origins: [found: 1], unique: EntityID(999)))
        w = ctx.world
        // 夜明けを迎えると、使わずにいたことが「取っておいた」として 1 度残る
        _ = fx.run(seconds: 26 * 3600, &w)
        XCTAssertEqual(w.ledger.records.filter { $0.act == .kept }.count, 1)
        let stock = StockSelector(holder: .base, stuff: .item("test.relic_blade"), unique: EntityID(999))
        let r = fx.apply(.production(.useFinite(placement: mine, stock: stock)), &w)
        XCTAssertNil(r.rejection)
        let use = try XCTUnwrap(w.ledger.records.last { $0.act == .used })
        XCTAssertEqual(use.subject, .entity(EntityID(999)))
        XCTAssertTrue(use.inputs.contains(found), "どこで拾った刃かを辿れる")
        XCTAssertTrue(r.events.contains(.finiteUsed(record: use.id)))
        XCTAssertEqual(ProductionQueries.module(mine, world: w, content: fx.content)?.speedPermille, 2000)
        XCTAssertEqual(w.inventory.quantity("test.relic_blade"), 0)
        // 10 回で尽きる(1 回 100‰)。尽きたら戻らない
        _ = fx.run(seconds: F.cycle / 2 * 11, &w)
        XCTAssertNil(w.placements.items[mine]?.module?.finite)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .consumed && $0.subject == .entity(EntityID(999)) })
        _ = fx.apply(.production(.dismantle(placement: mine)), &w)
        XCTAssertEqual(w.inventory.quantity("test.relic_blade"), 0, "片付けても、減った刃は戻らない")
    }

    func testFiniteBladeReturnsWithWearWhenDismantledEarly() throws {
        let fx = try F()
        var w = fx.world()
        F.addDeposit(&w, at: GridPoint(16, 16))
        let mine = fx.place(.minehead, 16, 16, &w)
        w.inventory.holders[.base, default: []].append(StockEntry(stuff: .item("test.relic_blade"), quantity: 1, unique: EntityID(7)))
        _ = fx.apply(.production(.useFinite(placement: mine, stock: StockSelector(holder: .base, stuff: .item("test.relic_blade"), unique: EntityID(7)))), &w)
        _ = fx.run(seconds: F.cycle / 2 * 3, &w)
        _ = fx.apply(.production(.dismantle(placement: mine)), &w)
        let blade = try XCTUnwrap(w.inventory.entries(.base).first { $0.unique == EntityID(7) })
        XCTAssertEqual(blade.durability, Milli(raw: 700), "減った分は戻らない")
    }

    // MARK: 来歴(ラインの生産は 1 個ずつ残さない)

    func testLineProductionIsCountedPerModuleRecord() throws {
        let fx = try F()
        var w = fx.world()
        F.addDeposit(&w, at: GridPoint(16, 16))
        let mine = fx.place(.minehead, 16, 16, &w)
        _ = fx.run(seconds: F.cycle * 3, &w)
        let recs = w.ledger.records.filter { $0.act == .produced && $0.subject == .module(.minehead, mine) }
        XCTAssertEqual(recs.count, 1, "同じ日・同じ入力なら 1 件にまとめる")
        XCTAssertEqual(recs.first?.count, 6, "鉄の鉱脈の採掘口は鉱石だけを出す(石は捨て石)")
        XCTAssertNotNil(w.ledger.first(.produced, .matter(NameGenerator.name(for: .ironOre(purity: Purity(percent: 30))))),
                        "初めての物の名前は 1 件残す(「初めて…をラインで作った」の条件)")
        // 蓄えの鉱石は、その記録から来たと分かる
        let ore = try XCTUnwrap(w.inventory.entries(.base).first { if case .matter = $0.stuff { true } else { false } })
        XCTAssertEqual(Set(ore.origins.keys), [recs[0].id])
    }

    // MARK: 決定性

    func testSameSeedSameCommandsSameWorld() throws {
        let fx = try F()
        func play() -> WorldState {
            var w = fx.world(seed: 5)
            F.addDeposit(&w, at: GridPoint(14, 16))
            let d = fx.design([.minehead, .charcoalFurnace, .anvil], &w)
            _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: F.wp(14, 16), facing: .east)), &w)
            _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 1, at: F.wp(18, 16), facing: .east)), &w)
            _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 2, at: F.wp(19, 16), facing: .east)), &w)
            _ = fx.run(seconds: 26 * 3600, &w)
            return w
        }
        XCTAssertEqual(play(), play())
    }
}

extension ProductionFixture {
    static var base_wp: WorldPoint { wp(base.x, base.y) }
}
