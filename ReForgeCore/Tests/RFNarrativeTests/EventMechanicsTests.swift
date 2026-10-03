import Foundation
import RFContent
import RFKernel
import RFMap
import RFMatter
import RFNarrative
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U11 出来事の受け入れテスト(F-work-units.md の U11 行)。
/// 公開の試験用コンテンツ content/public/narrative/mechanics.json を使う(物語は無い)。
final class EventMechanicsTests: XCTestCase {
    // MARK: - 道具

    private func settle(_ rig: TestRig, _ ctx: inout StepContext) -> StepReport {
        var r = StepReport()
        rig.simulation.settle(&ctx, &r)
        return r
    }

    /// 置いた物を 1 つ地図に足し、来歴と出来事を出す(生産・拠点の担当のコマンドの代わり)。
    @discardableResult
    private func place(_ ctx: inout StepContext, module: ModuleKindID? = nil, structure: StructureKindID? = nil,
                       at: WorldPoint) -> EntityID
    {
        let id = ctx.world.newEntityID()
        let kind: PlaceableKind = module.map { .module($0) } ?? .structure(structure!)
        let subject: SubjectRef = module.map { .module($0, id) } ?? .structure(structure!, id)
        let rec = ctx.record(module != nil ? .placed : .built, subject, actor: .noah, place: at)
        ctx.world.placements.items[id] = Placement(id: id, kind: kind, at: at, facing: .north, origin: rec, status: .running)
        ctx.emit(module != nil ? .placed(placement: id, record: rec) : .built(placement: id, record: rec))
        return id
    }

    private func firedIDs(_ events: [DomainEvent]) -> [EventID] {
        events.compactMap { if case .eventFired(let id, _) = $0 { id } else { nil } }
    }

    private func spawn(_ w: WorldState) -> WorldPoint { w.people[.noah]!.position! }

    /// 時間と出来事だけの本体(長い走行を軽くする。人の歩く・視界などは各担当のテストと受け入れテストで見る)。
    private func timeAndNarrative(_ rig: TestRig) -> Simulation {
        Simulation(content: rig.content, systems: Simulation.standardSystems.filter { ["time", "narrative"].contains($0.name) })
    }

    // MARK: - TEST-S5 決定性

    /// 同じ seed と同じ操作の列なら、同じ出来事の列・同じ世界(確率の出来事を含む)。別の seed では確率の出来事が変わる。
    func testSameSeedSameEventSequence() throws {
        let rig = try TestRig.publicOnly()
        func run(_ seed: UInt64) -> ([EventID], WorldState) {
            var w = rig.factory.newWorld(seed: seed)
            var events: [DomainEvent] = []
            for _ in 0..<1 {
                var r = rig.playDay(&w, dt: 1)
                r.merge(rig.simulation.apply(.time(.startNightWork), to: &w))
                r.merge(rig.simulation.apply(.time(.sleep), to: &w))
                XCTAssertEqual(r.warnings, [])
                events += r.events
            }
            return (firedIDs(events), w)
        }
        let (a, wa) = run(11)
        let (b, wb) = run(11)
        XCTAssertEqual(a, b)
        XCTAssertEqual(wa, wb)
        XCTAssertFalse(a.isEmpty)
        // 確率の出来事(1 日 1 回・夜明け・物語の乱数の流れ)は seed で変わる
        let light = timeAndNarrative(rig)
        let luckyRuns = Set((1...6).map { seed -> Int in
            var w = rig.factory.newWorld(seed: UInt64(seed))
            let r = light.runSteps(Int(3 * 26 * 3600 / SimStep.gameSeconds), &w)
            return firedIDs(r.events).filter { $0 == "event.test.lucky" }.count
        })
        XCTAssertGreaterThan(luckyRuns.count, 1)
        XCTAssertTrue(luckyRuns.allSatisfy { $0 <= 3 }, "1 日 1 回まで")
    }

    /// 物語の乱数の流れだけを使う: 他の流れ(地図・生産…)を引いても出来事の列は変わらない。
    func testNarrativeUsesOwnRandomStream() throws {
        let rig = try TestRig.publicOnly()
        let light = timeAndNarrative(rig)
        let day = Int(26 * 3600 / SimStep.gameSeconds)
        func luckyDays(disturb: Bool) -> [Int] {
            var w = rig.factory.newWorld(seed: 5)
            var days: [Int] = []
            for _ in 0..<6 {
                if disturb { w.rng.use(.production) { _ = $0.next() } }
                let r = light.runSteps(day, &w)
                if firedIDs(r.events).contains("event.test.lucky") { days.append(w.clock.day) }
            }
            return days
        }
        XCTAssertEqual(luckyDays(disturb: false), luckyDays(disturb: true))
    }

    // MARK: - 日数を使わない引き金

    /// 追跡カウンタ(近くにいた時間)→ 出来事 → 予約 → 前の出来事からの時間、の連鎖が日数なしで起きる。
    func testTrackerScheduleAndSinceFiredWithoutDays() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        let r = rig.simulation.runSteps(Int(6 * 3600 / SimStep.gameSeconds), &w)
        XCTAssertEqual(r.warnings, [])
        // 試験の仲間 A はノアのそばにいる(半径 3)。30 分で counter.test.near が 30 に届き、次の毎時で起きる
        XCTAssertGreaterThanOrEqual(w.narrative.counters["counter.test.near"] ?? 0, 30)
        let near = try XCTUnwrap(w.narrative.fired["event.test.near"])
        XCTAssertEqual(near.lastAt, GameTime(seconds: 3600))
        XCTAssertTrue(w.knowledge.knows("fact.test.near_known"))
        // 予約(120 分後)が起き、来歴の inputs が予約した出来事を指す
        let follow = try XCTUnwrap(w.narrative.fired["event.test.followup"])
        XCTAssertEqual(follow.lastAt, GameTime(seconds: 3600 + 7200))
        let followRec = try XCTUnwrap(w.ledger.record(try XCTUnwrap(follow.lastRecord)))
        XCTAssertTrue(followRec.inputs.contains(try XCTUnwrap(near.lastRecord)))
        // 前の出来事から 3 時間
        XCTAssertEqual(w.narrative.fired["event.test.after_near"]?.lastAt, GameTime(seconds: 4 * 3600))
        // クールダウン 4 時間: 1・5 時に起きる
        XCTAssertEqual(w.narrative.counters["counter.test.tick"], 2)
        // 公開のコンテンツの出来事は日数で引かない
        let issues = ContentValidator.validate(rig.content)
        XCTAssertEqual(issues.filter { $0.level == .error }, [])
        XCTAssertFalse(issues.contains { $0.rule == "event.no-day-trigger" })
    }

    /// 「工業の初めて」: 初めて炉を置いたときだけ起きる(2 つ目では起きない)。来歴の数も追跡カウンタで数える。
    func testFirstIndustrialActTriggers() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let c = spawn(ctx.world)
        place(&ctx, module: "furnace", at: WorldPoint(c.layer, c.point.moved(.east, by: 2)))
        XCTAssertEqual(settle(rig, &ctx).warnings, [])
        place(&ctx, module: "furnace", at: WorldPoint(c.layer, c.point.moved(.west, by: 8)))
        _ = settle(rig, &ctx)
        XCTAssertEqual(ctx.world.narrative.fired["event.test.first_furnace"]?.count, 1)
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.first_furnace"], 1)
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.furnaces"], 2)
    }

    /// 建った物を指す placement は、同じ種類の古い物ではなく、その hook を起こした物を中心にする。
    func testBuiltHookUsesCurrentPlacement() throws {
        let rig = try TestRig.publicOnly()
        let event = try JSONDecoder().decode(EventDef.self, from: Data(#"""
        {
          "id": "event.test.current_placement",
          "trigger": {
            "on": ["built"],
            "when": {
              "nearPlacement": {
                "place": { "placement": { "module": null, "structure": null } },
                "module": "furnace", "structure": null, "radius": 1
              }
            }
          },
          "effects": [{ "counter": { "id": "counter.test.current_placement", "add": 1 } }]
        }
        """#.utf8))
        var content = rig.content
        content.events[event.id] = event
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: content)
        let center = spawn(ctx.world)
        place(&ctx, module: "furnace", at: center)
        _ = settle(rig, &ctx)
        place(&ctx, structure: "structure.storage", at: WorldPoint(center.layer, center.point.moved(.east, by: 6)))
        _ = settle(rig, &ctx)
        XCTAssertNil(ctx.world.narrative.counters["counter.test.current_placement"])

        place(&ctx, structure: "structure.shelter", at: WorldPoint(center.layer, center.point.moved(.east, by: 1)))
        XCTAssertEqual(settle(rig, &ctx).warnings, [])
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.current_placement"], 1)
    }

    /// 優先度: 同じ hook で成り立つ出来事は優先度の大きい順に起きる。
    func testPriorityOrder() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        ctx.learn("fact.test.prio")
        let r = settle(rig, &ctx)
        XCTAssertEqual(firedIDs(r.events).filter { $0.rawValue.hasPrefix("event.test.prio") },
                       ["event.test.prio_high", "event.test.prio_low"])
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.prio"], 1)
    }

    // MARK: - 範囲の効果(REQ-S10)

    /// 置いた物を中心にした範囲: 中の仲間は配属に従わず中心へ歩く(ノアは除く)。範囲を出る・縮む・期限で消えると戻る。
    func testAuraOverridesAssignmentAndReleases() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        let c = spawn(w)
        let furnaceAt = WorldPoint(c.layer, c.point.moved(.east, by: 2))
        let furnace = place(&ctx, module: "furnace", at: furnaceAt)
        _ = settle(rig, &ctx)
        w = ctx.world
        let aura = try XCTUnwrap(w.auras.active.values.first { $0.kind == "aura.test.pull" })
        XCTAssertEqual(aura.source, .placement(furnace), "引き金の置いた物が中心")
        XCTAssertEqual(aura.radius, 4, "半径は AuraDef.radius")
        XCTAssertEqual(w.narrative.lineLog.last?.line, "line.test.work_a", "添え物の一言")

        _ = rig.simulation.runSteps(1, &w)
        let oa = try XCTUnwrap(w.people["person.test_a"]?.override)
        XCTAssertEqual(oa.aura, aura.id)
        XCTAssertEqual(oa.assignment, .guardArea(center: furnaceAt, radius: 1))
        XCTAssertNil(w.people[.noah]?.override, "ノアには名指ししない限り効かない")
        XCTAssertEqual(w.people["person.test_a"]?.assignment, .idle, "プレイヤーの配属そのものは消さない")

        // 範囲を出ると戻る
        w.people["person.test_b"]?.position = WorldPoint(c.layer, c.point.moved(.east, by: 9))
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertNil(w.people["person.test_b"]?.override)

        // 半径を半分に(範囲が目に見えて縮む)→ 距離 3 の仲間は外れる
        w.people["person.test_a"]?.position = WorldPoint(c.layer, furnaceAt.point.moved(.north, by: 3))
        var ctx2 = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.scaleAura(kind: "aura.test.pull", permille: 500, radiusPermille: 500)], &ctx2, cause: nil)
        w = ctx2.world
        XCTAssertEqual(w.auras.active[aura.id]?.radius, 2)
        XCTAssertEqual(w.auras.active[aura.id]?.strength, 500)
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertNil(w.people["person.test_a"]?.override)

        // 期限(6 時間)で範囲が消え、中にいた仲間も戻る
        w.people["person.test_a"]?.position = furnaceAt
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertNotNil(w.people["person.test_a"]?.override)
        _ = rig.simulation.runSteps(Int(6 * 3600 / SimStep.gameSeconds), &w)
        XCTAssertNil(w.auras.active[aura.id])
        XCTAssertNil(w.people["person.test_a"]?.override)
        // 上書きは来歴に残る(「体が勝手に動いた」を後で指せる)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .overridden && $0.subject == .person("person.test_a") })
    }

    /// 人を中心にした範囲は、その人について行く(中心の人自身には効かない)。
    func testAuraCenteredOnPersonMakesOthersFollow() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        EffectApplier.apply([.addAura(kind: "aura.test.pull", at: .person(id: "person.test_b"), radius: nil, hours: nil)],
                            &ctx, cause: nil)
        var w = ctx.world
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertEqual(w.people["person.test_a"]?.override?.assignment, .follow(person: "person.test_b"))
        XCTAssertNil(w.people["person.test_b"]?.override)
        var ctx2 = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.removeAura(kind: "aura.test.pull")], &ctx2, cause: nil)
        w = ctx2.world
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertNil(w.people["person.test_a"]?.override)
    }

    /// 定義から付く範囲(建造物の auras)と、各システムが読む値。種類ごとの半分化はこれから付く範囲にも効く。
    func testAuraFromDefinitionAndModifiers() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        let c = spawn(w)
        let at = WorldPoint(c.layer, c.point.moved(.south, by: 5))
        let beacon = place(&ctx, structure: "structure.test.beacon", at: at)
        _ = settle(rig, &ctx)
        w = ctx.world
        _ = rig.simulation.runSteps(1, &w)
        let a = try XCTUnwrap(w.auras.active.values.first { $0.kind == "aura.test.ward" })
        XCTAssertEqual(a.source, .placement(beacon))
        XCTAssertEqual(a.fromDefinition, true)
        let inside = WorldPoint(c.layer, at.point.moved(.east, by: 2))
        let outside = WorldPoint(c.layer, at.point.moved(.east, by: 3))
        XCTAssertEqual(Auras.workSpeedPermille(at: inside, in: w, content: rig.content), 1500)
        XCTAssertTrue(Auras.repelsEnemies(at: inside, in: w, content: rig.content))
        XCTAssertEqual(Auras.bodyPerHour(at: inside, stat: "mind", in: w, content: rig.content), 4)
        XCTAssertEqual(Auras.workSpeedPermille(at: outside, in: w, content: rig.content), 1000)
        XCTAssertFalse(Auras.repelsEnemies(at: outside, in: w, content: rig.content))

        // 半分にする(今ある範囲)
        var ctx2 = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.scaleAura(kind: "aura.test.ward", permille: 500, radiusPermille: 500)], &ctx2, cause: nil)
        w = ctx2.world
        XCTAssertEqual(Auras.workSpeedPermille(at: at, in: w, content: rig.content), 1250)
        XCTAssertEqual(Auras.bodyPerHour(at: at, stat: "mind", in: w, content: rig.content), 2)
        XCTAssertFalse(Auras.repelsEnemies(at: inside, in: w, content: rig.content), "半径 2 → 1")

        // 置いた物を片付けると範囲も消え、もう一度置くと半分のまま付く
        w.placements.items[beacon] = nil
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertFalse(w.auras.active.values.contains { $0.kind == "aura.test.ward" })
        var ctx3 = StepContext(world: w, content: rig.content)
        place(&ctx3, structure: "structure.test.beacon", at: at)
        w = ctx3.world
        _ = rig.simulation.runSteps(1, &w)
        let b = try XCTUnwrap(w.auras.active.values.first { $0.kind == "aura.test.ward" })
        XCTAssertEqual(b.radius, 1)
        XCTAssertEqual(b.strength, 500)
    }

    // MARK: - 追跡カウンタ

    /// 条件が成り立っていた夜の数(夜明けに数える)と、拠点から最も遠くまで行った距離。
    func testNightAndDistanceTrackers() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let c = spawn(ctx.world)
        ctx.emit(.dawn(day: 2))
        _ = settle(rig, &ctx)
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.nights_lit"] ?? 0, 0)
        place(&ctx, structure: "structure.test.beacon", at: WorldPoint(c.layer, c.point.moved(.south, by: 2)))
        ctx.emit(.dawn(day: 3))
        ctx.emit(.dawn(day: 4))
        _ = settle(rig, &ctx)
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.nights_lit"], 2)

        var w = ctx.world
        w.people[.noah]?.position = WorldPoint(c.layer, c.point.moved(.east, by: 7))
        _ = rig.simulation.runSteps(1, &w)
        w.people[.noah]?.position = c
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertEqual(w.narrative.counters["counter.test.far"], 7, "戻っても最も遠い距離は残る")
    }

    // MARK: - 効果は世界を変える

    /// どの効果も世界を変えるか、持ち主のシステムへのコマンドになる(未実装として捨てられる効果は無い)。
    func testEveryEffectChangesTheWorldOrBecomesACommand() throws {
        let rig = try TestRig.publicOnly()
        let base = rig.factory.newWorld(seed: 1)
        let c = base.people[.noah]!.position!
        let effects: [Effect] = [
            .learn(fact: "fact.test.revealed"),
            .give(item: "wood", matter: nil, quantity: 2, unique: nil),
            .give(item: "wood", matter: nil, quantity: 1, unique: true),
            .take(what: Ingredient(item: "wood", quantity: 1)),
            .counter(id: "counter.x", add: 2),
            .setCounter(id: "counter.x", value: 5),
            .stat(id: "stat.test.hidden", add: 10),
            .setStat(id: "stat.test.hidden", value: 7),
            .relation(person: "person.test_a", add: 3),
            .ideology(person: "person.test_a", axis: "axis.test.make", add: 1),
            .remember(person: "person.test_a", memory: "memory.test.saw", persists: true),
            .meet(person: "person.test_c", at: .base),
            .join(person: "person.test_c"),
            .leave(person: "person.test_b"),
            .die(person: "person.test_b", cause: "text.test.cause"),
            .injure(person: "person.test_a", amount: 5000),
            .overrideAssignment(person: "person.test_a", toward: .base, hours: 2),
            .clearOverride(person: "person.test_a"),
            .selfBuild(person: "person.test_a", structure: "structure.shelter", near: .base, radius: nil),
            .say(context: "work", speaker: nil),
            .groupRelation(id: "group.test", add: -3),
            .groupFlag(id: "group.test", flag: "flag.test", on: true),
            .addAura(kind: "aura.test.pull", at: .point(at: c), radius: 3, hours: 1),
            .scaleAura(kind: "aura.test.smoke", permille: 500),
            .removeAura(kind: "aura.test.smoke"),
            .revealMap(around: .base, radius: 5),
            .setTerrain(at: .point(at: c), terrain: "rock"),
            .spawnEnemy(kind: "enemy.test", count: 2, near: .base),
            .startBattle(enemy: "enemy.test", count: 1, near: .base),
            .convertPlacements(from: "furnace", to: "furnace.test.other"),
            .tagRecords(query: ProvenanceQuery(act: .placed), tag: "tag.test.later"),
            .unlock(target: .structure(id: "structure.test.beacon")),
            .startScene(scene: "scene.test.one"),
            .schedule(event: "event.test.followup", afterMinutes: 30),
            .unschedule(event: "event.test.followup"),
            .fire(event: "event.test.followup"),
            .objective(id: "objective.test.first", status: .done),
            .chapter(id: "chapter.test.two"),
            .ending(id: "ending.test.end"),
        ]
        var covered: Set<String> = []
        for e in effects {
            var ctx = StepContext(world: base, content: rig.content)
            // 前提: 置いた物 1 つ・弱めたり消したりする範囲 1 つ・予約 1 つ・上書き 1 つ
            place(&ctx, module: "furnace", at: c)
            EffectApplier.apply([.addAura(kind: "aura.test.smoke", at: .base, radius: 2, hours: nil),
                                 .schedule(event: "event.test.followup", afterMinutes: 30),
                                 .overrideAssignment(person: "person.test_a", toward: nil, hours: nil)], &ctx, cause: nil)
            _ = ctx.drainEvents()
            let before = ctx.world
            let cause = ctx.record(.chose, .event("event.test.chain"))
            EffectApplier.apply([e], &ctx, cause: cause)
            XCTAssertEqual(ctx.warnings, [], "\(e)")
            var changed = ctx.world
            changed.ledger = before.ledger  // 来歴が増えただけの効果は「変えた」に数えない(印の付け替えは数える)
            let retagged = before.ledger.records.map(\.tags) != ctx.world.ledger.records.prefix(before.ledger.records.count).map(\.tags)
            XCTAssertTrue(changed != before || retagged || !ctx.followUps.isEmpty, "世界を変えない効果: \(e)")
            if let label = Mirror(reflecting: e).children.first?.label { covered.insert(label) }
        }
        XCTAssertEqual(covered.count, 38, "Effect の case を setPart 以外全部ためす(case を足したらここにも足す)")

        // setPart は POI が要る。平らな地図には POI が無いので、対象が無いことが警告で見える(黙って捨てない)。
        // POI を置いた世界での確かめは、地図の担当の型(MapPlacement)が境界に入ってから足す。
        var ctx = StepContext(world: base, content: rig.content)
        EffectApplier.apply([.setPart(poiKind: "poi.test.wreck", part: "part.a", state: .dismantled)], &ctx, cause: nil)
        XCTAssertTrue(ctx.followUps.isEmpty)
        XCTAssertEqual(ctx.warnings.count, 1)
    }

    /// 他のシステムの切れ端を変える効果は、引き金の来歴を持ったコマンドになる。持ち主が処理すれば世界が変わり、
    /// 処理するシステムが無ければ警告で見える(黙って捨てない)。
    func testCrossSystemEffectsAreCommandsWithCause() throws {
        let rig = try TestRig.publicOnly()
        let w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        let cause = ctx.record(.chose, .event("event.test.chain"))
        EffectApplier.apply([.join(person: "person.test_c"), .setTerrain(at: .base, terrain: "rock")], &ctx, cause: cause)
        let center = try XCTUnwrap(Places.resolve(.base, world: w, trigger: nil))
        XCTAssertEqual(ctx.followUps, [.crew(.joinFromEffect(person: "person.test_c", cause: cause)),
                                       .exploration(.setTerrain(at: center, terrain: "rock", cause: cause))])

        // 持ち主の代わりの試験用システム
        struct StubCrew: SimSystem {
            let name = "stub.crew"
            func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
                guard case .crew(.joinFromEffect(let p, let cause)) = command else { return .notMine }
                let rec = ctx.record(.joined, .person(p), inputs: cause.map { [$0] } ?? [])
                ctx.world.people[p]?.presence = .member(since: ctx.world.clock.now)
                ctx.emit(.personJoined(person: p, record: rec))
                return .done
            }
        }
        let sim = Simulation(content: rig.content, systems: [StubCrew(), NarrativeSystem()])
        var ctx2 = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.join(person: "person.test_c")], &ctx2, cause: nil)
        var r = StepReport()
        sim.settle(&ctx2, &r)
        XCTAssertEqual(r.warnings, [])
        XCTAssertTrue(ctx2.world.people["person.test_c"]?.presence.isMember == true)

        // 受け手(持ち主のシステム)がいなければ警告で見える。どの担当が処理を入れたかに左右されないよう、
        // 出来事のシステムだけの本体で確かめる(持ち主の処理の確かめは各担当のテスト)。
        let narrativeOnly = Simulation(content: rig.content, systems: [NarrativeSystem()])
        var ctx3 = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.setTerrain(at: .base, terrain: "rock")], &ctx3, cause: nil)
        var r3 = StepReport()
        narrativeOnly.settle(&ctx3, &r3)
        XCTAssertTrue(r3.warnings.contains { $0.contains("setTerrain") })
    }

    /// 効果 fire は選択肢から別の筋へ進むときに使う(trigger.when を見ず、一度きりなら二度は起きない)。
    func testFireEffectRunsEventImmediately() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        EffectApplier.apply([.fire(event: "event.test.followup"), .fire(event: "event.test.followup")], &ctx, cause: nil)
        XCTAssertEqual(settle(rig, &ctx).warnings, [])
        XCTAssertEqual(ctx.world.narrative.fired["event.test.followup"]?.count, 1)
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.followup"], 1)
    }

    // MARK: - 目標・章・結末・場面

    func testObjectiveChapterAndEnding() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        EffectApplier.apply([.objective(id: "objective.test.beacon", status: .active)], &ctx, cause: nil)
        place(&ctx, structure: "structure.test.beacon", at: spawn(ctx.world))
        _ = settle(rig, &ctx)
        XCTAssertEqual(ctx.world.narrative.objectives["objective.test.beacon"], .done)
        XCTAssertEqual(ctx.world.narrative.chapter, "chapter.test.two", "目標の達成の効果で章が進む")

        EffectApplier.apply([.setCounter(id: "counter.test.end", value: 1)], &ctx, cause: nil)
        ctx.emit(.unlocked(what: "x"))
        let r = settle(rig, &ctx)
        XCTAssertEqual(ctx.world.narrative.ending, "ending.test.end")
        XCTAssertEqual(ctx.world.run.outcome, .ended("ending.test.end"))
        XCTAssertEqual(ctx.world.narrative.counters["counter.test.ended"], 1)
        XCTAssertTrue(r.events.contains(.endingReached(ending: "ending.test.end")))
        XCTAssertEqual(ctx.world.ledger.records.filter { $0.act == .achieved }.count, 2, "目標の達成と結末の記録")
    }

    /// 場面は押さなくても時間で次の行へ流れ、最後の行の次で終わる(地図は止めない)。
    func testSceneFlowsByTime() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        EffectApplier.apply([.startScene(scene: "scene.test.one")], &ctx, cause: nil)
        var w = ctx.world
        XCTAssertEqual(w.narrative.scene?.line, 0)
        let perLine = Int(NarrativeSystem.sceneLineSeconds / SimStep.gameSeconds)
        _ = rig.simulation.runSteps(perLine, &w)
        XCTAssertEqual(w.narrative.scene?.line, 1)
        _ = rig.simulation.runSteps(perLine, &w)
        XCTAssertNil(w.narrative.scene)
    }

    // MARK: - 仲間の一言

    /// 文脈と条件で絞り、重みで物語の乱数から選ぶ。会っていない人は言わない。直近に言った一言は重ねない。
    func testLineSelection() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 4), content: rig.content)
        XCTAssertEqual(Lines.candidates(context: "work", speaker: nil, world: ctx.world, content: rig.content).map(\.id),
                       ["line.test.work_a"], "条件(fact.test.alpha)が無い・試験の人 C はまだ会っていない")
        ctx.learn("fact.test.alpha")
        XCTAssertEqual(Lines.candidates(context: "work", speaker: nil, world: ctx.world, content: rig.content).map(\.id),
                       ["line.test.work_a", "line.test.work_b"])
        let first = try XCTUnwrap(Lines.say(context: "work", speaker: nil, &ctx))
        let second = try XCTUnwrap(Lines.say(context: "work", speaker: nil, &ctx))
        XCTAssertNotEqual(first, second, "直近の一言は重ねない")
        XCTAssertNil(Lines.say(context: "work", speaker: nil, &ctx), "どちらも直近に言った")
        XCTAssertTrue(ctx.drainEvents().contains(.lineSpoken(person: "person.test_a", line: "line.test.work_a")))
        XCTAssertNil(Lines.say(context: "campfire.none", speaker: nil, &ctx))

        // 同じ seed なら同じ一言
        func pickFirst(_ seed: UInt64) -> LineID? {
            var c = StepContext(world: rig.factory.newWorld(seed: seed), content: rig.content)
            c.learn("fact.test.alpha")
            return Lines.pick(context: "work", speaker: nil, &c)?.id
        }
        XCTAssertEqual(pickFirst(9), pickFirst(9))
        XCTAssertEqual(Set((1...20).map { pickFirst(UInt64($0)) }).count, 2, "重み 1:3 で両方が出る")
    }

    // MARK: - 条件の種類(原作の Events の条件を全部表せるか)

    /// 原作の引き金の種類を、日数を使わずに表せる(在庫と人数の比・得意分野と配属・体の数値・POI の進み・
    /// 見つけた数・前の出来事からの時間・探索の届いた範囲・確率)。
    func testOriginalTriggerKindsAreExpressible() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let json = #"""
        [
          {"stock": {"of": {"item": "wood", "quantity": 2}, "cmp": "lt", "perMember": true}},
          {"stock": {"of": {"item": "food", "quantity": 0}, "cmp": "eq"}},
          {"someone": {"where": [{"specialty": {"tag": "smith"}}, {"member": {}}]}},
          {"someone": {"where": [{"body": {"stat": "health", "cmp": "lt", "value": 30000}}]}},
          {"poi": {"kind": "poi.test.wreck", "test": {"visitsAtLeast": {"count": 7}}}},
          {"discoveredPOI": {"kind": "poi.test.wreck"}},
          {"discoveredPOI": {"kind": "poi.test.wreck", "atLeast": 3}},
          {"sinceFired": {"event": "event.test.chain", "hours": 72}},
          {"counter": {"id": "counter.test.far", "cmp": "ge", "value": 11}},
          {"all": {"of": [{"ledger": {"query": {"act": "defeated"}, "atLeast": 10}}, {"chance": {"basisPoints": 1500}}]}},
          {"trigger": {"query": {"act": "crafted", "item": "wood"}}},
          {"groupFlag": {"id": "group.test", "flag": "flag.test"}},
          {"person": {"id": "person.test_a", "test": {"near": {"person": "person.noah", "radius": 3}}}}
        ]
        """#
        let cs = try JSONDecoder().decode([Condition].self, from: Data(json.utf8))
        XCTAssertEqual(cs[5], .discoveredPOI(kind: "poi.test.wreck"), "省略可能なラベルは書かなくてよい")
        let holds = { (c: Condition, w: WorldState) in ConditionEvaluator.evaluatePure(c, world: w, content: rig.content) }
        XCTAssertEqual(holds(cs[0], ctx.world), true, "薪 3 < 一員 3 人 × 2")
        XCTAssertEqual(holds(cs[1], ctx.world), true)
        XCTAssertEqual(holds(cs[2], ctx.world), true)
        XCTAssertEqual(holds(cs[3], ctx.world), false)
        ctx.world.people["person.test_b"]?.body.health = Milli(20)
        XCTAssertEqual(holds(cs[3], ctx.world), true)
        XCTAssertEqual(holds(cs[9], ctx.world), false, "確率の前の条件で決まる")
        XCTAssertEqual(holds(cs[12], ctx.world), true)
        let crafted = ctx.record(.crafted, .item("wood"))
        XCTAssertEqual(ConditionEvaluator.evaluatePure(cs[10], world: ctx.world, content: rig.content, trigger: crafted), true)
        XCTAssertEqual(holds(cs[7], ctx.world), false, "起きていない出来事からの時間は成り立たない")
    }

    /// 巻き戻しで run の番号が進んでも、今の来歴に残る夜明け前の記録は条件から見える(巻き戻しは引き金を変えない)。
    func testLedgerConditionIgnoresRunIndex() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let rec = ctx.record(.placed, .module("furnace", nil))
        ctx.world.run.index += 1
        let q = ProvenanceQuery(act: .placed, module: "furnace")
        XCTAssertEqual(ConditionEvaluator.evaluatePure(.ledger(query: q, atLeast: 1), world: ctx.world, content: rig.content), true)
        XCTAssertEqual(ConditionEvaluator.evaluatePure(.firstTime(query: q), world: ctx.world, content: rig.content, trigger: rec), true)
    }

    // MARK: - 検証

    func testValidatorNarrativeRules() throws {
        var db = try TestContent.publicOnly()
        let json = #"""
        {"scenes": [{"id": "scene.test.long", "lines": [{"text": "text.test.line1"}, {"text": "text.test.line1"},
                                                        {"text": "text.test.line1"}, {"text": "text.test.line1"}]}],
         "events": [{"id": "event.test.bad", "trigger": {"on": ["fact"], "when": {"eventFired": {"id": "event.nope"}}},
                     "effects": [{"addAura": {"kind": "aura.nope", "at": {"base": {}}}}]},
                    {"id": "event.test.sceneonly", "trigger": {"when": {"always": {}}}, "effects": [], "scene": "scene.test.one"}]}
        """#
        try ContentLoader.apply(json: Data(json.utf8), to: &db)
        let issues = ContentValidator.validate(db)
        XCTAssertTrue(issues.contains { $0.rule == "scene.max-lines" && $0.message.contains("scene.test.long") })
        XCTAssertTrue(issues.contains { $0.rule == "narrative.ref" && $0.message.contains("event.nope") })
        XCTAssertTrue(issues.contains { $0.rule == "narrative.ref" && $0.message.contains("aura.nope") })
        XCTAssertTrue(issues.contains { $0.rule == "event.changes-world" && $0.message.contains("event.test.sceneonly") },
                      "場面だけの出来事は警告")
    }
}
