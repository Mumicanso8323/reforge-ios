import RFCrew
import RFContent
import RFKernel
import Foundation
import RFMap
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U5 人(ノアと仲間)の受け入れテスト(docs/architecture/F-work-units.md の U5 行)。
/// 公開の試験用コンテンツ(32×32 の平らな草地、ノア + test_a(専門 smith・思想 make 3)+ test_b(study・guard 2))。
final class CrewSystemTests: XCTestCase {
    // MARK: - 道具

    private func world(_ rig: TestRig, seed: UInt64 = 1) -> WorldState { rig.factory.newWorld(seed: seed) }

    private func spawn(_ w: WorldState) -> WorldPoint { w.people[.noah]!.position! }

    /// 始まりの位置(地図の spawn)からの相対の位置。
    private func at(_ w: WorldState, _ dx: Int, _ dy: Int) -> WorldPoint {
        let s = w.map.spawn
        return WorldPoint(s.layer, GridPoint(s.point.x + dx, s.point.y + dy))
    }

    private func apply(_ rig: TestRig, _ w: inout WorldState, _ c: CrewCommand) -> StepReport {
        rig.simulation.apply(.crew(c), to: &w)
    }

    @discardableResult
    private func place(_ w: inout WorldState, module: ModuleKindID? = nil, structure: StructureKindID? = nil,
                       at p: WorldPoint, status: PlacementStatus = .running) -> EntityID {
        let id = w.newEntityID()
        let kind: PlaceableKind = module.map { .module($0) } ?? .structure(structure!)
        w.placements.items[id] = Placement(id: id, kind: kind, at: p, facing: .north, origin: ProvenanceLedger.unknownOrigin,
                                           status: status)
        return id
    }

    private func water(_ w: inout WorldState, _ points: [GridPoint]) {
        for p in points { w.map[.surface]?.setTerrain("water", at: p) }
    }

    /// 歩き終えるまで進める(上限つき)。
    @discardableResult
    private func walkUntilStopped(_ rig: TestRig, _ w: inout WorldState, _ id: PersonID = .noah, limit: Int = 400,
                                  trace: ((WorldState) -> Void)? = nil) -> StepReport {
        var r = StepReport()
        for _ in 0..<limit {
            guard w.people[id]?.motion != nil else { break }
            r.merge(rig.simulation.runSteps(1, &w))
            trace?(w)
        }
        return r
    }

    // MARK: - 歩く(1 秒 4 マス・経路どおり・行き先の変更)

    /// 1 実秒 4 マス(原作 MapScreen.cs:71)。昼の実時間で 3 秒 = 12 マス。刻みによらない。
    func testWalksFourTilesPerRealSecond() throws {
        let rig = try TestRig.publicOnly()
        XCTAssertEqual(CrewRules.progressPerStep(rig.content.clock), 375, "既定の時計で 1 ステップ 0.375 マス")
        for dt in [1.0 / 60, 0.37, 1.0] {
            var w = world(rig)
            let start = spawn(w)
            XCTAssertNil(apply(rig, &w, .walk(to: at(w, 14, 0))).rejection)
            var t = 0.0
            while t < 3.0 - 1e-9 {
                let d = min(dt, 3.0 - t)
                _ = rig.simulation.advance(&w, realSeconds: d)
                t += d
            }
            XCTAssertEqual(w.people[.noah]!.position!.point.x - start.point.x, 12, "刻み \(dt) 秒")
        }
    }

    /// 経路どおり(通れないマスを通らず、1 マスずつ隣へ)に歩き、着いたら arrived を出して止まる。
    func testWalksAlongPathAroundWater() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let s = spawn(w).point
        // ノアの右に縦の水の壁(下に 1 マスの切れ目)
        water(&w, (-6...5).map { GridPoint(s.x + 3, s.y + $0) })
        // 水を見ておく(既知の水を避ける経路にする)
        _ = rig.simulation.runSteps(1, &w)
        let goal = at(w, 6, 0)
        XCTAssertNil(apply(rig, &w, .walk(to: goal)).rejection)
        var prev = s
        var visited: [GridPoint] = []
        let r = walkUntilStopped(rig, &w) { w in
            let p = w.people[.noah]!.position!.point
            if p != prev {
                XCTAssertLessThanOrEqual(p.chebyshev(to: prev), 1, "飛ばない")
                visited.append(p)
                prev = p
            }
        }
        XCTAssertEqual(w.people[.noah]!.position, goal)
        XCTAssertTrue(visited.allSatisfy { w.map[.surface]!.terrain(at: $0) != "water" }, "水を通らない")
        XCTAssertTrue(visited.contains { $0.y >= s.y + 6 }, "切れ目を回る")
        XCTAssertTrue(r.events.contains(.arrived(person: .noah, at: goal)))
        XCTAssertEqual(w.people[.noah]!.activity, .idle)
    }

    /// 歩いている途中に別の行き先を送ると、いまの次のマスを経て新しい行き先へ向かう(戻らない・飛ばない)。
    func testChangesDestinationWhileWalking() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        XCTAssertNil(apply(rig, &w, .walk(to: at(w, 8, 0))).rejection)
        _ = rig.simulation.runSteps(5, &w)  // 1.875 マス
        let mid = w.people[.noah]!
        XCTAssertEqual(mid.position, at(w, 1, 0))
        XCTAssertGreaterThan(mid.motion!.progress, 0)
        let next = mid.motion!.path.first!
        let goal = at(w, 1, -6)
        XCTAssertNil(apply(rig, &w, .walk(to: goal)).rejection)
        XCTAssertEqual(w.people[.noah]!.motion!.path.first, next, "途中のマスへは進み続ける")
        XCTAssertEqual(w.people[.noah]!.motion!.progress, mid.motion!.progress, "進みを保つ")
        walkUntilStopped(rig, &w)
        XCTAssertEqual(w.people[.noah]!.position, goal)
    }

    /// 通れないマス(水)をタップすると、その隣まで歩く。地図の外・届かない所は断る(足元カードの 1 行)。
    func testWalkToBlockedTileStopsNextToIt() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let target = at(w, 4, 0).point
        water(&w, [target])
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertNil(apply(rig, &w, .walk(to: WorldPoint(.surface, target))).rejection)
        walkUntilStopped(rig, &w)
        XCTAssertEqual(w.people[.noah]!.position!.point.chebyshev(to: target), 1)
        XCTAssertEqual(apply(rig, &w, .walk(to: WorldPoint(.surface, GridPoint(99, 99)))).rejection?.reason,
                       "reason.walk.unreachable")
    }

    /// 霧の先も楽観的な経路で歩き、霧が晴れて水が見えたら引き直す(水には入らない)。
    func testFogOptimisticRouteIsReplannedWhenRevealed() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let s = spawn(w).point
        // 視界(8)の外に横長の水の壁。切れ目は左端
        water(&w, (-12...13).map { GridPoint(s.x + $0, s.y - 11) })
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertFalse(w.knowledge.mapKnown[.surface]![GridPoint(s.x, s.y - 11)], "壁はまだ霧の中")
        let goal = WorldPoint(.surface, GridPoint(s.x, s.y - 14))
        XCTAssertNil(apply(rig, &w, .walk(to: goal)).rejection)
        XCTAssertEqual(w.people[.noah]!.motion!.throughFog, true)
        XCTAssertTrue(w.people[.noah]!.motion!.path.contains(GridPoint(s.x, s.y - 11)), "知らないので真っすぐ")
        var visited: [GridPoint] = []
        walkUntilStopped(rig, &w, limit: 2000) { visited.append($0.people[.noah]!.position!.point) }
        XCTAssertEqual(w.people[.noah]!.position, goal)
        XCTAssertFalse(visited.contains { w.map[.surface]!.terrain(at: $0) == "water" }, "見えた水には入らない")
    }

    // MARK: - 視界で地図の既知が増える

    func testVisionRevealsMapKnownAndShrinksAtNight() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        XCTAssertNil(w.knowledge.mapKnown[.surface])
        let r = rig.simulation.runSteps(1, &w)
        let known0 = w.knowledge.mapKnown[.surface]!.countSet
        XCTAssertEqual(known0, VisionRule.cells(center: spawn(w).point, radius: 8, in: GridSize(width: 32, height: 32)).count)
        XCTAssertTrue(r.events.contains(.tilesRevealed(layer: .surface, count: known0)))
        XCTAssertFalse(r.changes.dirtyTiles.isEmpty, "新しく知ったマスの区画を描き直す")
        _ = apply(rig, &w, .walk(to: at(w, 6, 0)))
        walkUntilStopped(rig, &w)
        XCTAssertGreaterThan(w.knowledge.mapKnown[.surface]!.countSet, known0, "歩くと既知が増える")

        // 夜は半径 5(昼 8 − 3)
        var n = world(rig)
        n.clock.phase = .nightWork
        _ = rig.simulation.runSteps(1, &n)
        XCTAssertEqual(n.knowledge.mapKnown[.surface]!.countSet,
                       VisionRule.cells(center: spawn(n).point, radius: 5, in: GridSize(width: 32, height: 32)).count)
    }

    // MARK: - 配属の実行(モジュールに付く・見張り)

    /// モジュールに付く: 隣まで歩いて working になり、専門一致 +30% の速さで働く。生産は workers(at:) で読む。
    func testOperateWalksToModuleAndWorksWithSpecialtyBonus() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let furnace = place(&w, module: "furnace", at: at(w, 6, 3))
        let r0 = apply(rig, &w, .assign(person: "person.test_a", assignment: .operate(placement: furnace)))
        XCTAssertNil(r0.rejection)
        XCTAssertTrue(r0.events.contains(.assigned(person: "person.test_a", assignment: .operate(placement: furnace))))
        let rec = try XCTUnwrap(w.ledger.records.last { $0.act == .assigned })
        XCTAssertEqual(rec.actor, .noah)
        XCTAssertTrue(rec.tags.contains("tag.assign.operate.furnace"))
        _ = rig.simulation.runSteps(60, &w)
        let a = w.people["person.test_a"]!
        XCTAssertEqual(a.activity, .working(at: furnace))
        XCTAssertEqual(a.position!.point.chebyshev(to: at(w, 6, 3).point), 1, "モジュールの隣に立つ")
        XCTAssertEqual(a.workSpeed, 1300, "専門 smith が炉の専門と一致 +30%")
        XCTAssertEqual(w.people.workers(at: furnace), ["person.test_a"])
        XCTAssertEqual(w.people.workSpeedPermille(at: furnace), 1300)
        // 専門の無い人は普通の速さ。関係ランク 3 以上で +10%
        _ = apply(rig, &w, .assign(person: "person.test_b", assignment: .operate(placement: furnace)))
        w.people["person.test_b"]?.relation.rank = 3
        _ = rig.simulation.runSteps(60, &w)
        XCTAssertEqual(w.people["person.test_b"]!.workSpeed, 1100)
        // 置いた物が消えたら配属は外れる
        w.placements.items[furnace] = nil
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertEqual(w.people["person.test_a"]!.assignment, .idle)
        XCTAssertEqual(w.people.workers(at: furnace), [])
    }

    /// 思想の向きが配属の速さに効く(配属の印 × 思想の重み)。
    func testIdeologyAlignmentChangesWorkSpeed() throws {
        var content = try TestContent.publicOnly()
        try ContentLoader.apply(json: Data(#"{"ideologyAxes": [{"id": "axis.test.make", "weights": {"tag.assign.operate.furnace": 2}}]}"#.utf8),
                                to: &content)
        let rig = TestRig(content: content)
        var w = world(rig)
        let furnace = place(&w, module: "furnace", at: at(w, 3, 0))
        _ = apply(rig, &w, .assign(person: "person.test_a", assignment: .operate(placement: furnace)))
        _ = rig.simulation.runSteps(30, &w)
        // 1000 + 専門 300 + 思想 (3 × 2) × 20 = 1420
        XCTAssertEqual(w.people["person.test_a"]!.workSpeed, 1420)
    }

    /// 見張り: 中心へ歩いて guarding になり、夜も立っている。戦闘はこれを guards で読む。
    func testGuardStandsAtPostDayAndNight() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let post = at(w, -5, 4)
        XCTAssertNil(apply(rig, &w, .assign(person: "person.test_b", assignment: .guardArea(center: post, radius: 3))).rejection)
        _ = rig.simulation.runSteps(60, &w)
        let b = w.people["person.test_b"]!
        XCTAssertLessThanOrEqual(b.position!.point.chebyshev(to: post.point), 1)
        XCTAssertEqual(b.activity, .guarding(center: post))
        XCTAssertEqual(w.people.guards, ["person.test_b"])
        w.clock.phase = .nightWork
        _ = rig.simulation.runSteps(40, &w)
        XCTAssertEqual(w.people["person.test_b"]!.activity, .guarding(center: post))
        XCTAssertEqual(w.people["person.test_a"]!.activity, .sleeping, "配属の無い人は夜は眠る")
    }

    /// 得意分野の振る舞い: 見張りにいる人は、敵がノアに近づくと、敵とノアの間に出る(BEAT-19)。
    func testGuardWithInterposeStepsBetweenThreatAndNoah() throws {
        var content = try TestContent.publicOnly()
        content.people["person.test_b"]?.behaviors = [.interpose(protect: nil, radius: 5)]
        let rig = TestRig(content: content)
        var w = world(rig)
        let post = at(w, 0, 3)
        _ = apply(rig, &w, .assign(person: "person.test_b", assignment: .guardArea(center: post, radius: 3)))
        _ = rig.simulation.runSteps(40, &w)
        XCTAssertEqual(w.people["person.test_b"]!.activity, .guarding(center: post))
        let threat = w.newEntityID()
        w.combat.threats[threat] = ThreatState(id: threat, kind: "enemy.test", position: at(w, 4, 0), count: 1,
                                               health: Milli(10), intent: "food")
        _ = rig.simulation.runSteps(40, &w)
        let b = w.people["person.test_b"]!
        XCTAssertEqual(b.activity, .interposing(threat: threat))
        XCTAssertEqual(b.position, at(w, 1, 0), "ノアから敵へ 1 マスの所")
        XCTAssertEqual(w.people.guards, ["person.test_b"])
        // 敵がいなくなれば持ち場へ戻る
        w.combat.threats[threat] = nil
        _ = rig.simulation.runSteps(40, &w)
        XCTAssertEqual(w.people["person.test_b"]!.activity, .guarding(center: post))
    }

    /// 運搬: 経路の両端を行き来し、端に着くたびに arrived を出す(積み下ろしは RFLogistics)。
    func testHaulGoesBackAndForth() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let a = place(&w, module: "furnace", at: at(w, -4, 0))
        let b = place(&w, module: "furnace", at: at(w, 5, 0))
        let route = w.newEntityID()
        w.logistics.routes[route] = HaulRoute(id: route, from: a, to: b)
        XCTAssertNil(apply(rig, &w, .assign(person: "person.test_a", assignment: .haul(route: route))).rejection)
        XCTAssertEqual(w.people.haulers(of: route), ["person.test_a"])
        var arrivals: [GridPoint] = []
        for _ in 0..<300 {
            let r = rig.simulation.runSteps(1, &w)
            for case .arrived(let p, let at) in r.events where p == "person.test_a" { arrivals.append(at.point) }
        }
        XCTAssertGreaterThanOrEqual(arrivals.count, 3)
        let nearA = arrivals.map { $0.chebyshev(to: at(w, -4, 0).point) == 1 }
        XCTAssertEqual(Array(nearA.prefix(3)), [true, false, true], "積む → 下ろす → 積む")
        XCTAssertEqual(w.people["person.test_a"]!.activity, .carrying(route: route))
    }

    // MARK: - 上書き(範囲の効果)

    /// 範囲の効果(drawTowardSource)の中の仲間は、配属に従わず中心へ歩く。範囲が消えれば配属に戻る。
    /// ノアは名指しされない限り影響されない。名指しされても連れて行かれず、足取りが重くなる(止めない。BEAT-22)。
    func testAuraOverrideDrawsCompanionsButNoahOnlySlows() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let furnace = place(&w, module: "furnace", at: at(w, 3, 3))
        _ = apply(rig, &w, .assign(person: "person.test_a", assignment: .operate(placement: furnace)))
        _ = rig.simulation.runSteps(30, &w)
        XCTAssertEqual(w.people["person.test_a"]!.activity, .working(at: furnace))
        let center = at(w, -4, -2)
        let aura = w.newEntityID()
        w.auras.active[aura] = Aura(id: aura, kind: "aura.test.pull", source: .point(center), radius: 8,
                                    origin: ProvenanceLedger.unknownOrigin)
        _ = rig.simulation.runSteps(60, &w)
        let a = w.people["person.test_a"]!
        XCTAssertNotNil(a.override)
        XCTAssertEqual(a.assignment, .operate(placement: furnace), "プレイヤーの配属は残る")
        XCTAssertLessThanOrEqual(a.position!.point.chebyshev(to: center.point), 1, "中心へ歩いた")
        XCTAssertNil(w.people[.noah]!.override, "ノアは名指しされない限り")
        // プレイヤーが配属し直しても、上書きの間は従わない
        _ = apply(rig, &w, .assign(person: "person.test_a", assignment: .guardArea(center: at(w, 5, 5), radius: 1)))
        _ = rig.simulation.runSteps(30, &w)
        XCTAssertLessThanOrEqual(w.people["person.test_a"]!.position!.point.chebyshev(to: center.point), 1)
        // 範囲が消えると配属に戻る
        w.auras.active[aura] = nil
        _ = rig.simulation.runSteps(80, &w)
        XCTAssertNil(w.people["person.test_a"]!.override)
        XCTAssertEqual(w.people["person.test_a"]!.activity, .guarding(center: at(w, 5, 5)))
    }

    func testNamedNoahWalksWithHeavySteps() throws {
        var content = try TestContent.publicOnly()
        content.auras["aura.test.pull"]?.affects = [.noah, "person.test_a"]
        let rig = TestRig(content: content)
        func tilesWalked(drawn: Bool) -> Int {
            var w = world(rig)
            if drawn {
                let aura = w.newEntityID()
                w.auras.active[aura] = Aura(id: aura, kind: "aura.test.pull", source: .point(at(w, -3, 0)), radius: 10,
                                            origin: ProvenanceLedger.unknownOrigin)
                _ = rig.simulation.runSteps(1, &w)
                XCTAssertNotNil(w.people[.noah]!.override)
            }
            let start = spawn(w).point
            XCTAssertNil(apply(rig, &w, .walk(to: at(w, 9, 0))).rejection, "名指しされてもタップで歩ける")
            _ = rig.simulation.runSteps(24, &w)
            return w.people[.noah]!.position!.point.x - start.x
        }
        XCTAssertEqual(tilesWalked(drawn: false), 9)
        let heavy = tilesWalked(drawn: true)
        XCTAssertGreaterThan(heavy, 0, "止めない")
        XCTAssertLessThan(heavy, 4, "重い足取り")
    }

    // MARK: - 賛否と関係

    /// 来歴の印 × 思想の重みで賛否が出て関係が動く(同じ印は 1 日 1 回)。
    func testOpinionFromTaggedDecisionMovesRelation() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        var ctx = StepContext(world: w, content: rig.content)
        let rec = ctx.record(.built, .structure("structure.test.shelter", nil), actor: .noah, tags: ["tag.test.build"])
        ctx.emit(.built(placement: EntityID(999), record: rec))
        var report = StepReport()
        rig.simulation.settle(&ctx, &report)
        w = ctx.world
        // test_a: make 3 × build 2 = +6 / test_b: guard 2 × build −1 = −2
        XCTAssertTrue(report.events.contains(.opinion(person: "person.test_a", about: rec, stance: 6)))
        XCTAssertTrue(report.events.contains(.opinion(person: "person.test_b", about: rec, stance: -2)))
        XCTAssertFalse(report.events.contains { if case .opinion(.noah, _, _) = $0 { true } else { false } })
        XCTAssertEqual(w.people["person.test_a"]!.relation.points, 6)
        XCTAssertEqual(w.people["person.test_b"]!.relation.points, 0, "0 より下がらない")
        // 同じ日にもう一度: 賛否は出るが関係は動かない
        ctx = StepContext(world: w, content: rig.content)
        let rec2 = ctx.record(.built, .structure("structure.test.shelter", nil), actor: .noah, tags: ["tag.test.build"])
        ctx.emit(.built(placement: EntityID(998), record: rec2))
        report = StepReport()
        rig.simulation.settle(&ctx, &report)
        XCTAssertTrue(report.events.contains(.opinion(person: "person.test_a", about: rec2, stance: 6)))
        XCTAssertEqual(ctx.world.people["person.test_a"]!.relation.points, 6)
    }

    /// 関係ランク: 次まで (ランク+1)×50(原作 Survivor.cs:47-62)。0〜10。
    func testRelationRankThresholds() {
        var r = RelationState()
        XCTAssertEqual(r.add(49), 0)
        XCTAssertEqual(r.add(1), 1)
        XCTAssertEqual([r.rank, r.points], [1, 0])
        XCTAssertEqual(r.add(100 + 150), 2)
        XCTAssertEqual([r.rank, r.points], [3, 0])
        r.add(100_000)
        XCTAssertEqual(r.rank, 10)
        r.add(-1_000_000)
        XCTAssertEqual([r.rank, r.points], [10, 0], "ランクは下がらない")
    }

    /// 効果 relation が点だけ足しても、次のステップでランクに直る。
    func testEffectRelationPointsAreNormalized() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        var ctx = StepContext(world: w, content: rig.content)
        EffectApplier.apply([.relation(person: "person.test_a", add: 60)], &ctx, cause: nil)
        w = ctx.world
        let r = rig.simulation.runSteps(1, &w)
        XCTAssertEqual(w.people["person.test_a"]!.relation.rank, 1)
        XCTAssertEqual(w.people["person.test_a"]!.relation.points, 10)
        XCTAssertTrue(r.events.contains(.relationChanged(person: "person.test_a", rank: 1, delta: 0)))
    }

    /// 焚き火で話す(夜作業): 1 時間かかり、1 晩に 1 回だけ関係が深まる。昼は話せない。
    func testCampfireTalk() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        XCTAssertEqual(apply(rig, &w, .talk(person: "person.test_a")).rejection?.reason, "reason.talk.not_night")
        w.clock.phase = .nightWork
        let t0 = w.clock.now
        let r = apply(rig, &w, .talk(person: "person.test_a"))
        XCTAssertNil(r.rejection)
        XCTAssertEqual(r.steps, Int(CrewRules.talkDuration.seconds / SimStep.gameSeconds))
        XCTAssertEqual(w.clock.now - t0, CrewRules.talkDuration)
        XCTAssertEqual(w.people["person.test_a"]!.relation.points, CrewRules.talkPoints)
        XCTAssertTrue(w.ledger.records.contains { $0.act == .talked && $0.subject == .person("person.test_a") })
        _ = apply(rig, &w, .talk(person: "person.test_a"))
        XCTAssertEqual(w.people["person.test_a"]!.relation.points, CrewRules.talkPoints, "同じ晩は 1 回だけ")
    }

    // MARK: - 合流・離脱・死

    func testMeetJoinLeaveDie() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        var r = rig.simulation.apply(.crew(.meetFromEffect(person: "person.test_c", at: at(w, 5, 5), cause: nil)), to: &w)
        XCTAssertTrue(r.events.contains { if case .personMet("person.test_c", _) = $0 { true } else { false } })
        XCTAssertEqual(w.people["person.test_c"]!.position, at(w, 5, 5))
        r = rig.simulation.apply(.crew(.joinFromEffect(person: "person.test_c", cause: nil)), to: &w)
        XCTAssertTrue(w.people["person.test_c"]!.presence.isMember)
        XCTAssertTrue(w.people.members.contains("person.test_c"))
        r = rig.simulation.apply(.crew(.injureFromEffect(person: "person.test_c", amount: 30_000, cause: nil)), to: &w)
        XCTAssertEqual(w.people["person.test_c"]!.body.health, Milli(70))
        r = rig.simulation.apply(.crew(.dieFromEffect(person: "person.test_c", reason: "cause.test", cause: nil)), to: &w)
        guard case .dead(_, let rec?) = w.people["person.test_c"]!.presence else { return XCTFail("死んだ") }
        XCTAssertEqual(w.ledger.record(rec)?.act, .died)
        XCTAssertNil(w.people["person.test_c"]!.position)
        // 死んだ人は戻らない
        r = rig.simulation.apply(.crew(.joinFromEffect(person: "person.test_c", cause: nil)), to: &w)
        XCTAssertFalse(w.people["person.test_c"]!.presence.isAlive)
        XCTAssertEqual(r.warnings.filter { !$0.contains("断られた") }, [])
    }

    func testInjuryToZeroKills() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        _ = rig.simulation.apply(.crew(.injureFromEffect(person: "person.test_a", amount: 200_000, cause: nil)), to: &w)
        XCTAssertFalse(w.people["person.test_a"]!.presence.isAlive)
    }

    /// スキルの習得(RFResearch の出来事)を人の切れ端に書く。
    func testSkillAcquiredIsWrittenToPerson() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: world(rig), content: rig.content)
        ctx.emit(.skillAcquired(person: "person.test_b", skill: "skill.test", record: ProvenanceLedger.unknownOrigin))
        var rep = StepReport()
        rig.simulation.settle(&ctx, &rep)
        XCTAssertTrue(ctx.world.people["person.test_b"]!.skills.contains("skill.test"))
    }

    // MARK: - 戦闘中は動かない

    func testFightingPersonDoesNotWalk() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        _ = apply(rig, &w, .walk(to: at(w, 8, 0)))
        let battle = w.newEntityID()
        w.combat.battles[battle] = BattleState(id: battle, participants: [.noah], enemies: [], origin: ProvenanceLedger.unknownOrigin)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.emit(.battleStarted(battle: battle, record: ProvenanceLedger.unknownOrigin))
        var rep = StepReport()
        rig.simulation.settle(&ctx, &rep)
        w = ctx.world
        let p0 = w.people[.noah]!.position
        _ = rig.simulation.runSteps(20, &w)
        XCTAssertEqual(w.people[.noah]!.position, p0)
        XCTAssertEqual(w.people[.noah]!.activity, .fighting(battle: battle))
        XCTAssertEqual(apply(rig, &w, .walk(to: at(w, -3, 0))).rejection?.reason, "reason.walk.in_battle")
    }

    // MARK: - 巻き戻しの「前にも」

    /// 巻き戻しの後(runResumed)、前の周回を覚えている仲間が文脈 rewind.deja_vu の一言を言う。
    func testDejaVuLineAfterRewind() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        w.people["person.test_a"]?.memories.append(MemoryRecord(kind: "memory.test.deja_vu", at: .zero, run: 1, about: nil,
                                                                persistsAcrossRewind: true))
        var ctx = StepContext(world: w, content: rig.content)
        ctx.emit(.runResumed(act: .rewound, record: ProvenanceLedger.unknownOrigin))
        var rep = StepReport()
        rig.simulation.settle(&ctx, &rep)
        XCTAssertTrue(rep.events.contains(.lineSpoken(person: "person.test_a", line: "line.test.deja_vu")))
    }

    // MARK: - REQ-S5: ノアと他の人を数値で比べる形を Frame に出さない

    func testFrameHasNoPerPersonNumbersToCompare() throws {
        let rig = try TestRig.publicOnly()
        var w = world(rig)
        let furnace = place(&w, module: "furnace", at: at(w, 3, 0))
        _ = apply(rig, &w, .assign(person: "person.test_a", assignment: .operate(placement: furnace)))
        _ = rig.simulation.runSteps(40, &w)
        let frame = FrameBuilder(content: rig.content).build(w, revision: 1, previous: nil, report: nil)
        // 人の絵は位置・向き・補間の進み・文字・名前だけ(体・関係・速さ・思想の数を持たない)
        let fields = Set(Mirror(reflecting: frame.actors.first!).children.compactMap(\.label))
        XCTAssertTrue(fields.isSubset(of: ["id", "glyph", "from", "to", "progress", "facing", "label"]), "\(fields)")
        // 上の帯の数値は拠点全体のもの(人ごとの数値ではない)
        let people = Set(w.people.order.map(\.rawValue))
        XCTAssertTrue(frame.status.allSatisfy { s in !people.contains { s.key.contains($0) } })
    }

    // MARK: - 決定性

    func testSameSeedSameCommandsSameWorld() throws {
        let rig = try TestRig.publicOnly()
        func run() -> WorldState {
            var w = world(rig, seed: 7)
            let furnace = place(&w, module: "furnace", at: at(w, 4, 4))
            _ = apply(rig, &w, .assign(person: "person.test_a", assignment: .operate(placement: furnace)))
            _ = apply(rig, &w, .assign(person: "person.test_b", assignment: .guardArea(center: at(w, -6, -6), radius: 2)))
            _ = apply(rig, &w, .walk(to: at(w, 10, -10)))
            _ = rig.playDay(&w, dt: 0.37)
            return w
        }
        XCTAssertEqual(run(), run())
    }

    /// 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(CrewSystem().handle(foreign, &ctx), .notMine)
    }
}
