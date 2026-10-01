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

/// 1 次元の帯・方針と撤退・武器の強さ・来歴。
final class LaneAndWeaponTests: XCTestCase {
    // MARK: - 武器の強さ = 素材の純度と硬さ

    func testPurityEffectIsIntegerNines() {
        XCTAssertEqual(Weapons.ninesMilli(Purity(percent: 90)), 1000)
        XCTAssertEqual(Weapons.ninesMilli(Purity(percent: 99)), 2000)
        XCTAssertEqual(Weapons.ninesMilli(Purity(percent: 50)), 301)
        XCTAssertEqual(Weapons.ninesMilli(.full), 6000)
        XCTAssertEqual(Weapons.purityEffectPermille(Purity(percent: 90)), 1100)
        XCTAssertEqual(Weapons.purityEffectPermille(Purity(percent: 99)), 1400)
    }

    func testWeaponPowerFollowsPurityAndHardness() {
        func iron(_ pct: Int, _ temper: Temper, _ shape: Shape = .rod) -> Matter {
            Matter(substance: .iron, purity: Purity(percent: pct), stage: .metal, shape: shape, worked: 1, temper: temper)
        }
        let hardSpear = Weapons.power(of: iron(70, .hard))
        let plainSpear = Weapons.power(of: iron(70, .none))
        let softSpear = Weapons.power(of: iron(70, .soft))
        let poorHard = Weapons.power(of: iron(35, .hard))
        let cracked = Weapons.power(of: iron(70, .cracked))
        XCTAssertGreaterThan(hardSpear, plainSpear, "剛(硬い)は強い")
        XCTAssertGreaterThan(plainSpear, softSpear, "柔は弱い")
        XCTAssertGreaterThan(hardSpear, poorHard, "純度が高いほど強い")
        XCTAssertLessThan(cracked, hardSpear, "割れは欠ける")
        XCTAssertEqual(hardSpear, 12)

        let def = CombatDef()
        let spear = Weapons.profile(EquippedItem(stuff: .matter(iron(70, .hard)), origin: ProvenanceID(5)), def: def, ruleBook: .r1)
        XCTAssertEqual(spear.reachMin, 1)
        XCTAssertEqual(spear.reachMax, 2)
        XCTAssertEqual(spear.origin, ProvenanceID(5))
        let blade = Weapons.profile(EquippedItem(stuff: .matter(iron(70, .hard, .plate)), origin: nil), def: def, ruleBook: .r1)
        XCTAssertEqual(blade.reachMax, 1)
        XCTAssertEqual(Weapons.profile(nil, def: def, ruleBook: .r1), .unarmed)
    }

    /// 剛鉄の槍を持ったノアは群れ 1 匹にほぼ勝ち、素手ではほぼ負ける(発明が戦闘に返る)。
    func testArmedNoahWinsUnarmedLoses() throws {
        let rig = try TestRig.publicOnly()
        func fight(seed: UInt64, armed: Bool) -> BattleState.Outcome? {
            var w = rig.factory.newWorld(seed: seed)
            Fixture.clearPeople(&w, except: [.noah])
            if armed { Fixture.arm(&w, .noah) }
            _ = rig.simulation.apply(.combat(.startBattle(enemy: "enemy.test.pack", count: 1, near: w.people[.noah]!.position!)), to: &w)
            _ = Fixture.untilBattlesEnd(rig, &w)
            return w.combat.lastBattle?.outcome
        }
        let seeds: [UInt64] = Array(1...30)
        let armedWins = seeds.filter { fight(seed: $0, armed: true) == .won }.count
        let unarmedWins = seeds.filter { fight(seed: $0, armed: false) == .won }.count
        XCTAssertGreaterThanOrEqual(armedWins, 27)
        XCTAssertLessThanOrEqual(unarmedWins, 3)
    }

    // MARK: - 1 次元の帯で自動に進む

    private func unit(_ ref: BattleUnit.Ref, _ side: BattleUnit.Side, at pos: Int, hp: Int = 100, attack: Int = 4,
                      speed: Int = 6, reach: ClosedRange<Int> = 0...0) -> BattleUnit {
        BattleUnit(ref: ref, side: side, position: pos, hp: hp, maxHP: hp, attack: attack, defense: 0, speed: speed,
                   reachMin: reach.lowerBound, reachMax: reach.upperBound)
    }

    private func battle(_ units: [BattleUnit], stance: BattleState.Stance) -> BattleState {
        BattleState(id: EntityID(1), kind: .encounter, at: Fixture.at(Fixture.store), laneSize: 6, participants: [.noah],
                    enemies: [EntityID(2)], units: units, stance: stance, startedAt: .zero, firstTurnAt: .zero,
                    origin: ProvenanceID(1))
    }

    func testLaneRunsToAnEndWithoutInput() {
        for seed in UInt64(1)...20 {
            var b = battle([unit(.person(.noah), .allies, at: 0, attack: 10),
                            unit(.enemy(threat: EntityID(2), kind: "enemy.test.small", index: 0), .enemies, at: 5, hp: 15, attack: 3, speed: 5),
                            unit(.enemy(threat: EntityID(2), kind: "enemy.test.small", index: 1), .enemies, at: 4, hp: 15, attack: 3, speed: 5)],
                           stance: .advance)
            var rng = SeededRandom(state: seed)
            var result: BattleState.Outcome?
            var turns = 0
            while result == nil && turns < 100 {
                result = Lane.resolveTurn(&b, def: CombatDef(), rng: &rng)
                turns += 1
                XCTAssertTrue(b.units.allSatisfy { (0..<6).contains($0.position) })
            }
            XCTAssertNotNil(result, "入力なしで決着する")
        }
    }

    /// 距離を取る: 槍は届く一番遠い間合いで待ち、来た相手を先に打つ。前に出る: 詰める。
    func testStanceChangesHowAlliesMove() {
        let spear = unit(.person(.noah), .allies, at: 0, attack: 10, speed: 9, reach: 1...2)
        let beast = unit(.enemy(threat: EntityID(2), kind: "enemy.test.small", index: 0), .enemies, at: 5, hp: 50, speed: 4)
        var keep = battle([spear, beast], stance: .keepDistance)
        var rng = SeededRandom(state: 1)
        Lane.resolveTurn(&keep, def: CombatDef(), rng: &rng)
        XCTAssertEqual(keep.units[0].position, 0, "距離を取る: 動かずに待つ")
        XCTAssertEqual(keep.units[1].position, 3, "獣が詰めて来る(速さ 4 → 2 マス)")
        var firstAttacker: Int?
        for _ in 0..<5 where firstAttacker == nil {
            Lane.resolveTurn(&keep, def: CombatDef(), rng: &rng)
            firstAttacker = keep.beats.first { $0.act == .hit || $0.act == .miss }?.actor
        }
        XCTAssertEqual(firstAttacker, 0, "間合いに入った獣を先に打つ")

        var adv = battle([spear, beast], stance: .advance)
        var rng2 = SeededRandom(state: 1)
        Lane.resolveTurn(&adv, def: CombatDef(), rng: &rng2)
        XCTAssertGreaterThan(adv.units[0].position, 0, "前に出る: 詰める")
    }

    /// 方針と撤退はコマンドで選べ、戦闘は自動で進む。撤退すると逃げ、群れは地図に残る。
    func testStanceAndRetreatCommands() throws {
        let rig = try TestRig.publicOnly()
        var fled = 0
        for seed in UInt64(1)...10 {
            var w = rig.factory.newWorld(seed: seed)
            let r = rig.simulation.apply(.combat(.startBattle(enemy: "enemy.test.pack", count: 3, near: w.people[.noah]!.position!)), to: &w)
            let id = try XCTUnwrap(Fixture.started(r.events).first)
            XCTAssertEqual(w.combat.battles[id]?.laneSize, 6)
            XCTAssertNil(rig.simulation.apply(.combat(.stance(battle: id, stance: .advance)), to: &w).rejection)
            XCTAssertEqual(w.combat.battles[id]?.stance, .advance)
            XCTAssertNil(rig.simulation.apply(.combat(.retreat(battle: id)), to: &w).rejection)
            XCTAssertEqual(rig.simulation.apply(.combat(.retreat(battle: id)), to: &w).rejection?.reason,
                           "reason.combat.already_retreating")
            let end = Fixture.untilBattlesEnd(rig, &w)
            let e = try XCTUnwrap(Fixture.ended(end.events).first)
            XCTAssertFalse(e.1, "撤退した戦いは勝ちにならない")
            if e.2 {
                fled += 1
                XCTAssertEqual(w.ledger.record(e.3)?.act, .fled)
                let t = try XCTUnwrap(w.combat.threats.values.first, "群れは地図に残る")
                XCTAssertNotNil(t.calmUntil)
            }
        }
        XCTAssertGreaterThanOrEqual(fled, 8)
        // 既定の方針
        var w = rig.factory.newWorld(seed: 1)
        _ = rig.simulation.apply(.combat(.setDefaultStance(stance: .advance)), to: &w)
        let r = rig.simulation.apply(.combat(.startBattle(enemy: "enemy.test.small", count: 1, near: w.people[.noah]!.position!)), to: &w)
        XCTAssertEqual(w.combat.battles[Fixture.started(r.events)[0]]?.stance, .advance)
        XCTAssertEqual(rig.simulation.apply(.combat(.retreat(battle: EntityID(424_242))), to: &w).rejection?.reason,
                       "reason.combat.no_battle")
    }

    // MARK: - 勝ち負けが来歴に残る

    func testVictoryIsRecorded() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        Fixture.clearPeople(&w, except: [.noah])
        Fixture.arm(&w, .noah, purity: 9900)
        let spear = w.people[.noah]!.equipment["weapon"]!.origin!
        let start = rig.simulation.apply(.combat(.startBattle(enemy: "enemy.test.pack", count: 1, near: w.people[.noah]!.position!)), to: &w)
        let bid = Fixture.started(start.events)[0]
        let threat = w.combat.battles[bid]!.enemies[0]
        XCTAssertEqual(w.combat.battles[bid]!.units[0].weaponOrigin, spear, "どの武器で戦ったかを指せる")
        let r = Fixture.untilBattlesEnd(rig, &w)
        let e = try XCTUnwrap(Fixture.ended(r.events).first)
        XCTAssertTrue(e.1)
        let rec = try XCTUnwrap(w.ledger.record(e.3))
        XCTAssertEqual(rec.act, .defeated)
        XCTAssertEqual(rec.subject, .enemy("enemy.test.pack", threat))
        XCTAssertEqual(rec.actor, .noah)
        XCTAssertEqual(rec.count, 1)
        XCTAssertNotNil(rec.place, "狩場が残る")
        XCTAssertTrue(rec.tags.contains("tag.test.hunt"))
        let fought = try XCTUnwrap(w.ledger.records.first { $0.act == .fought })
        XCTAssertTrue(rec.inputs.contains(fought.id))
        XCTAssertEqual(ProvenanceQueries.count(ProvenanceQuery(act: .defeated, enemy: "enemy.test.pack"), in: w), 1,
                       "倒した数は来歴で数えられる(条件 ledger)")
        XCTAssertEqual(w.combat.kills["enemy.test.pack"], 1)
        XCTAssertEqual(w.inventory.quantity("test_meat", in: .person(.noah)), 2, "外での獲物は持ち帰る")
        XCTAssertTrue(w.combat.threats.isEmpty)
    }

    func testDefeatIsRecordedAndInjuresTheFighter() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        Fixture.clearPeople(&w, except: [.noah])
        let start = rig.simulation.apply(.combat(.startBattle(enemy: "enemy.test.pack", count: 2, near: w.people[.noah]!.position!)), to: &w)
        XCTAssertEqual(Fixture.started(start.events).count, 1)
        let r = Fixture.untilBattlesEnd(rig, &w)
        let e = try XCTUnwrap(Fixture.ended(r.events).first)
        XCTAssertFalse(e.1)
        XCTAssertFalse(e.2)
        let rec = try XCTUnwrap(w.ledger.record(e.3))
        XCTAssertEqual(rec.act, .fought)
        XCTAssertEqual(rec.detail["result"], .string("lost"))
        // 傷は人の担当へコマンドで渡す(人の担当が入るまでは「受けないコマンド」の警告、入れば体力が減る)
        XCTAssertTrue(r.warnings.contains { $0.contains("injureFromEffect") }
                      || w.people[.noah]!.body.health < BodyState().health)
        XCTAssertEqual(w.combat.threats.count, 1, "勝った群れは残る")
    }
}
