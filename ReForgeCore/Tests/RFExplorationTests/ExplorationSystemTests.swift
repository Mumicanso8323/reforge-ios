import RFContent
import RFExploration
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// RFExploration の受け入れテスト(F-work-units.md U8: 残骸を漁る 10 回まで・得られる物の表 / 有限の部品の
/// 取り外し・解体・作り直しが来歴に残る)と、行為・区画の出来事の仕組み。
final class ExplorationSystemTests: XCTestCase {
    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(ExplorationSystem().handle(foreign, &ctx), .notMine)
    }

    // MARK: 残骸を漁る

    /// 残骸を漁れるのは 10 回まで。1 回ごとに保存食 2〜4・枝 2〜3、水パック 1〜3(80%)・繊維 2(30%)・金属片 1(40%)。
    func testScavengeHomeWreckTenTimesWithOriginalTable() throws {
        var rig = try ExploreRig(seed: 3)
        for i in 0..<10 {
            let before = (rig.qty("ration"), rig.qty("stick"), rig.qty("water_pack"), rig.qty("plant_fiber"),
                          rig.qty("metal_scrap"))
            XCTAssertNil(rig.interact("interaction.scavenge", at: rig.wreckAt), "\(i) 回目")
            XCTAssertTrue((2...4).contains(rig.qty("ration") - before.0))
            XCTAssertTrue((2...3).contains(rig.qty("stick") - before.1))
            XCTAssertTrue([0, 1, 2, 3].contains(rig.qty("water_pack") - before.2))
            XCTAssertTrue([0, 2].contains(rig.qty("plant_fiber") - before.3))
            XCTAssertTrue([0, 1].contains(rig.qty("metal_scrap") - before.4))
        }
        XCTAssertEqual(rig.interact("interaction.scavenge", at: rig.wreckAt)?.reason, "reason.explore.exhausted")
        let left = rig.world.map[.surface]!.placements[.homeWreck]!.remainingUses
        XCTAssertEqual(left, 0)
        let recs = rig.records(.scavenged)
        XCTAssertEqual(recs.count, 10)
        XCTAssertEqual(recs.first?.subject, .poi("wreck.home", rig.wreck))
        // 拠点の蓄えの保存食の来歴は漁った記録を指す
        let ration = rig.world.inventory.entries(.base).first { $0.stuff == .item("ration") }!
        XCTAssertTrue(Set(ration.origins.keys).isSubset(of: Set(recs.map(\.id))))
    }

    /// 確率の物は原作の率に近い(多 seed で 80% / 30% / 40%)。
    func testScavengeChancesMatchOriginal() throws {
        var water = 0, fiber = 0, metal = 0, n = 0
        for seed in 0..<30 {
            var rig = try ExploreRig(seed: UInt64(seed))
            for _ in 0..<10 {
                let w = rig.qty("water_pack"), f = rig.qty("plant_fiber"), m = rig.qty("metal_scrap")
                XCTAssertNil(rig.interact("interaction.scavenge", at: rig.wreckAt))
                water += rig.qty("water_pack") > w ? 1 : 0
                fiber += rig.qty("plant_fiber") > f ? 1 : 0
                metal += rig.qty("metal_scrap") > m ? 1 : 0
                n += 1
            }
        }
        XCTAssertEqual(Double(water) / Double(n), 0.8, accuracy: 0.07)
        XCTAssertEqual(Double(fiber) / Double(n), 0.3, accuracy: 0.07)
        XCTAssertEqual(Double(metal) / Double(n), 0.4, accuracy: 0.07)
    }

    /// 同じ seed と同じ操作なら同じ物が出る(探索の乱数の流れだけを使う)。
    func testScavengeIsDeterministic() throws {
        var a = try ExploreRig(seed: 9)
        var b = try ExploreRig(seed: 9)
        for _ in 0..<5 {
            a.interact("interaction.scavenge", at: a.wreckAt)
            b.interact("interaction.scavenge", at: b.wreckAt)
        }
        XCTAssertEqual(a.world, b.world)
    }

    /// 届かない所からはできない(足元カードの理由を返すだけで、止めない)。
    func testTooFarIsRejected() throws {
        var rig = try ExploreRig()
        rig.put(.noah, rig.wreckAt + GridPoint(6, 0))
        XCTAssertEqual(rig.interact("interaction.scavenge", at: rig.wreckAt)?.reason, "reason.explore.too_far")
    }

    // MARK: 有限の部品

    /// 区画は 1 マス 1 つ。取り外し → 解体 → 作り直しが状態と来歴に残り、解体済みは戻らない。
    func testPartsSalvageDismantleRebuildAreRecorded() throws {
        var rig = try ExploreRig()
        // 部品 b は足跡の (y,x) 順で 2 番目のマス = (1, 0)
        let cellB = rig.wreckAt + GridPoint(1, 0)
        XCTAssertNil(rig.interact("interaction.salvage_part", at: cellB))
        let prog = rig.world.exploration.poi[rig.wreck]!
        guard case .salvaged(let r1) = prog.part("part.test.b") else { return XCTFail("取り外していない") }
        XCTAssertEqual(rig.world.ledger.record(r1)?.act, .salvagedPart)
        XCTAssertEqual(rig.world.ledger.record(r1)?.subject, .part(rig.wreck, "part.test.b"))
        // 焼け残りの刃(試験用): 唯一品で、減ったら戻らない残りを持つ
        let blade = rig.world.inventory.entries(.base).first { $0.stuff == .item("test_relic_blade") }
        XCTAssertNotNil(blade?.unique)
        XCTAssertEqual(blade?.durability, Milli(raw: 1000))
        XCTAssertEqual(blade?.origins.keys.first, r1)

        // 同じマスをもう一度取り外すことはできない(他の無傷の区画が選ばれる)
        XCTAssertNil(rig.interact("interaction.salvage_part", at: cellB))
        XCTAssertEqual(rig.world.exploration.poi[rig.wreck]!.part("part.test.a").name, .salvaged)

        // 解体は押し続ける行為: 押すのをやめると止まる
        rig.apply(.exploration(.interact(interaction: "interaction.dismantle_part", at: WorldPoint(.surface, cellB),
                                         holding: true)))
        rig.steps(4)
        rig.apply(.exploration(.interact(interaction: "interaction.dismantle_part", at: WorldPoint(.surface, cellB),
                                         holding: false)))
        let paused = rig.world.exploration.active[.noah]?.progress
        rig.steps(20)
        XCTAssertEqual(rig.world.exploration.active[.noah]?.progress, paused)
        XCTAssertNil(rig.interact("interaction.dismantle_part", at: cellB, holding: true))
        guard case .dismantled(let r2) = rig.world.exploration.poi[rig.wreck]!.part("part.test.b") else {
            return XCTFail("解体していない")
        }
        XCTAssertGreaterThanOrEqual(rig.qty("metal_scrap"), 3)

        // 条件「部品の状態」が解体を見る(後の出来事・修理の要求が指す)
        let cond = Condition.part(poiKind: "wreck.home", part: "part.test.b", state: .dismantled)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(cond, world: rig.world, content: rig.content), true)

        // 解体済みは戻らない(もう一度解体はできない)。作り直しは自分の工業の材料が要る
        XCTAssertEqual(rig.interact("interaction.rebuild_part", at: cellB)?.reason, "reason.explore.missing_cost")
        var ctx = StepContext(world: rig.world, content: rig.content)
        let made = ctx.record(.crafted, .item("test_plate"), actor: .noah)
        ctx.addStock(.item("test_plate"), 2, to: .base, origin: made)
        rig.world = ctx.world
        XCTAssertNil(rig.interact("interaction.rebuild_part", at: cellB))
        guard case .rebuilt(let r3) = rig.world.exploration.poi[rig.wreck]!.part("part.test.b") else {
            return XCTFail("作り直していない")
        }
        let rebuilt = rig.world.ledger.record(r3)!
        XCTAssertEqual(rebuilt.act, .rebuiltPart)
        XCTAssertTrue(rebuilt.inputs.contains(made), "作り直しの記録は使った材料の来歴を指す")
        XCTAssertNotEqual(r2, r3)
        XCTAssertNotNil(rig.world.ledger.first(.salvagedPart, .part(rig.wreck, "part.test.b")))
        XCTAssertNotNil(rig.world.ledger.first(.rebuiltPart, .part(rig.wreck, "part.test.b")))
        // 部品の行為は残骸を漁る回数を減らさない
        XCTAssertEqual(rig.world.map[.surface]!.placements[.homeWreck]!.remainingUses, 10)
    }

    /// 修理の段階は 1 つずつ進む。解体した部品は直せない。段階の効果で事実を知る(機能が開く)。
    func testRepairStagesOneByOne() throws {
        var rig = try ExploreRig { c in
            var two = c.interactions["interaction.repair_part"]!
            two.id = "interaction.repair_part_2"
            two.partOp?.repairTo = 2
            two.effects = nil
            c.interactions[two.id] = two
        }
        var ctx = StepContext(world: rig.world, content: rig.content)
        ctx.addStock(.item("test_part"), 3, to: .base)
        rig.world = ctx.world
        XCTAssertEqual(rig.interact("interaction.repair_part_2", at: rig.wreckAt)?.reason, "reason.explore.part_state")
        XCTAssertNil(rig.interact("interaction.repair_part", at: rig.wreckAt))
        XCTAssertEqual(rig.world.exploration.poi[rig.wreck]?.repair["part.test.c"], 1)
        XCTAssertTrue(rig.world.knowledge.knows("fact.test.terminal_1"))
        XCTAssertNil(rig.interact("interaction.repair_part_2", at: rig.wreckAt))
        XCTAssertEqual(rig.world.exploration.poi[rig.wreck]?.repair["part.test.c"], 2)
        XCTAssertEqual(rig.records(.repaired).count, 2)

        var broken = try ExploreRig()
        // 部品 c((y,x) 順で 3 番目 = (2, 0))を解体してから直そうとする
        XCTAssertNil(broken.interact("interaction.dismantle_part", at: broken.wreckAt + GridPoint(2, 0)))
        var bctx = StepContext(world: broken.world, content: broken.content)
        bctx.addStock(.item("test_part"), 1, to: .base)
        broken.world = bctx.world
        XCTAssertEqual(broken.interact("interaction.repair_part", at: broken.wreckAt)?.reason, "reason.explore.part_state")
    }

    // MARK: 行為の進み方

    /// 夜作業ではその場で終わり、かかった時間を返す(本体がその分のステップを進める)。
    func testNightWorkCompletesAtOnce() throws {
        var rig = try ExploreRig()
        rig.world.clock.phase = .nightWork
        let before = rig.world.clock.now
        let r = rig.apply(.exploration(.interact(interaction: "interaction.scavenge",
                                                 at: WorldPoint(.surface, rig.wreckAt), holding: true)))
        XCTAssertNil(r.rejection)
        XCTAssertNil(rig.world.exploration.active[.noah])
        XCTAssertEqual(rig.records(.scavenged).count, 1)
        XCTAssertEqual(r.steps, 4)
        XCTAssertGreaterThanOrEqual(rig.world.clock.now.seconds - before.seconds, 0)
    }

    /// 歩き出して届かなくなったら取りやめ、使った材料は同じ来歴で戻る。
    func testMovingAwayCancelsAndRefunds() throws {
        var rig = try ExploreRig()
        var ctx = StepContext(world: rig.world, content: rig.content)
        let made = ctx.record(.crafted, .item("test_part"))
        ctx.addStock(.item("test_part"), 1, to: .base, origin: made)
        rig.world = ctx.world
        rig.apply(.exploration(.interact(interaction: "interaction.repair_part", at: WorldPoint(.surface, rig.wreckAt),
                                         holding: true)))
        XCTAssertEqual(rig.qty("test_part"), 0)
        rig.put(.noah, rig.wreckAt + GridPoint(0, 8))
        rig.steps(1)
        XCTAssertNil(rig.world.exploration.active[.noah])
        XCTAssertEqual(rig.qty("test_part"), 1)
        XCTAssertEqual(rig.world.inventory.entries(.base).first { $0.stuff == .item("test_part") }?.origins, [made: 1])
    }

    /// 採集のクールダウン(原作 HarvestSystem: 枝 5 日)。
    func testHarvestCooldown() throws {
        var rig = try ExploreRig()
        let spot = rig.noahPos.point + GridPoint(1, 0)
        rig.world.map[.surface]?.setTerrain("forest", at: spot)
        XCTAssertNil(rig.interact("interaction.pick_sticks", at: spot))
        XCTAssertEqual(rig.interact("interaction.pick_sticks", at: spot)?.reason, "reason.explore.cooldown")
        rig.world.clock.day += 5
        XCTAssertNil(rig.interact("interaction.pick_sticks", at: spot))
        XCTAssertEqual(rig.records(.gathered).count, 2)
    }

    /// 大きすぎる扉や設備は 2 人で付かないと進まない(BEAT-16 の形)。
    func testRequiredPeople() throws {
        var rig = try ExploreRig { c in
            c.interactions["interaction.test.heavy"] = .make(
                id: "interaction.test.heavy", target: .poi(kind: "wreck.home"), seconds: 30, limit: 1,
                yields: [.of("metal_scrap", 1, 1)], requiredPeople: 2)
        }
        let far = rig.wreckAt + GridPoint(10, 0)
        rig.put("person.test_a", far)
        rig.put("person.test_b", far)
        XCTAssertEqual(rig.interact("interaction.test.heavy", at: rig.wreckAt)?.reason, "reason.explore.need_more_people")
        rig.put("person.test_a", rig.wreckAt + GridPoint(3, 0))
        XCTAssertNil(rig.interact("interaction.test.heavy", at: rig.wreckAt))
        XCTAssertEqual(rig.qty("metal_scrap"), 1)
    }

    /// 鉱脈を手で掘ると、鉱脈の純度のままの鉄鉱石(物質)が入り、残りの回数が減る。
    func testMiningDepositByHand() throws {
        var rig = try ExploreRig()
        let spot = rig.noahPos.point + GridPoint(0, 1)
        var rng = SeededRandom(state: 5)
        let dep = DepositGenerator.make(id: "deposit.test", at: spot, category: .iron, rng: &rng, primaryPercent: 30...30)
        _ = rig.world.map[.surface]?.deposits.add(dep)
        XCTAssertNil(rig.interact("interaction.mine_by_hand", at: spot))
        let ore = rig.world.inventory.entries(.base).compactMap { e -> Matter? in
            if case .matter(let m) = e.stuff { return m } else { return nil }
        }
        XCTAssertFalse(ore.isEmpty)
        XCTAssertEqual(ore.first?.stage, .ore)
        XCTAssertEqual(rig.world.map[.surface]!.deposits["deposit.test"]!.remainingExtractions, dep.remainingExtractions - 1)
        XCTAssertEqual(rig.records(.mined).count, 1)
    }

    // MARK: 効果から

    func testEffectCommandsChangeMapAndParts() throws {
        var rig = try ExploreRig()
        var ctx = StepContext(world: rig.world, content: rig.content)
        let cause = ctx.record(.chose, .none)
        let sys = ExplorationSystem()
        let c = WorldPoint(.surface, GridPoint(4, 4))
        XCTAssertEqual(sys.handle(.exploration(.revealMap(around: c, radius: 2, cause: cause)), &ctx), .done)
        XCTAssertTrue(ctx.world.knowledge.mapKnown[.surface]![GridPoint(4, 5)])
        XCTAssertEqual(sys.handle(.exploration(.setTerrain(at: c, terrain: "rock", cause: cause)), &ctx), .done)
        XCTAssertEqual(ctx.world.map[.surface]?.terrain(at: c.point), "rock")
        XCTAssertTrue(ctx.world.ledger.records.last!.inputs.contains(cause))
        let rec = ctx.record(.salvagedPart, .part(rig.wreck, "part.test.d"))
        XCTAssertEqual(sys.handle(.exploration(.setPart(poi: rig.wreck, part: "part.test.d", state: .dismantled(record: rec))), &ctx),
                       .done)
        XCTAssertEqual(ctx.world.exploration.poi[rig.wreck]?.part("part.test.d"), .dismantled(record: rec))
        XCTAssertTrue(ctx.drainEvents().contains(.partChanged(poi: rig.wreck, part: "part.test.d", record: rec)))
        rig.world = ctx.world
    }
}
