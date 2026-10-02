import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld
import XCTest

/// TEST-O4 炉の熱(序盤の設計 W-03・P-04・P-05)。
final class FurnaceHeatTests: XCTestCase {
    typealias F = ProductionFixture
    static let hour: Int64 = 3600

    /// 炉に熱の定義(R1 の既定)を付けた内容。batch はデータ(P-05)。
    func fixture(batch: Int = 2) throws -> F {
        try F { c in
            c.modules[.furnace]?.hearth = HearthDef(capSeconds: 0, fuels: [:], thresholds: [0, 0, 0, 0],
                                                    light: [0, 0, 0, 0, 0], burnPermille: [0, 0, 0, 0, 0],
                                                    furnace: FurnaceHeatDef())
            c.modules[.furnace]?.batch = batch
        }
    }

    /// 採掘口 → 炉(木炭)のライン。炉の ID を返す。
    func line(_ fx: F, _ w: inout WorldState) -> EntityID {
        F.addDeposit(&w, at: GridPoint(14, 16), percent: 30, extractions: 200)
        let d = fx.design([.minehead, .charcoalFurnace], &w)
        _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 0, at: F.wp(14, 16), facing: .east)), &w)
        _ = fx.apply(.production(.placeFromDesign(design: d, stepIndex: 1, at: F.wp(15, 16), facing: .east)), &w)
        return w.placements.at(F.wp(15, 16))[0]
    }

    func charcoal(_ w: WorldState, _ furnace: EntityID) -> Int {
        w.inventory.quantity(.charcoal) + (w.placements.items[furnace]?.module?.inputCount(.charcoal) ?? 0)
    }

    func temp(_ w: WorldState, _ furnace: EntityID, _ fx: F) -> Int {
        FurnaceHeat.temperature(w.placements.items[furnace]!, fx.content) ?? -1
    }

    func preheat(_ fx: F, _ w: inout WorldState, _ furnace: EntityID) -> Rejection? {
        fx.apply(.base(.hearth(placement: furnace, op: .preheat)), &w).rejection
    }

    /// 冷えた炉は予熱の前は溶かさない。予熱(木炭 2・1.5 時間)で 1100℃ になり、動き出す。
    func testColdFurnaceWaitsForPreheat() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 40)
        let furnace = line(fx, &w)
        _ = fx.run(seconds: 9600 * 2, &w)
        XCTAssertEqual(w.placements.items[furnace]?.status, .stopped(reason: FurnaceHeat.furnaceCold))
        XCTAssertEqual(w.placements.items[furnace]?.module?.today.produced, 0)
        let before = charcoal(w, furnace)
        XCTAssertNil(preheat(fx, &w, furnace))
        XCTAssertEqual(charcoal(w, furnace), before - 2, "予熱に木炭 2")
        XCTAssertEqual(preheat(fx, &w, furnace)?.reason, FurnaceHeat.alreadyHot)
        _ = fx.run(seconds: 3600, &w)
        XCTAssertLessThan(temp(w, furnace, fx), 1100, "1 時間ではまだ")
        _ = fx.run(seconds: 1800, &w)
        XCTAssertGreaterThanOrEqual(temp(w, furnace, fx), 1100, "1.5 時間で 1100℃")
        _ = fx.run(seconds: 9600 * 2, &w)
        XCTAssertGreaterThan(w.placements.items[furnace]?.module?.today.produced ?? 0, 0)
        // 熱い炉は灯り(半径 3)
        XCTAssertEqual(Hearths.lightRadius(w.placements.items[furnace]!, fx.content), 3)
    }

    /// 熱い間は木炭を 0.4/時で使う(塊の数ではなく時間で)。夜も熱いまま。1 回で塊 2(batch 2)。
    func testBurnsFuelByTimeAndStaysHotOvernight() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 40)
        let furnace = line(fx, &w)
        XCTAssertNil(preheat(fx, &w, furnace))
        _ = fx.run(seconds: 5400, &w)
        let c0 = charcoal(w, furnace)
        let made0 = w.placements.items[furnace]?.module?.lifetimeProduced ?? 0
        _ = fx.run(seconds: 26 * Self.hour, &w)   // 丸 1 日(昼と夜)
        let used = c0 - charcoal(w, furnace)
        XCTAssertTrue((10...11).contains(used), "26 時間で木炭 10.4 前後: \(used)")
        XCTAssertGreaterThanOrEqual(temp(w, furnace, fx), 1100, "燃料が続く間は夜も熱い")
        let made = (w.placements.items[furnace]?.module?.lifetimeProduced ?? 0) - made0
        XCTAssertGreaterThan(made, 0)
        XCTAssertEqual(made % 2, 0, "1 回で塊 2")
    }

    /// 燃料が来ないと 1 時間に 200℃ 下がり、1100℃ を切ると止まって理由が出る。予熱し直しが要る。
    func testCoolsWithoutFuelAndStops() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 4)
        let furnace = line(fx, &w)
        XCTAssertNil(preheat(fx, &w, furnace))
        _ = fx.run(seconds: 5400, &w)
        // 木炭を取り上げる
        w.inventory.holders[.base] = w.inventory.entries(.base).filter { $0.stuff != .item(.charcoal) }
        w.placements.items[furnace]?.module?.input.removeAll { $0.stuff == .item(.charcoal) }
        let t0 = temp(w, furnace, fx)
        _ = fx.run(seconds: Self.hour, &w)
        XCTAssertEqual(t0 - temp(w, furnace, fx), 200, "1 時間で 200℃")
        _ = fx.run(seconds: 2 * Self.hour, &w)
        XCTAssertLessThan(temp(w, furnace, fx), 1100)
        XCTAssertEqual(w.placements.items[furnace]?.status, .stopped(reason: FurnaceHeat.furnaceCold))
        XCTAssertEqual(Hearths.lightRadius(w.placements.items[furnace]!, fx.content), 0)
        XCTAssertEqual(preheat(fx, &w, furnace)?.reason, FurnaceHeat.noPreheatFuel, "予熱の木炭が無い")
    }

    /// 薪だけでは 1100℃ に届かない(予熱できず、熱い炉に薪をくべても保てない)。
    func testWoodAloneDoesNotReachWorkingHeat() throws {
        let fx = try fixture()
        var w = fx.world(wood: 40, charcoal: 2)
        let furnace = line(fx, &w)
        XCTAssertNil(preheat(fx, &w, furnace))
        _ = fx.run(seconds: 5400, &w)
        w.placements.items[furnace]?.module?.input.removeAll { $0.stuff == .item(.charcoal) }
        ModuleRuntime.put(StockEntry(stuff: .item(.wood), quantity: 20, origins: [ProvenanceLedger.unknownOrigin: 20]),
                          into: &w.placements.items[furnace]!.module!.input)
        _ = fx.run(seconds: 3 * Self.hour, &w)
        XCTAssertLessThan(temp(w, furnace, fx), 1100)
        XCTAssertEqual(w.placements.items[furnace]?.module?.inputCount(.wood), 20, "薪は炉の熱にならない")
        // 内容が薪を燃料にしても、薪の上限 900℃ で止まる
        let def = FurnaceHeatDef(burnPerHour: ["wood": 1000])
        XCTAssertEqual(def.cap("wood"), 900)
    }

    /// 熱の定義の無い炉(古い形の内容)は今どおり: 熱を見ず、木炭は塊ごとに入口から使う。
    func testOldFurnaceWithoutHeatIsUnchanged() throws {
        let fx = try F()
        var w = fx.world(charcoal: 40)
        let furnace = line(fx, &w)
        _ = fx.run(seconds: 9600 * 3, &w)
        let p = w.placements.items[furnace]!
        XCTAssertTrue(FurnaceHeat.isHot(p, fx.content))
        XCTAssertTrue(FurnaceHeat.fuels(p, fx.content).isEmpty)
        XCTAssertNil(p.module?.hearth?.heat)
        XCTAssertGreaterThan(p.module?.lifetimeProduced ?? 0, 0)
        XCTAssertEqual(fx.apply(.base(.hearth(placement: furnace, op: .preheat)), &w).rejection?.reason,
                       FurnaceHeat.notFurnace)
    }

    /// 手で溶かす(工程の燃料に木炭 1)を熱い炉の隣でやっても、木炭は工程から取らない(炉が時間で燃やす分だけ)。
    /// 冷えた炉の隣では断る。工程の木炭の入力は、熱の定義の無い古い炉のため(RuleBook の燃料)に残してよい。
    func testHandSmeltAtHotFurnaceDoesNotPayFuelTwice() throws {
        let fx = try fixture()
        var w = fx.world(charcoal: 40)
        let furnace = line(fx, &w)
        var ctx = StepContext(world: w, content: fx.content)
        ctx.addStock(.matter(.ironOre(purity: Purity(basisPoints: 3000))), 2, to: .person(.noah))
        w = ctx.world
        let ore = try XCTUnwrap(w.inventory.entries(.person(.noah)).first {
            if case .matter(let m) = $0.stuff { m.stage == .ore } else { false }
        })
        let smelt = Command.production(.handwork(id: "handwork.smelt",
                                                 input: StockSelector(holder: .person(.noah), stuff: ore.stuff),
                                                 holding: true))
        XCTAssertEqual(fx.apply(smelt, &w).rejection?.reason, FurnaceHeat.furnaceCold, "冷えた炉の隣では断る")
        XCTAssertNil(preheat(fx, &w, furnace))
        _ = fx.run(seconds: 5400, &w)
        XCTAssertTrue(FurnaceHeat.isHot(w.placements.items[furnace]!, fx.content))

        var idle = w
        XCTAssertNil(fx.apply(smelt, &w).rejection)
        _ = fx.run(seconds: 8 * 160, &w)
        _ = fx.run(seconds: 8 * 160, &idle)
        XCTAssertEqual(F.matterCount(w, .person(.noah)) { $0.stage == .metal }, 1, "手で溶かした塊")
        XCTAssertEqual(charcoal(w, furnace), charcoal(idle, furnace), "工程の木炭は取らない(二重に払わない)")
    }

    /// 寝るで一括に進めても、刻んで進めても、同じ熱と燃料になる。
    func testSameHeatWhetherSteppedOrBatched() throws {
        let fx = try fixture()
        var a = fx.world(charcoal: 40)
        let fa = line(fx, &a)
        XCTAssertNil(preheat(fx, &a, fa))
        var b = a
        _ = fx.run(seconds: 10 * Self.hour, &a)
        for _ in 0..<40 { _ = fx.run(seconds: 900, &b) }
        XCTAssertEqual(a.placements.items[fa]?.module?.hearth, b.placements.items[fa]?.module?.hearth)
    }
}
