import RFContent
import RFFailure
import RFKernel
import RFRules
import RFSim
import RFSurvival
import RFTestSupport
import RFTime
import RFWorld
import XCTest

/// RFSurvival の受け入れテスト(docs/architecture/F-work-units.md の U4)。
final class SurvivalSystemTests: XCTestCase {
    let noah = PersonID.noah
    let a: PersonID = "person.test_a"
    let b: PersonID = "person.test_b"

    /// 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(SurvivalSystem().handle(foreign, &ctx), .notMine)
    }

    /// 生存の規則が無いコンテンツ(公開の試験用だけ)では、消費も作業の遅れも起きない(他の担当のテストを守る)。
    func testWithoutRulesNothingIsConsumed() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        _ = rig.simulation.runSteps(rig.stepsPerDay * 4, &w)
        XCTAssertTrue(w.run.isActive)
        XCTAssertEqual(w.survival.work, [:])
        XCTAssertEqual(w.survival.vitals, [:])
    }

    // MARK: - 1 人 1 日 食料 1・水 1(昼のリアルタイムと寝るの一括で一致)

    func testDailyConsumptionMatchesRealtimeAndSleep() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var start = rig.factory.newWorld(seed: 11)
        rig.stock(&start, "test.ration", 50)
        rig.stock(&start, "test.water_pack", 50)
        let pop = start.people.members.count
        XCTAssertEqual(pop, 3)

        // 昼を細かい刻みで → 夜作業 → 寝る
        var fine = start
        for _ in 0..<3 {
            _ = rig.playDay(&fine, dt: 1.0 / 60)
            _ = rig.simulation.apply(.time(.startNightWork), to: &fine)
            _ = rig.simulation.apply(.time(.sleep), to: &fine)
        }
        // 昼を粗い刻みで → すぐ寝る
        var coarse = start
        for _ in 0..<3 {
            _ = rig.playDay(&coarse, dt: 0.37)
            _ = rig.simulation.apply(.time(.sleep), to: &coarse)
        }
        // 全部を一括のステップで
        var bulk = start
        _ = rig.simulation.runSteps(rig.stepsPerDay * 3, &bulk)

        for w in [fine, coarse, bulk] {
            XCTAssertEqual(w.clock.day, 4)
            XCTAssertEqual(rig.count(w, "test.ration"), 50 - 3 * pop)
            XCTAssertEqual(rig.count(w, "test.water_pack"), 50 - 3 * pop)
        }
        XCTAssertEqual(fine.survival, coarse.survival)
        XCTAssertEqual(fine.survival, bulk.survival)
        XCTAssertEqual(fine.inventory, bulk.inventory)
        XCTAssertEqual(fine.people, bulk.people)
    }

    /// 蓄えが何日もつか(上の帯)は値で持つ。
    func testStockDaysIsAValue() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 1)
        rig.stock(&w, "test.ration", 6)
        rig.stock(&w, "test.water_pack", 3)
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)
        XCTAssertEqual(w.survival.stat("stat.food_days"), Milli(2))  // 6 個 ÷ 3 人
        XCTAssertEqual(w.survival.stat("stat.water_days"), Milli(1))
    }

    // MARK: - 失敗は値の規則(食料切れ 5 日・水切れ 3 日)

    func testStarvationFailsAfterFiveDaysByValue() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 2)
        rig.stock(&w, "test.water_pack", 100)
        var failedDay: Int?
        var last = Milli.zero
        for _ in 0..<10 where w.run.isActive {
            last = w.survival.stat("stat.days_without_food")
            _ = rig.simulation.runSteps(rig.stepsPerDay, &w)
            if !w.run.isActive { failedDay = w.clock.day }
        }
        // 最初の 1 食は 1 日目の終わり。そこから 5 日食べられずにいて失敗する
        XCTAssertEqual(failedDay, 7)
        XCTAssertLessThan(last.raw, 5000)
        XCTAssertGreaterThanOrEqual(w.survival.stat("stat.days_without_food").raw, 5000)
        XCTAssertEqual(w.survival.daysWithoutFood, 5)
        guard case .failed(let cause, _) = w.run.outcome else { return XCTFail("失敗していない") }
        XCTAssertEqual(cause, "text.test.starve")
    }

    func testDehydrationFailsAfterThreeDaysByValue() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 3)
        rig.stock(&w, "test.ration", 100)
        var failedDay: Int?
        for _ in 0..<10 where w.run.isActive {
            _ = rig.simulation.runSteps(rig.stepsPerDay, &w)
            if !w.run.isActive { failedDay = w.clock.day }
        }
        XCTAssertEqual(failedDay, 5)
        guard case .failed(let cause, _) = w.run.outcome else { return XCTFail("失敗していない") }
        XCTAssertEqual(cause, "text.test.thirst")
    }

    /// 食べられずにいても、物が手に入ればすぐ食べて、空腹の数え直しになる。
    func testEatingResetsHunger() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 4)
        rig.stock(&w, "test.water_pack", 100)
        _ = rig.simulation.runSteps(rig.stepsPerDay * 3, &w)
        XCTAssertGreaterThanOrEqual(w.survival.stat("stat.days_without_food").raw, 2000)
        rig.stock(&w, "test.ration", 3)
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)  // 次の区切りで食べる
        XCTAssertEqual(w.survival.stat("stat.days_without_food"), .zero)
        XCTAssertEqual(rig.count(w, "test.ration"), 0)
        XCTAssertNil(w.survival.vitals[noah]?.hungrySince)
    }

    // MARK: - 空腹の日は作業が遅い(−50%)

    func testHungerHalvesWorkSpeed() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 5)
        rig.stock(&w, "test.water_pack", 100)
        rig.stock(&w, "test.ration", 3)  // 1 日目の終わりの 1 食ぶんだけ
        _ = rig.simulation.runSteps(rig.stepsPerDay, &w)
        XCTAssertEqual(w.survival.workPermille(for: a), 1000)
        _ = rig.simulation.runSteps(rig.stepsPerDay, &w)  // 2 日目の終わりに食べられない
        for p in w.people.members { XCTAssertEqual(w.survival.workPermille(for: p), 500) }
        XCTAssertEqual(w.people[a]?.body.satiety, .zero)
    }

    // MARK: - 生水(選んで飲む・中毒の危険)と煮沸

    func testRawWaterIsAChoiceWithRisk() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 6)
        rig.stock(&w, "test.ration", 100)
        rig.stock(&w, "test.raw_water", 10)
        rig.stock(&w, "test.boiled_water", 1)
        _ = rig.simulation.runSteps(rig.stepsPerDay, &w)
        // 自動では生水を飲まない(煮沸した水は飲む)
        XCTAssertEqual(rig.count(w, "test.raw_water"), 10)
        XCTAssertEqual(rig.count(w, "test.boiled_water"), 0)
        XCTAssertEqual(w.people.members.filter { w.survival.vitals[$0]?.thirstySince != nil }.count, 2)

        let thirsty = w.people.members.first { w.survival.vitals[$0]?.thirstySince != nil }!
        let mindBefore = w.people[thirsty]!.body.mind
        let r = rig.simulation.apply(.survival(.consume(person: thirsty, stock: StockSelector(holder: .base, stuff: .item("test.raw_water")))), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertNil(w.survival.vitals[thirsty]?.thirstySince)
        XCTAssertEqual(w.people[thirsty]?.body.conditions["ailment.test.poison"], 1000)
        XCTAssertEqual(w.people[thirsty]!.body.mind.raw, mindBefore.raw - 2000)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .consumed && $0.actor == thirsty && $0.subject == .item("test.raw_water") })
        XCTAssertTrue(w.ledger.records.contains { $0.act == .wasInjured && $0.actor == thirsty })
        XCTAssertTrue(r.events.contains(.bodyChanged(person: thirsty)))

        // 中毒の間は作業が遅く、1 日で治る
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)
        XCTAssertEqual(w.survival.workPermille(for: thirsty), 700)
        _ = rig.simulation.runSteps(rig.stepsPerDay, &w)
        XCTAssertNil(w.people[thirsty]?.body.conditions["ailment.test.poison"])

        // 渇きを満たし、次の 1 回ぶんまでは先に飲める。それ以上は飲めない(足元カードに理由)
        var accepted = 0
        var last: StepReport?
        for _ in 0..<5 {
            let r = rig.simulation.apply(.survival(.consume(person: thirsty, stock: StockSelector(holder: .base, stuff: .item("test.raw_water")))), to: &w)
            last = r
            if r.rejection != nil { break }
            accepted += 1
        }
        XCTAssertEqual(accepted, 2)
        XCTAssertEqual(last?.rejection?.reason, "reason.survival.full")
    }

    // MARK: - 精神力: 外で減り、シェルターの中で戻る

    func testMindFallsOutsideAndRecoversInShelter() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 7)
        rig.stock(&w, "test.ration", 100)
        rig.stock(&w, "test.water_pack", 100)
        _ = rig.simulation.runSteps(rig.stepsPerHour * 8, &w)
        XCTAssertEqual(w.people[noah]?.body.mind, Milli(98))  // -0.25 / 時
        let pos = w.people[noah]!.position!
        _ = rig.build(&w, "structure.test.shelter", at: pos)
        _ = rig.simulation.runSteps(rig.stepsPerHour / 2, &w)
        XCTAssertEqual(w.people[noah]?.body.mind, Milli(99))  // +2 / 時
        _ = rig.simulation.runSteps(rig.stepsPerHour * 4, &w)
        XCTAssertEqual(w.people[noah]?.body.mind, Milli(100))  // 上限
    }

    /// 局所の範囲の効果(排気など)は、範囲の中の人の精神力だけを削る(R2 の中身の仕組み)。
    func testAuraReducesMindOnlyInside() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 8)
        rig.stock(&w, "test.ration", 100)
        rig.stock(&w, "test.water_pack", 100)
        let pos = w.people[noah]!.position!
        var far = pos
        far.point = GridPoint(pos.point.x + 5, pos.point.y)
        w.people[a]?.position = far
        let id = w.newEntityID()
        w.auras.active[id] = Aura(id: id, kind: "aura.test.exhaust", source: .point(pos), radius: 2,
                                  origin: ProvenanceLedger.unknownOrigin)
        _ = rig.simulation.runSteps(rig.stepsPerHour * 4, &w)
        XCTAssertEqual(w.people[noah]?.body.mind, Milli(95))  // -0.25×4 - 1×4
        XCTAssertEqual(w.people[a]?.body.mind, Milli(99))
        // 強さを半分にすると半分
        w.auras.active[id]?.strength = 500
        _ = rig.simulation.runSteps(rig.stepsPerHour * 4, &w)
        XCTAssertEqual(w.people[noah]?.body.mind, Milli(92))
    }

    // MARK: - 体の規則は全員に共通(REQ-S5)

    func testBodyRulesAreTheSameForEveryone() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 9)
        rig.stock(&w, "test.ration", 100)
        rig.stock(&w, "test.water_pack", 100)
        rig.stock(&w, "test.raw_water", 10)
        for p in [noah, a] {
            _ = rig.simulation.apply(.survival(.injure(person: p, amount: 30)), to: &w)
            _ = rig.simulation.apply(.survival(.consume(person: p, stock: StockSelector(holder: .base, stuff: .item("test.raw_water")))), to: &w)
        }
        var history: [(BodyState, BodyState)] = []
        for _ in 0..<12 {
            _ = rig.simulation.runSteps(rig.stepsPerHour * 4, &w)
            history.append((w.people[noah]!.body, w.people[a]!.body))
        }
        for (n, o) in history { XCTAssertEqual(n, o) }
        XCTAssertEqual(w.survival.workPermille(for: noah), w.survival.workPermille(for: a))
        XCTAssertEqual(w.survival.vitals[noah], w.survival.vitals[a])
    }

    /// 傷は全員に共通の速さで治り、治る速さは数値として見える(BEAT-15)。
    func testWoundHealsAtAVisibleCommonRate() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 10)
        rig.stock(&w, "test.ration", 100)
        rig.stock(&w, "test.water_pack", 100)
        let r = rig.simulation.apply(.survival(.injure(person: b, amount: 10)), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.people[b]?.body.health, Milli(90))
        XCTAssertEqual(w.people[b]?.body.conditions["ailment.wound"], 10)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .wasInjured && $0.subject == .person(b) })
        // 引き金の来歴を渡せば、wasInjured の inputs から辿れる(REQ-S6)
        var ctx = StepContext(world: w, content: rig.content)
        let trigger = ctx.record(.fought, .person(b), actor: b)
        w = ctx.world
        XCTAssertNil(rig.simulation.apply(.survival(.injure(person: b, amount: 0, cause: trigger)), to: &w).rejection)
        XCTAssertEqual(w.ledger.records.last { $0.act == .wasInjured }?.inputs, [trigger])
        XCTAssertNil(rig.simulation.apply(.survival(.afflict(person: b, ailment: "ailment.test.poison", severity: 0, cause: trigger)), to: &w).rejection)
        XCTAssertEqual(w.ledger.records.last { $0.act == .wasInjured }?.inputs, [trigger])
        _ = rig.simulation.runSteps(rig.stepsPerDay / 4, &w)  // 20 / 日 → 1/4 日で 5
        XCTAssertEqual(w.people[b]?.body.conditions["ailment.wound"], 5)
        _ = rig.simulation.runSteps(rig.stepsPerDay / 4, &w)
        XCTAssertNil(w.people[b]?.body.conditions["ailment.wound"])
    }

    /// 研究の建造物に付いている人(学ぶ時期)は食料の消費が増える(BEAT-15。全員に共通の規則)。
    func testStudyingEatsMore() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 12)
        rig.stock(&w, "test.water_pack", 100)
        for p in [noah, a, b] { rig.stock(&w, "test.ration", 20, to: .person(p)) }
        let desk = rig.build(&w, "structure.test.desk", at: w.people[b]!.position!)
        w.people[b]?.assignment = .operate(placement: desk)
        _ = rig.simulation.runSteps(rig.stepsPerDay * 4, &w)
        XCTAssertEqual(rig.count(w, "test.ration", in: .person(noah)), 16)
        XCTAssertEqual(rig.count(w, "test.ration", in: .person(a)), 16)
        XCTAssertEqual(rig.count(w, "test.ration", in: .person(b)), 14)  // 1.5 倍
    }

    /// スキルを習っている人は、研究の机の外にいても学ぶ時期として食料の消費が増える(BEAT-15。研究の担当の isLearning)。
    func testLearningASkillEatsMoreAwayFromTheDesk() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 16)
        rig.stock(&w, "test.water_pack", 100)
        for p in [noah, a] { rig.stock(&w, "test.ration", 20, to: .person(p)) }
        w.research.learning[a] = SkillLearning(skill: "skill.test.long", since: w.clock.now)
        XCTAssertTrue(w.research.isLearning(a))
        _ = rig.simulation.runSteps(rig.stepsPerDay * 4, &w)
        XCTAssertEqual(rig.count(w, "test.ration", in: .person(noah)), 16)
        XCTAssertEqual(rig.count(w, "test.ration", in: .person(a)), 14)
        XCTAssertNotNil(w.research.learning[a])  // まだ習っている途中
    }

    // MARK: - スタミナ: 歩いた分だけ減り、時間で戻る

    func testWalkingDrainsStaminaForEveryoneAlike() throws {
        let rig = try Fixture.rig(Fixture.survival)
        var w = rig.factory.newWorld(seed: 17)
        var ctx = StepContext(world: w, content: rig.content)
        let sys = SurvivalSystem()
        // 平地 10 マスぶん(moveCost 10 × 10)を、ノアと仲間が同じだけ歩いた
        for p in [noah, a] { sys.react(to: .walked(person: p, tiles: 10, staminaCost: 100), &ctx) }
        w = ctx.world
        XCTAssertEqual(w.people[noah]?.body.stamina.raw, 100_000 - 500)
        XCTAssertEqual(w.people[noah]?.body.stamina, w.people[a]?.body.stamina)
        // 大きく歩くと作業が遅くなる
        ctx = StepContext(world: w, content: rig.content)
        sys.react(to: .walked(person: noah, tiles: 1900, staminaCost: 19_000), &ctx)
        w = ctx.world
        rig.stock(&w, "test.ration", 100)
        rig.stock(&w, "test.water_pack", 100)
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)
        XCTAssertLessThan(w.people[noah]!.body.stamina.raw, 10_000)
        XCTAssertEqual(w.survival.workPermille(for: noah), 750)
        // 時間で戻る(+1.5 / 時)
        let before = w.people[noah]!.body.stamina.raw
        _ = rig.simulation.runSteps(rig.stepsPerHour * 4, &w)
        XCTAssertEqual(w.people[noah]!.body.stamina.raw, before + 6000)
        XCTAssertEqual(w.survival.workPermille(for: noah), 1000)
    }

    // MARK: - 拠点全体の数値: 内訳(基礎の上昇 + 上積み)と合計・暦・期限

    func testStatBreakdownAndSum() throws {
        let rig = try Fixture.rig(Fixture.stats)
        var w = rig.factory.newWorld(seed: 13)
        let id = w.newEntityID()
        w.auras.active[id] = Aura(id: id, kind: "aura.test.extra", source: .point(w.people[noah]!.position!),
                                  radius: 1, origin: ProvenanceLedger.unknownOrigin)
        _ = rig.simulation.runSteps(rig.stepsPerDay, &w)
        XCTAssertEqual(w.survival.stat("stat.test.gas.base").raw, 810)
        XCTAssertEqual(w.survival.stat("stat.test.gas.extra").raw, 10 * 26)
        XCTAssertEqual(w.survival.stat("stat.test.gas").raw, 810 + 260)
        XCTAssertEqual(w.survival.stat("stat.test.calendar").raw, 0)  // 暦は回る
        // 出来事の効果が内訳に足した分も合計に入る
        var ctx = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.stat(id: "stat.test.gas.extra", add: 100)], &ctx, cause: nil)
        w = ctx.world
        _ = rig.simulation.runSteps(rig.stepsPerTick, &w)
        XCTAssertEqual(w.survival.stat("stat.test.gas").raw,
                       w.survival.stat("stat.test.gas.base").raw + w.survival.stat("stat.test.gas.extra").raw)
        XCTAssertGreaterThanOrEqual(w.survival.stat("stat.test.gas.extra").raw, 360)
        XCTAssertTrue(rig.content.stats["stat.test.gas"]!.isAlert(1400))
        XCTAssertFalse(rig.content.stats["stat.test.gas"]!.isAlert(1399))
    }

    /// 警告と期限は日数でなく値で判定する。上積みが無ければ Day 80・120・150 に届く(OPEN-S2・§3.1)。
    func testMarksAndDeadlineReachedOnSchedule() throws {
        let rig = try Fixture.rig(Fixture.stats)
        let sim = Simulation(content: rig.content, systems: [TimeSystem(), SurvivalSystem(), FailureSystem()])
        var w = rig.factory.newWorld(seed: 14)
        var crossedDays: [Int] = []
        var guardDays = 0
        while w.run.isActive, guardDays < 200 {
            let r = sim.runSteps(rig.stepsPerDay, &w)
            for e in r.events { if case .statCrossed("stat.test.gas", _) = e { crossedDays.append(w.clock.day) } }
            guardDays += 1
        }
        XCTAssertEqual(crossedDays, [80, 120, 150])
        XCTAssertEqual(w.clock.day, 150)
        guard case .failed(let cause, _) = w.run.outcome else { return XCTFail("期限で失敗していない") }
        XCTAssertEqual(cause, "text.test.deadline")
    }

    /// 上積みがあれば期限は早く来る(値で判定しているから)。
    func testExtraBringsDeadlineCloser() throws {
        let rig = try Fixture.rig(Fixture.stats)
        let sim = Simulation(content: rig.content, systems: [TimeSystem(), SurvivalSystem(), FailureSystem()])
        var w = rig.factory.newWorld(seed: 15)
        var ctx = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.stat(id: "stat.test.gas.extra", add: 700)], &ctx, cause: nil)
        w = ctx.world
        while w.run.isActive, w.clock.day < 200 { _ = sim.runSteps(rig.stepsPerDay, &w) }
        XCTAssertEqual(w.clock.day, 10)  // 上積みが無ければ 150
    }
}
