import RFCombat
import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U9 脅威と戦闘の受け入れテスト(F-work-units.md の U9 行)。
/// 夜、灯りの外から食料を狙う / 範囲 repelEnemies の中に入らない / 1 次元の帯で自動に進み、方針と撤退だけ選べる /
/// 武器の強さ = 素材の純度と硬さ / 勝ち負けが来歴に残る。
final class CombatSystemTests: XCTestCase {
    /// 骨組み: 他のシステムのコマンドは受けない。
    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(CombatSystem().handle(foreign, &ctx), .notMine)
    }

    /// 公開の試験用コンテンツだけでは夜に何も来ない(他の担当の走行を乱さない)。
    func testPublicContentIsQuietByDefault() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        _ = Fixture.toDusk(rig, &w)
        let r = Fixture.throughNight(rig, &w)
        XCTAssertTrue(w.combat.threats.isEmpty)
        XCTAssertFalse(r.events.contains { if case .threatAppeared = $0 { true } else { false } })
    }

    // MARK: - 夜、灯りの外から食料を狙う

    /// 夜、灯りの外(拠点から遠いマス)に群れが出て、蓄えへ歩き、誰もいなければ食料を奪って帰る。
    func testNightRaidComesFromOutsideAndStealsFood() throws {
        let rig = try Fixture.rig(Fixture.nightlyRaid)
        var w = rig.factory.newWorld(seed: 7)
        Fixture.clearPeople(&w)
        Fixture.addFood(&w, 5)
        _ = Fixture.toDusk(rig, &w)
        XCTAssertEqual(w.combat.plannedRaids.count, 1, "日没に今夜の群れが決まる")
        var firstSeen: WorldPoint?
        var closest = Int.max
        let r = Fixture.throughNight(rig, &w) { w in
            for t in w.combat.threats.values {
                if firstSeen == nil { firstSeen = t.position }
                closest = min(closest, t.position.point.chebyshev(to: Fixture.store))
            }
        }
        let first = try XCTUnwrap(firstSeen)
        XCTAssertGreaterThanOrEqual(first.point.chebyshev(to: Fixture.store), 10, "遠く(灯りの外)から来る")
        XCTAssertLessThanOrEqual(closest, 2, "蓄えまで歩いて来る(着いたステップで奪って帰る)")
        XCTAssertEqual(Fixture.food(w), 3, "2 匹が 1 つずつ奪う")
        XCTAssertEqual(w.combat.night.stolen["test_stash"], 2)
        let raided = r.events.compactMap { if case .raided(_, let rec) = $0 { rec } else { nil } }
        XCTAssertEqual(raided.count, 1)
        let rec = try XCTUnwrap(w.ledger.record(raided[0]))
        guard case .enemy(let kind, _) = rec.subject else { return XCTFail("奪った記録は獣を指す") }
        XCTAssertEqual(kind, "enemy.test.small")
        XCTAssertTrue(w.combat.threats.isEmpty, "奪った群れは帰る・夜明けに残らない")
    }

    // MARK: - 範囲 repelEnemies の中に入らない

    /// 蓄えが灯り(repelEnemies の範囲)の中なら、獣は縁で止まり、一晩中中に入らない。食料は無事。
    func testRepelAuraKeepsBeastsOut() throws {
        let rig = try Fixture.rig(Fixture.nightlyRaid)
        var w = rig.factory.newWorld(seed: 7)
        Fixture.clearPeople(&w)
        Fixture.addFood(&w, 5)
        Fixture.build(&w, "structure.test.beacon", at: Fixture.store)  // aura.test.ward(半径 2・repelEnemies)
        _ = Fixture.toDusk(rig, &w)
        var seen = false
        var closest = Int.max
        let r = Fixture.throughNight(rig, &w) { w in
            for t in w.combat.threats.values {
                seen = true
                closest = min(closest, t.position.point.chebyshev(to: Fixture.store))
                XCTAssertFalse(Auras.repelsEnemies(at: t.position, in: w, content: rig.content), "範囲の中に入った: \(t.position)")
            }
        }
        XCTAssertTrue(seen, "群れは来ている")
        XCTAssertEqual(closest, 3, "灯りの縁まで来て止まる")
        XCTAssertEqual(Fixture.food(w), 5)
        XCTAssertFalse(r.events.contains { if case .raided = $0 { true } else { false } })
        XCTAssertTrue(w.combat.threats.isEmpty, "夜明けに帰る")
    }

    /// 柵で囲めば入れない。
    func testFenceBlocksTheWay() throws {
        let rig = try Fixture.rig(Fixture.nightlyRaid)
        var w = rig.factory.newWorld(seed: 11)
        Fixture.clearPeople(&w)
        Fixture.addFood(&w, 5)
        for dy in -2...2 { for dx in -2...2 where max(abs(dx), abs(dy)) == 2 {
            Fixture.build(&w, "structure.test.fence", at: Fixture.store + GridPoint(dx, dy))
        } }
        _ = Fixture.toDusk(rig, &w)
        _ = Fixture.throughNight(rig, &w) { w in
            for t in w.combat.threats.values { XCTAssertGreaterThanOrEqual(t.position.point.chebyshev(to: Fixture.store), 3) }
        }
        XCTAssertEqual(Fixture.food(w), 5)
    }

    /// 落とし穴を踏んだ獣は倒れ、罠を作った記録が倒した記録の入力に入る。夜明けに仕掛け直す。
    func testTrapCatchesAndRecordsTheBuilder() throws {
        let rig = try Fixture.rig(Fixture.nightlyRaid)
        var w = rig.factory.newWorld(seed: 7)
        Fixture.clearPeople(&w)
        Fixture.addFood(&w, 5)
        var traps: [EntityID] = []
        for dy in -3...3 { for dx in -3...3 where max(abs(dx), abs(dy)) == 3 {
            traps.append(Fixture.build(&w, "structure.test.pit", at: Fixture.store + GridPoint(dx, dy)))
        } }
        _ = Fixture.toDusk(rig, &w)
        let r = Fixture.throughNight(rig, &w)
        let sprung = r.events.compactMap { if case .trapSprung(let p, let rec) = $0 { (p, rec) } else { nil } }
        XCTAssertEqual(sprung.count, 1, "罠の値 2 で 2 匹とも倒れる")
        let (trap, recID) = try XCTUnwrap(sprung.first)
        let rec = try XCTUnwrap(w.ledger.record(recID))
        XCTAssertEqual(rec.act, .defeated)
        XCTAssertEqual(rec.count, 2)
        XCTAssertNil(rec.actor)
        XCTAssertTrue(rec.inputs.contains(w.placements.items[trap]!.origin), "罠を作った来歴を指す")
        XCTAssertEqual(Fixture.food(w), 5)
        XCTAssertEqual(w.inventory.quantity("test_meat"), 2, "獲物は拠点の蓄えへ")
        XCTAssertEqual(w.combat.kills["enemy.test.small"], 2)
        XCTAssertTrue(w.combat.sprungTraps.isEmpty, "夜明けに仕掛け直す")
    }

    // MARK: - 見張り・駆けつける

    /// 見張りは半径の中に来た獣と戦う(蓄えに着く前に)。寝ている間も同じ規則で進む。
    func testGuardEngagesBeforeTheStore() throws {
        let rig = try Fixture.rig(Fixture.nightlyRaid)
        var w = rig.factory.newWorld(seed: 5)
        Fixture.clearPeople(&w, except: [.noah])
        w.people[.noah]?.position = Fixture.at(Fixture.store)
        w.people[.noah]?.assignment = .guardArea(center: Fixture.at(Fixture.store), radius: 5)
        Fixture.addFood(&w, 5)
        _ = Fixture.toDusk(rig, &w)
        let r = rig.simulation.apply(.time(.sleep), to: &w)
        let started = Fixture.started(r.events)
        XCTAssertFalse(started.isEmpty, "見張りが戦う")
        let b = try XCTUnwrap(w.combat.lastBattle)
        XCTAssertEqual(b.participants, [.noah])
        XCTAssertEqual(b.kind, .encounter)
        XCTAssertGreaterThanOrEqual(b.at.point.chebyshev(to: Fixture.store), 2, "蓄えより手前で")
    }

    /// 蓄えに着いた獣には拠点の人が駆けつける。勝てば奪われず、獲物が拠点に入る。
    func testDefendersRallyAtTheStore() throws {
        let rig = try Fixture.rig(Fixture.nightlyRaid)
        var w = rig.factory.newWorld(seed: 9)
        for p in w.people.order { w.people[p]?.position = Fixture.at(Fixture.store); Fixture.arm(&w, p) }
        Fixture.addFood(&w, 5)
        _ = Fixture.toDusk(rig, &w)
        let r = rig.simulation.apply(.time(.sleep), to: &w)
        let b = try XCTUnwrap(w.combat.lastBattle)
        XCTAssertEqual(b.kind, .raid(target: Fixture.at(Fixture.store)))
        XCTAssertEqual(b.outcome, .won)
        XCTAssertEqual(Fixture.food(w), 5)
        XCTAssertEqual(w.inventory.quantity("test_meat"), 2)
        XCTAssertEqual(Fixture.ended(r.events).count, 1)
    }

    // MARK: - 森で出会う・巣

    /// 出会う地形(森)にいる人に獣が寄って来て、戦いになる。灯りの中では寄らない。
    func testForestEncounter() throws {
        let rig = try Fixture.rig(Fixture.forestPack)
        var w = rig.factory.newWorld(seed: 2)
        Fixture.clearPeople(&w, except: [.noah])
        let spot = GridPoint(5, 5)
        for dy in -4...4 { for dx in -4...4 { w.map[.surface]?.setTerrain("forest", at: spot + GridPoint(dx, dy)) } }
        w.people[.noah]?.position = Fixture.at(spot)
        let r = rig.simulation.runSteps(240 * 6, &w)  // 1 時間に 1 度の確率で 6 時間
        XCTAssertTrue(r.events.contains { if case .threatAppeared(_, "enemy.test.pack") = $0 { true } else { false } })
        XCTAssertFalse(Fixture.started(r.events).isEmpty, "寄って来て戦いになる")

        var safe = rig.factory.newWorld(seed: 2)
        Fixture.clearPeople(&safe, except: [.noah])
        for dy in -4...4 { for dx in -4...4 { safe.map[.surface]?.setTerrain("forest", at: spot + GridPoint(dx, dy)) } }
        safe.people[.noah]?.position = Fixture.at(spot)
        Fixture.build(&safe, "structure.test.beacon", at: spot)
        _ = rig.simulation.runSteps(2, &safe)  // 範囲が付く
        let quiet = rig.simulation.runSteps(240 * 6, &safe)
        XCTAssertTrue(Fixture.started(quiet.events).isEmpty, "灯りの中には寄らない")
    }

    /// 巣に近づくと守りが出る。守りを全部倒すと巣が壊れ、壊した記録(印つき)が残る。
    func testNestGuardsAndDestroyingTheNest() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 4)
        let den = GridPoint(6, 6)
        let poi = EntityID(9_999)
        _ = w.map[.surface]?.placements.place(MapPlacement(id: "nest.test", kind: .nest, templateID: "poi.test.den",
                                                           anchor: den, entity: poi))
        for p in w.people.order {
            w.people[p]?.position = Fixture.at(den + GridPoint(2, 0))
            Fixture.arm(&w, p, purity: 9900)
        }
        let r = Fixture.untilBattlesEnd(rig, &w)
        XCTAssertEqual(Fixture.started(r.events).count, 1)
        XCTAssertEqual(w.combat.lastBattle?.kind, .nest(poi: poi))
        XCTAssertEqual(w.combat.lastBattle?.outcome, .won)
        let destroyed = r.events.compactMap { if case .nestDestroyed(let p, let rec) = $0 { (p, rec) } else { nil } }
        XCTAssertEqual(destroyed.count, 1)
        let rec = try XCTUnwrap(w.ledger.record(destroyed[0].1))
        XCTAssertEqual(rec.subject, .poi("poi.test.den", poi))
        XCTAssertTrue(rec.tags.contains("tag.test.den_broken"))
        XCTAssertEqual(w.combat.nests[poi]?.destroyed, rec.id)
        // 壊した巣からは守りが出ない
        let again = rig.simulation.runSteps(240, &w)
        XCTAssertTrue(Fixture.started(again.events).isEmpty)
    }

    // MARK: - 効果から

    /// 効果の spawnEnemy・startBattle(コマンド)を受ける。
    func testEffectCommands() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 1)
        let near = Fixture.at(Fixture.store + GridPoint(6, 0))
        let r1 = rig.simulation.apply(.combat(.spawnEnemy(kind: "enemy.test.small", count: 3, near: near, cause: nil)), to: &w)
        XCTAssertNil(r1.rejection)
        let t = try XCTUnwrap(w.combat.threats.values.first)
        XCTAssertEqual(t.count, 3)
        XCTAssertEqual(t.intent, .hunt(person: .noah), "昼に出た獣は近くの人に寄る")
        let r2 = rig.simulation.apply(.combat(.startBattle(enemy: "enemy.test.pack", count: 1, near: Fixture.at(Fixture.store))), to: &w)
        XCTAssertNil(r2.rejection)
        XCTAssertEqual(Fixture.started(r2.events).count, 1)
        XCTAssertEqual(w.combat.battles.values.first?.participants.count, 3, "近くの一員が全員入る")
        let bad = rig.simulation.apply(.combat(.spawnEnemy(kind: "enemy.none", count: 1, near: near, cause: nil)), to: &w)
        XCTAssertEqual(bad.rejection?.reason, "reason.combat.unknown_enemy")
    }

    // MARK: - 決定性

    func testSameSeedSameNight() throws {
        let rig = try Fixture.rig(Fixture.nightlyRaid)
        func run() -> (WorldState, [DomainEvent]) {
            var w = rig.factory.newWorld(seed: 42)
            Fixture.clearPeople(&w, except: [.noah])
            w.people[.noah]?.position = Fixture.at(Fixture.store)
            Fixture.addFood(&w, 5)
            _ = Fixture.toDusk(rig, &w)
            let r = rig.simulation.apply(.time(.sleep), to: &w)
            return (w, r.events)
        }
        let a = run(), b = run()
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
    }
}
