import RFAbilities
import RFContent
import RFKernel
import RFPresent
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// U10 研究と力: 力は R1 で比べられる画面を作らない(REQ-S5)/ 見えてからの代償型の力の仕組み(R3 の土台)。
final class AbilitiesSystemTests: XCTestCase {
    static let sense: AbilityID = "ability.test.sense"
    static let calm: AbilityID = "ability.test.calm"
    static let keeper: PersonID = "person.test_c"
    static let hour = Int(3600 / SimStep.gameSeconds)

    func testIgnoresForeignCommands() throws {
        let rig = try TestRig.publicOnly()
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        let foreign: Command = .base(.demolish(placement: EntityID(1)))
        XCTAssertEqual(AbilitiesSystem().handle(foreign, &ctx), .notMine)
    }

    // MARK: R1 — 伏線だけ。比べられる形にしない(REQ-S5)

    /// ノアの手(道具なしで純度が読める)は定義の上にだけあり、見えない・使えない・一覧に出ない。
    /// 読める/読めないの差は、R2 で検品台に付けたときにプレイヤーが自分で比べて気づく(BEAT-03)。
    func testForeshadowedAbilityIsInvisibleAndUnusable() throws {
        let rig = try TestRig.publicOnly()
        var w = rig.factory.newWorld(seed: 3)
        XCTAssertTrue(rig.content.perceives(person: .noah, skills: [], sense: "purity"))
        XCTAssertFalse(rig.content.perceives(person: "person.test_a", skills: [], sense: "purity"))
        XCTAssertEqual(AbilityRules.visibleAbilities(of: .noah, w, rig.content), [])
        let r = rig.simulation.apply(.abilities(.use(person: .noah, ability: Self.sense, target: nil)), to: &w)
        XCTAssertEqual(r.rejection?.reason, AbilityReasons.unknown)
        _ = rig.playDay(&w)
        XCTAssertEqual(w.abilities, AbilitiesState(), "R1 の伏線の力は世界に数値を作らない")
    }

    /// 画面(Frame)に「ノアだけの数値」が無い: 力の切れ端にノアだけの値を入れても Frame は 1 文字も変わらず、
    /// その値は Frame のどこにも現れない(数・文字列のどちらでも)。
    func testFrameHasNoNoahOnlyNumbers() throws {
        let rig = try TestRig.publicOnly()
        var plain = rig.factory.newWorld(seed: 5)
        _ = rig.simulation.runSteps(Self.hour, &plain)
        var marked = plain
        marked.abilities.mastery[.noah] = [Self.sense: 7_654_321]
        marked.abilities.reserve[.noah] = Milli(raw: 9_876_543)
        marked.abilities.cooldowns[.noah] = [Self.sense: GameTime(seconds: 5_555_555)]

        let builder = FrameBuilder(content: rig.content)
        let a = builder.build(plain, revision: 1, previous: nil, report: nil)
        let b = builder.build(marked, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(a, b, "力の値は Frame に入らない")

        let leaves = Self.leaves(of: b)
        for marker in ["7654321", "9876543", "9876.543", "5555555"] {
            XCTAssertFalse(leaves.contains { $0.contains(marker) }, "Frame に \(marker) が出ている")
        }
        // 人ごとの見え方は、ノアと仲間で同じ項目の形(ノアだけの欄が無い)
        let noah = b.actors.first { $0.id == PersonID.noah.rawValue }
        let other = b.actors.first { $0.id != PersonID.noah.rawValue }
        XCTAssertNotNil(noah)
        XCTAssertNotNil(other)
        XCTAssertEqual(Mirror(reflecting: noah!).children.map(\.label), Mirror(reflecting: other!).children.map(\.label))
    }

    /// Frame の葉(数・文字列)を全部集める(後で項目が増えても検査が効くように、反射でたどる)。
    static func leaves(of value: Any) -> [String] {
        let m = Mirror(reflecting: value)
        if m.children.isEmpty { return ["\(value)"] }
        return m.children.flatMap { leaves(of: $0.value) }
    }

    // MARK: R3 の土台 — 見えてからの代償型の力

    func revealedWorld(_ rig: TestRig) -> WorldState {
        var w = rig.factory.newWorld(seed: 9)
        w.people[Self.keeper]?.presence = .member(since: .zero)
        let spawn = w.people[.noah]?.position
        w.people[Self.keeper]?.position = spawn
        var ctx = StepContext(world: w, content: rig.content)
        ctx.learn("fact.test.revealed")
        return ctx.world
    }

    /// 見えない間は使えず、範囲も付かない。見えると持ち主だけが使え、力の元を使い、熟達と来歴が残る。
    /// 間を置かないと使えない。元が足りない分は傷で払う。夜明けに元が満ちる。
    func testVisibleAbilityPaysCostAndCoolsDown() throws {
        let rig = try TestRig.publicOnly()
        var hidden = rig.factory.newWorld(seed: 9)
        hidden.people[Self.keeper]?.presence = .member(since: .zero)
        XCTAssertEqual(rig.simulation.apply(.abilities(.use(person: Self.keeper, ability: Self.calm, target: nil)),
                                            to: &hidden).rejection?.reason, AbilityReasons.unknown, "見えない間")

        var w = revealedWorld(rig)
        XCTAssertEqual(AbilityRules.visibleAbilities(of: Self.keeper, w, rig.content), [Self.calm])
        XCTAssertEqual(AbilityRules.visibleAbilities(of: .noah, w, rig.content), [], "持っていない人には出ない")
        XCTAssertEqual(rig.simulation.apply(.abilities(.use(person: .noah, ability: Self.calm, target: nil)),
                                            to: &w).rejection?.reason, AbilityReasons.unknown)

        let target = w.people[.noah]!.position!
        var r = rig.simulation.apply(.abilities(.use(person: Self.keeper, ability: Self.calm, target: target)), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.narrative.counters["counter.test.ability"], 1, "使うと世界が変わる")
        XCTAssertEqual(w.abilities.reserve[Self.keeper], Milli(2))
        XCTAssertEqual(w.abilities.mastery(Self.keeper, Self.calm), 1)
        guard case .abilityUsed(Self.keeper, Self.calm, let rec)? = r.events.first(where: { $0.hook == "ability.used" })
        else { return XCTFail("abilityUsed が出ていない") }
        let record = w.ledger.records.first { $0.id == rec }
        XCTAssertEqual(record?.act, .used)
        XCTAssertEqual(record?.subject, .ability(Self.calm))
        XCTAssertEqual(record?.place, target)

        r = rig.simulation.apply(.abilities(.use(person: Self.keeper, ability: Self.calm, target: nil)), to: &w)
        XCTAssertEqual(r.rejection?.reason, AbilityReasons.cooldown)
        _ = rig.simulation.runSteps(Self.hour, &w)
        r = rig.simulation.apply(.abilities(.use(person: Self.keeper, ability: Self.calm, target: nil)), to: &w)
        XCTAssertNil(r.rejection)
        XCTAssertEqual(w.abilities.reserve[Self.keeper], .zero)
        let second = w.ledger.records.last { $0.act == .used && $0.detail["passive"] == nil }
        XCTAssertEqual(second?.detail["wound"], .int(5), "足りない 1 を傷 5 で払う")

        _ = rig.playDay(&w)
        _ = rig.simulation.apply(.time(.sleep), to: &w)
        XCTAssertEqual(w.abilities.reserve[Self.keeper], Milli(5), "夜明けに満ちる")
    }

    /// 力の範囲の効果(獣が寄らない など)は、力が見えていて持ち主が一員の間だけ、持ち主を中心に付く。
    func testAbilityAuraFollowsHolderWhileMember() throws {
        let rig = try TestRig.publicOnly()
        var hidden = rig.factory.newWorld(seed: 9)
        hidden.people[Self.keeper]?.presence = .member(since: .zero)
        let spawn = hidden.people[.noah]?.position
        hidden.people[Self.keeper]?.position = spawn
        _ = rig.simulation.runSteps(4, &hidden)
        XCTAssertTrue(hidden.auras.active.isEmpty, "見えない力は範囲も付けない")

        var w = revealedWorld(rig)
        _ = rig.simulation.runSteps(4, &w)
        let auras = w.auras.active.values.filter { $0.kind == "aura.test.calm" }
        XCTAssertEqual(auras.count, 1)
        XCTAssertEqual(auras.first?.source, .person(Self.keeper))
        let near = w.people[Self.keeper]!.position!
        XCTAssertNotNil(Auras.active(at: near, kind: "aura.test.calm", in: w))
        _ = rig.simulation.runSteps(4, &w)
        XCTAssertEqual(w.auras.active.values.filter { $0.kind == "aura.test.calm" }.count, 1, "付け直さない")

        w.people[Self.keeper]?.presence = .away(since: w.clock.now)
        _ = rig.simulation.runSteps(1, &w)
        XCTAssertTrue(w.auras.active.values.filter { $0.kind == "aura.test.calm" }.isEmpty, "一員でなくなれば外れる")
        XCTAssertNil(w.abilities.auras[Self.keeper])
    }

    /// 配属の効き(BEAT-25 の土台): 力の passives はスキルと同じ問い合わせで各システムが読む。
    func testPassivesAreReadThroughContentQueries() throws {
        var c = try TestContent.publicOnly()
        c.abilities[Self.calm]?.passives = [.speed(work: WorkKey.module("furnace"), permille: 2000)]
        XCTAssertEqual(c.speedPermille(person: Self.keeper, skills: [], work: WorkKey.module("furnace")), 2000)
        XCTAssertEqual(c.speedPermille(person: .noah, skills: [], work: WorkKey.module("furnace")), 1000)
    }
}
