import RFContent
import RFKernel
import RFResearch
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U10 研究と力: 研究机に付いた仲間が昼に進める / 完了で解禁と効果 / スキルが道筋を増やす。
final class ResearchSystemTests: XCTestCase {
    static let desk: StructureKindID = "structure.test.desk"
    static let basics: ResearchID = "research.test.basics"
    static let metal: ResearchID = "research.test.metal"
    static let hidden: ResearchID = "research.test.hidden"
    static let parts: ResearchID = "research.test.parts"
    static let stonework: SkillID = "skill.test.stonework"
    static let kindling: SkillID = "skill.test.kindling"
    static let studyB: PersonID = "person.test_b" // 専門 "study"(研究机の専門)
    static let plainA: PersonID = "person.test_a"
    /// 1 ゲーム時間のステップ数。
    static let hour = Int(3600 / SimStep.gameSeconds)

    // MARK: 道具

    /// 研究机を置き、その人を隣に立たせて配属する(建てる・歩くは U8・U5 の担当なので、結果の状態を直に作る)。
    @discardableResult
    func seatAtDesk(_ w: inout WorldState, _ people: [PersonID], kind: StructureKindID = desk) -> EntityID {
        let at = w.people[.noah]!.position!
        let id = w.newEntityID()
        w.placements.items[id] = Placement(id: id, kind: .structure(kind), at: at, facing: .south,
                                           origin: ProvenanceLedger.unknownOrigin, status: .running)
        for (i, p) in people.enumerated() {
            w.people[p]?.position = WorldPoint(at.layer, GridPoint(at.point.x + 1, at.point.y + (i % 2)))
            w.people[p]?.assignment = .operate(placement: id)
        }
        return id
    }

    func apply(_ rig: TestRig, _ c: ResearchCommand, _ w: inout WorldState) -> StepReport {
        rig.simulation.apply(.research(c), to: &w)
    }

    func newWorld(_ rig: TestRig) -> WorldState { rig.factory.newWorld(seed: 7) }

    // MARK: 骨組み

    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(ResearchSystem().handle(foreign, &ctx), .notMine)
    }

    // MARK: 研究机に付いた仲間が昼に進める

    /// 研究机に付いた仲間が昼の間に研究を進める(研究の専門の人は 1.5 倍)。付いていない人は進めない。
    func testDeskWorkerAdvancesResearchDuringDay() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        seatAtDesk(&w, [Self.studyB])
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        _ = rig.simulation.runSteps(Self.hour, &w)
        // 机の速さ 10 点/時 × 専門 1.5 = 15 点
        XCTAssertEqual(w.research.points(of: Self.basics), 15)
        XCTAssertEqual(w.research.studying, [Self.studyB])
        XCTAssertTrue(w.research.isLearning(Self.studyB), "研究している人は学ぶ時期(BEAT-15)")
        XCTAssertFalse(w.research.isLearning(.noah))
    }

    /// 研究を選んでいない・机に付いていない・机が建ち終えていない間は進まない。
    func testNoProgressWithoutSelectionDeskOrWorker() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        let desk = seatAtDesk(&w, [])
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertTrue(w.research.progress.isEmpty, "選んでいない")
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertEqual(w.research.points(of: Self.basics), 0, "誰も付いていない")
        // 配属はしたが、上書き(出来事が配属に従わせない)の間は進まない
        w.people[Self.plainA]?.assignment = .operate(placement: desk)
        w.people[Self.plainA]?.position = WorldPoint(w.placements.items[desk]!.at.layer,
                                                     GridPoint(w.placements.items[desk]!.at.point.x, w.placements.items[desk]!.at.point.y + 1))
        w.people[Self.plainA]?.override = AssignmentOverride(assignment: .idle, aura: nil, until: nil,
                                                             origin: ProvenanceLedger.unknownOrigin)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertEqual(w.research.points(of: Self.basics), 0, "上書きの間")
        w.people[Self.plainA]?.override = nil
        w.placements.items[desk]?.status = .underConstruction(progress: 500)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertEqual(w.research.points(of: Self.basics), 0, "建造中の机")
        w.placements.items[desk]?.status = .running
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertEqual(w.research.points(of: Self.basics), 10, "専門でない人は机の速さのまま")
    }

    /// 研究は昼の間だけ進む(寝て夜を越しても進まない)。
    func testResearchStopsAtNight() throws {
        var content = try TestContent.publicOnly()
        content.structures[Self.desk]?.provides["research"] = 1 // 1 日で終わらないように遅くする
        let rig = TestRig(content: content)
        var w = newWorld(rig)
        seatAtDesk(&w, [Self.plainA])
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        _ = rig.playDay(&w)
        XCTAssertEqual(w.clock.phase, .dusk)
        let atDusk = w.research.progress[Self.basics] ?? 0
        XCTAssertEqual(atDusk / ResearchState.unitsPerPoint, 7, "昼 8 時間のうち日没のステップを除いて約 8 点")
        XCTAssertNil(rig.simulation.apply(.time(.sleep), to: &w).rejection)
        XCTAssertEqual(w.clock.phase, .day)
        // 夜明けのステップ(新しい昼の最初の 15 秒)の分だけは進んでよい
        XCTAssertLessThanOrEqual((w.research.progress[Self.basics] ?? 0) - atDusk, 1 * 15 * 1000, "夜は進まない")
    }

    /// 同じ研究に付く人が増えると速くなるが、逓減する(原作: 1 人 100%・2 人 150%)。
    func testMoreResearchersHelpWithDiminishingReturns() throws {
        XCTAssertEqual(ResearchRules.combined([1000]), 1000)
        XCTAssertEqual(ResearchRules.combined([1000, 1000]), 1500)
        XCTAssertEqual(ResearchRules.combined([1000, 1000, 1000]), 1850)
        XCTAssertEqual(ResearchRules.combined([1000, 1000, 1000, 1000, 1000]), 2100)
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        seatAtDesk(&w, [Self.plainA, Self.studyB])
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        _ = rig.simulation.runSteps(Self.hour, &w)
        // 速い人(15)から重み 1000、次(10)に 500 → 20 点
        XCTAssertEqual(w.research.points(of: Self.basics), 20)
    }

    /// 夜作業の研究: 研究机があれば、行為の時間(2 時間)だけ進む。昼にはできない。
    func testNightStudyAdvancesForItsDuration() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        seatAtDesk(&w, [])
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        XCTAssertEqual(apply(rig, .nightStudy(person: .noah), &w).rejection?.reason, ResearchReasons.notNight)
        _ = rig.playDay(&w)
        XCTAssertNil(rig.simulation.apply(.time(.startNightWork), to: &w).rejection)
        let r = apply(rig, .nightStudy(person: .noah), &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(r.steps, 2 * Self.hour)
        XCTAssertEqual(w.research.points(of: Self.basics), 20, "10 点/時 × 2 時間")
        XCTAssertTrue(w.research.nightSessions.isEmpty)
    }

    // MARK: 完了で解禁と効果

    /// 段ごとに解禁され、全部終わるとパッケージの解禁と効果。来歴に「誰が研究したか」が残る。
    func testCompletionUnlocksAndAppliesEffects() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        seatAtDesk(&w, [Self.studyB])
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        // 20 点(1 段目)= 80 分
        var r = rig.simulation.runSteps(80 * 60 / Int(SimStep.gameSeconds), &w)
        XCTAssertEqual(w.research.nodesDone[Self.basics], 1)
        XCTAssertTrue(w.research.unlocked.handwork.contains("handwork.test.cord"))
        XCTAssertFalse(w.research.unlocked.handwork.contains("handwork.test.charcoal"))
        XCTAssertTrue(r.events.contains { if case .researchNode(Self.basics, 0, _) = $0 { true } else { false } })
        XCTAssertFalse(w.research.completed.contains(Self.basics))

        r = rig.simulation.runSteps(80 * 60 / Int(SimStep.gameSeconds), &w)
        XCTAssertTrue(w.research.completed.contains(Self.basics))
        XCTAssertNil(w.research.active, "終わったら次を選ぶまで空く")
        XCTAssertTrue(w.research.unlocked.handwork.contains("handwork.test.charcoal"))
        XCTAssertTrue(w.research.unlocked.structures.contains("structure.test.campfire"))
        XCTAssertEqual(w.narrative.counters["counter.test.research"], 1, "完了の効果が世界を変える")
        guard let done = r.events.compactMap({ e -> ProvenanceID? in
            if case .researchCompleted(Self.basics, let rec) = e { rec } else { nil }
        }).first else { return XCTFail("researchCompleted が出ていない") }
        let rec = w.ledger.records.first { $0.id == done }
        XCTAssertEqual(rec?.act, .researched)
        XCTAssertEqual(rec?.actor, Self.studyB)
        XCTAssertEqual(rec?.subject, .research(Self.basics))
        XCTAssertTrue(ConditionEvaluator.evaluatePure(.researchDone(id: Self.basics), world: w, content: rig.content) == true)

        // 進みは上限で止まり、もう選べない
        XCTAssertEqual(apply(rig, .select(research: Self.basics), &w).rejection?.reason, ResearchReasons.done)
        XCTAssertEqual(w.research.points(of: Self.basics), 40)
    }

    /// 前提の研究が終わるまで選べない。終われば選べる。切り替えても進みは残る。
    func testPrerequisitesAndSwitchingKeepProgress() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        seatAtDesk(&w, [Self.plainA])
        XCTAssertEqual(apply(rig, .select(research: Self.metal), &w).rejection?.reason, ResearchReasons.locked)
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertNil(apply(rig, .select(research: Self.parts), &w).rejection)
        XCTAssertEqual(w.research.points(of: Self.basics), 10, "切り替えても残る")
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        _ = rig.simulation.runSteps(3 * Self.hour, &w)
        XCTAssertTrue(w.research.completed.contains(Self.basics))
        XCTAssertNil(apply(rig, .select(research: Self.metal), &w).rejection)
    }

    /// 物を使う研究は、初めて選んだときに一度だけ使う。足りなければ選べない。
    func testResearchCostIsPaidOnce() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        XCTAssertEqual(w.inventory.quantity("wood"), 3)
        XCTAssertNil(apply(rig, .select(research: Self.parts), &w).rejection)
        XCTAssertEqual(w.inventory.quantity("wood"), 1)
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        XCTAssertNil(apply(rig, .select(research: Self.parts), &w).rejection)
        XCTAssertEqual(w.inventory.quantity("wood"), 1, "選び直しで二度使わない")

        var w2 = newWorld(rig)
        _ = w2.inventory.holders[.base]?.removeAll { $0.stuff == .item("wood") }
        XCTAssertEqual(apply(rig, .select(research: Self.parts), &w2).rejection?.reason, ResearchReasons.noMaterials)
    }

    /// 存在を伏せる研究は、条件が成り立つまで一覧に出ず、選べない(理由は「知らない」と同じ)。
    func testHiddenResearchIsNotListedUntilRevealed() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        XCTAssertFalse(ResearchQueries.list(w, rig.content).contains { $0.id == Self.hidden })
        XCTAssertEqual(apply(rig, .select(research: Self.hidden), &w).rejection?.reason, ResearchReasons.unknown)
        XCTAssertEqual(apply(rig, .select(research: "research.test.nonexistent"), &w).rejection?.reason,
                       ResearchReasons.unknown)
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.revealed")
        w = ctx.world
        XCTAssertTrue(ResearchQueries.list(w, rig.content).contains { $0.id == Self.hidden && $0.status == .available })
        XCTAssertNil(apply(rig, .select(research: Self.hidden), &w).rejection)
        let metal = ResearchQueries.list(w, rig.content).first { $0.id == Self.metal }
        XCTAssertEqual(metal?.status, .locked, "前提がまだの研究は見えるが選べない")
    }

    // MARK: スキルが道筋を増やす

    /// スキルは研究の後に習えるようになり、時間をかけて身につく。身につくと道筋(手作業)が解禁される。
    /// 習っている間は学ぶ時期(BEAT-15)。
    func testSkillTakesTimeAndUnlocksAPath() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        XCTAssertEqual(apply(rig, .learnSkill(person: Self.plainA, skill: Self.stonework), &w).rejection?.reason,
                       ResearchReasons.skillLocked, "研究の前は習えない")
        w.research.completed.insert(Self.basics)
        XCTAssertNil(apply(rig, .learnSkill(person: Self.plainA, skill: Self.stonework), &w).rejection)
        XCTAssertTrue(w.research.isLearning(Self.plainA))
        XCTAssertFalse(w.research.unlocked.handwork.contains("handwork.test.stone_tool"))
        var r = rig.simulation.runSteps(2 * Self.hour, &w)
        XCTAssertFalse(r.events.contains { $0.hook == "skill" })
        let half = ResearchQueries.skills(of: Self.plainA, w, rig.content).first { $0.id == Self.stonework }
        XCTAssertEqual(half?.status, .learning)
        XCTAssertEqual(half?.progressPermille, 500)
        r = rig.simulation.runSteps(2 * Self.hour, &w)
        XCTAssertFalse(w.research.isLearning(Self.plainA))
        XCTAssertTrue(w.research.unlocked.handwork.contains("handwork.test.stone_tool"), "石器の道が開く")
        guard case .skillAcquired(let p, let s, let rec)? = r.events.first(where: { $0.hook == "skill" }) else {
            return XCTFail("skillAcquired が出ていない")
        }
        XCTAssertEqual(p, Self.plainA)
        XCTAssertEqual(s, Self.stonework)
        XCTAssertEqual(w.ledger.records.first { $0.id == rec }?.act, .acquiredSkill)
        XCTAssertTrue(rig.content.gatedUnlocks.contains(.handwork(id: "handwork.test.stone_tool")),
                      "研究・スキルで開く物は、解禁まで使えないと読める")
    }

    /// 習うのをやめても進みは残り、選び直せば続きから。別のスキルに替えても前の進みは取っておく。
    func testStoppingAndSwitchingSkillsKeepsProgress() throws {
        let rig = try TestRig.publicOnly()
        var w = newWorld(rig)
        w.research.completed.insert(Self.basics)
        XCTAssertNil(apply(rig, .learnSkill(person: .noah, skill: Self.stonework), &w).rejection)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertNil(apply(rig, .learnSkill(person: .noah, skill: Self.kindling), &w).rejection)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertNil(apply(rig, .stopLearning(person: .noah), &w).rejection)
        XCTAssertEqual(apply(rig, .stopLearning(person: .noah), &w).rejection?.reason, ResearchReasons.notLearning)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertEqual(w.research.skillProgress[.noah]?[Self.stonework], 3600 * 1000)
        XCTAssertEqual(w.research.skillProgress[.noah]?[Self.kindling], 3600 * 1000)
        XCTAssertNil(apply(rig, .learnSkill(person: .noah, skill: Self.kindling), &w).rejection)
        let r = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertTrue(r.events.contains { if case .skillAcquired(.noah, Self.kindling, _) = $0 { true } else { false } },
                      "続きから 1 時間で身につく(2 時間のスキル)")
    }

    /// 火起こし: スキルを持つ人だけ成功率が上がる(道筋を増やす選択。行為の担当が ContentDB で読む)。
    /// 習得の時間が無いスキルはすぐ身につく。身についた人(skills)は人の担当が入れる。
    func testSkillModifiersRaiseChanceAndSpeed() throws {
        let rig = try TestRig.publicOnly()
        let c = rig.content
        XCTAssertEqual(c.chanceBonus(person: .noah, skills: [], interaction: "interaction.test.kindle"), 0)
        XCTAssertEqual(c.chanceBonus(person: .noah, skills: [Self.kindling], interaction: "interaction.test.kindle"), 3000)
        XCTAssertEqual(c.chanceBonus(person: .noah, skills: [Self.kindling], interaction: "interaction.test.other"), 0)

        var w = newWorld(rig)
        let r = apply(rig, .learnSkill(person: Self.plainA, skill: "skill.test.instant"), &w)
        XCTAssertNil(r.rejection)
        XCTAssertTrue(r.events.contains { if case .skillAcquired(Self.plainA, "skill.test.instant", _) = $0 { true } else { false } })
        // 人の担当(U5)が skills に入れた後の効き: 研究が 2 倍速
        w.people[Self.plainA]?.skills.insert("skill.test.instant")
        XCTAssertEqual(apply(rig, .learnSkill(person: Self.plainA, skill: "skill.test.instant"), &w).rejection?.reason,
                       ResearchReasons.skillKnown)
        seatAtDesk(&w, [Self.plainA])
        XCTAssertNil(apply(rig, .select(research: Self.basics), &w).rejection)
        _ = rig.simulation.runSteps(Self.hour, &w)
        XCTAssertEqual(w.research.points(of: Self.basics), 20)
    }

    /// 決定性: 同じ seed と同じコマンドで、研究とスキルの進みが同じになる。
    func testDeterministic() throws {
        let rig = try TestRig.publicOnly()
        func run() -> WorldState {
            var w = newWorld(rig)
            seatAtDesk(&w, [Self.plainA, Self.studyB])
            _ = apply(rig, .select(research: Self.basics), &w)
            _ = apply(rig, .learnSkill(person: .noah, skill: "skill.test.instant"), &w)
            _ = rig.playDay(&w)
            _ = apply(rig, .select(research: Self.metal), &w)
            _ = rig.simulation.apply(.time(.sleep), to: &w)
            _ = rig.playDay(&w)
            return w
        }
        let a = run(), b = run()
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.research.completed.contains(Self.metal))
    }
}
