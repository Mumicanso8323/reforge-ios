import RFContent
import RFInvention
import RFKernel
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 発明のテストの一式。公開の試験用コンテンツに、試験用の手がかり(本文なし・ネタバレなし)と
/// 工程のモジュールの解禁・試作の材料を足す。
struct InventionFixture {
    let rig: TestRig
    let content: ContentDB

    /// 試験用の仲間(シリカの役。関係ランク 3 で手がかりをくれる)。
    static let companion: PersonID = "person.test_b"

    static let unlocked: [ModuleKindID] = [.minehead, .millstone, .sluice, .mixingBowl, .furnace, .anvil, .quenchTank]

    /// 試験用の手がかり。5 種の導線のうち、端末の断片・手が知っていた手順・仲間の知識・図鑑の空欄。
    /// 主張(claims)は文の意味を機械が読める形にしたもの。
    static func hints() -> [HintDef] {
        let M = StepPattern(.millstone), S = StepPattern(.sluice), L = StepPattern(.mixingBowl, input: .limestone)
        let F = StepPattern(.furnace), Q = StepPattern(.quenchTank)
        let fine = NamePart.grade(.fine, .metal), hard = NamePart.temper(.hard)
        let trialed = { (n: Int) in Condition.ledger(query: ProvenanceQuery(act: .trialed), atLeast: n) }
        return [
            // 端末の断片「…を砕いてから…ですすぐ…」
            HintDef(id: "hint.test.terminal", when: .always, about: "module:millstone",
                    text: "text.test.hint.terminal", source: "source:terminal",
                    claims: [HintClaim(.includes(step: M), toward: fine), HintClaim(.includes(step: S), toward: fine),
                             HintClaim(.before(first: M, then: S), toward: fine)]),
            // 手が知っていた「石灰石を入れれば」(最初の試作の後)
            HintDef(id: "hint.test.hand.lime", when: trialed(1), about: "item:limestone",
                    text: "text.test.hint.hand_lime", source: "source:hand",
                    claims: [HintClaim(.includes(step: L), toward: fine)]),
            // 手が知っていた「砕いて洗えば」(2 回目の試作の後)
            HintDef(id: "hint.test.hand.crush_wash", when: trialed(2), about: "module:sluice",
                    text: "text.test.hint.hand_crush_wash", source: "source:hand",
                    claims: [HintClaim(.next(first: M, then: S), toward: fine)]),
            // 仲間の案「混ぜ物は熱する前ね」(関係ランク 3)
            HintDef(id: "hint.test.companion", from: companion,
                    when: .person(id: companion, test: .relationAtLeast(rank: 3)), about: "module:mixing_bowl",
                    text: "text.test.hint.companion", source: "source:companion",
                    claims: [HintClaim(.before(first: L, then: F), toward: fine)]),
            // 図鑑の空欄(命名からの類推)「精 = 純度 85 以上」「剛 = 硬い」
            HintDef(id: "hint.test.codex.fine", when: .always, about: "grade:fine.metal",
                    text: "text.test.hint.codex_fine", source: "source:codex",
                    claims: [HintClaim(.gradeMeans(threshold: Purity(percent: 85)), toward: fine)],
                    target: MatterName([fine, .substance(.iron), .shape(.plate)])),
            HintDef(id: "hint.test.codex.hard", when: .always, about: "temper:hard",
                    text: "text.test.hint.codex_hard", source: "source:codex",
                    claims: [HintClaim(.includes(step: Q), toward: hard)],
                    target: MatterName([hard, .substance(.iron), .shape(.plate)])),
        ]
    }

    init(hints: [HintDef] = InventionFixture.hints()) throws {
        var c = try TestContent.publicOnly()
        for h in hints { c.hints[h.id] = h }
        content = c
        rig = TestRig(content: c)
    }

    /// 露頭の鉱石の純度(seed で 20〜35% に決める。地図の担当が露頭を作るときと同じ範囲)。
    static func orePurity(seed: UInt64) -> Purity {
        var r = SeededRandom(state: seed ^ 0x5EED_0E0E)
        let lo = R1Ore.outcrop.lowerBound.basisPoints, hi = R1Ore.outcrop.upperBound.basisPoints
        return Purity(basisPoints: lo + r.int(below: hi - lo + 1))
    }

    /// 新しい世界に、鉱石 ore 個と燃料・水・石灰石を足し、工程のモジュールを解禁する。
    func world(seed: UInt64, ore: Int = 8, charcoal: Int = 60, wood: Int = 20, limestone: Int = 20, water: Int = 40)
        -> WorldState
    {
        var ctx = StepContext(world: rig.factory.newWorld(seed: seed), content: content)
        ctx.addStock(.matter(.ironOre(purity: Self.orePurity(seed: seed))), ore, to: .base)
        ctx.addStock(.item(.charcoal), charcoal, to: .base)
        ctx.addStock(.item(.wood), wood, to: .base)
        ctx.addStock(.item(.limestone), limestone, to: .base)
        ctx.addStock(.item(.water), water, to: .base)
        ctx.world.research.unlocked.modules.formUnion(Self.unlocked)
        return ctx.world
    }

    /// 拠点の鉱石(掘ったままの塊)の山を指す。
    static func oreSelector(_ w: WorldState) -> StockSelector? {
        for e in w.inventory.entries(.base) {
            if case .matter(let m) = e.stuff, m.stage == .ore, m.shape == .lump, m.substance == .hematite, e.unique == nil {
                return StockSelector(holder: .base, stuff: e.stuff)
            }
        }
        return nil
    }

    static func oreCount(_ w: WorldState) -> Int {
        w.inventory.quantity(where: {
            if case .matter(let m) = $0 { m.stage == .ore && m.shape == .lump && m.substance == .hematite } else { false }
        })
    }

    func trial(_ steps: [ProcessStep], _ w: inout WorldState, quantity: Int = 1) -> StepReport {
        guard let sel = Self.oreSelector(w) else {
            XCTFail("鉱石が無い")
            return StepReport()
        }
        return rig.simulation.apply(.invention(.trial(input: sel, quantity: quantity, steps: steps)), to: &w)
    }
}

/// 名前の部品で見る目標(プレイヤーが名前を読んで分かること)。
enum Goal: CaseIterable {
    /// 精鉄板: 精(以上)の板で割れていない。剛・柔は問わない。
    case fine
    /// 剛鉄板: 剛の板。
    case hard

    var toward: NamePart { self == .fine ? .grade(.fine, .metal) : .temper(.hard) }

    func reached(_ n: MatterName) -> Bool {
        guard n.parts.contains(.shape(.plate)), n.parts.contains(.substance(.iron)) else { return false }
        switch self {
        case .fine: return (n.grade == .fine || n.grade == .pure) && n.temper != .cracked
        case .hard: return n.temper == .hard
        }
    }
}

func shorthand(_ steps: [ProcessStep]) -> String {
    steps.map { s -> String in
        switch s.module {
        case .minehead: "掘"
        case .millstone: "砕"
        case .sluice: "洗"
        case .mixingBowl: "混"
        case .furnace: s.inputItems == [.wood] ? "熱(薪)" : "熱(炭)"
        case .anvil: "叩"
        case .quenchTank: "冷"
        default: s.module.rawValue
        }
    }.joined(separator: "→")
}
