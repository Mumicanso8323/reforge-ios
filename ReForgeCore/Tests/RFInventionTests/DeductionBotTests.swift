import Foundation
import RFContent
import RFInvention
import RFKernel
import RFMatter
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// TEST-R1-01 推理ボット(order.md §5.8)。
///
/// 推理ボットは、ノートに載った事実(試作の並び・結果の名前・所見・工程表の見込み)と、その時点でノートに載っている
/// 手がかり(主張 claims)だけを使い、仮説(並び)の消去で次に試す並びを決める。試作は本体のコマンドで行い、
/// 手持ちの鉱石 8 個(= 8 回分)を実際に使う。
///
/// - 推理ボット: seed 0〜99 の全部で、鉱石 8 回分以内に精鉄板と剛鉄板の両方に届く。
/// - 同じ予算の総当たり(並びを短い順・パレット順に試す)と無作為は、両方に届くのが 2 割以下。
/// - 手がかりを全部外した推理ボットも、両方に届くのが 2 割以下(手がかりが効いていることの確認)。
final class DeductionBotTests: XCTestCase {
    static let seeds: [UInt64] = Array(0..<100)

    func testReasoningBotReachesBothWithinEightOres() throws {
        let fx = try InventionFixture()
        var used: [Int] = []
        for seed in Self.seeds {
            let run = BotHarness(fx: fx).play(seed: seed, policy: DeductionBot(clues: .all, seed: seed))
            XCTAssertTrue(run.fine && run.hard, "seed \(seed): \(run.log.joined(separator: " / "))")
            XCTAssertLessThanOrEqual(run.trials, 8)
            used.append(run.trials)
        }
        let mean = Double(used.reduce(0, +)) / Double(used.count)
        print("[TEST-R1-01] 推理ボット: 100 seed 全部で両方に届いた。使った鉱石 平均 \(String(format: "%.2f", mean))・最大 \(used.max() ?? 0)")
    }

    func testBruteForceRandomAndCluelessBotsMostlyFail() throws {
        let fx = try InventionFixture()
        let harness = BotHarness(fx: fx)
        func rate(seeds: [UInt64] = Self.seeds, _ make: (UInt64) -> any TrialPolicy)
            -> (both: Double, fine: Double, hard: Double)
        {
            var both = 0, fine = 0, hard = 0
            for seed in seeds {
                let r = harness.play(seed: seed, policy: make(seed))
                if r.fine && r.hard { both += 1 }
                if r.fine { fine += 1 }
                if r.hard { hard += 1 }
            }
            let n = Double(seeds.count)
            return (Double(both) / n, Double(fine) / n, Double(hard) / n)
        }
        func show(_ label: String, _ r: (both: Double, fine: Double, hard: Double)) {
            print("[TEST-R1-01] \(label): 両方 \(Int(r.both * 100))% / 精鉄板 \(Int(r.fine * 100))% / 剛鉄板 \(Int(r.hard * 100))%")
        }

        let brute = rate { _ in BruteForceBot() }
        let random = rate { RandomBot(seed: $0) }
        let clueless = rate { DeductionBot(clues: [], seed: $0) }
        show("総当たり", brute)
        show("無作為", random)
        show("手がかりなしの推理", clueless)
        XCTAssertLessThanOrEqual(brute.both, 0.2)
        XCTAssertLessThanOrEqual(random.both, 0.2)
        XCTAssertLessThanOrEqual(clueless.both, 0.2)

        // 参考: 導線を 1 つずつ外したとき(合否は見ない。どの導線がどれだけ効いているかの記録。seed 0〜19)
        for (label, clues) in [("所見なし", Clues.all.subtracting(.findings)), ("手がかりの文なし", Clues.all.subtracting(.hints)),
                               ("図鑑の空欄なし", Clues.all.subtracting(.codex)), ("ノアの手なし", Clues.all.subtracting(.hand)),
                               ("所見だけ", Clues.findings)] {
            show("推理(\(label)・20 seed)", rate(seeds: Array(0..<20)) { DeductionBot(clues: clues, seed: $0) })
        }
    }

    /// 手がかりは嘘をつかない: 目標ごとに、その目標(と全般)に向けた主張を全部満たし、本当に目標に届く並びがある。
    /// 露頭の鉱石 20〜35% のどれでも。図鑑の空欄の「段の意味」は名前の段の境目と一致する。
    /// 非公開のコンテンツがあれば、本物の手がかりも同じ検査を通す。
    func testHintsDoNotLie() throws {
        try assertHintsDoNotLie(InventionFixture().content)
        if TestContent.hasPrivateLayer { try assertHintsDoNotLie(TestContent.full()) }
    }

    func assertHintsDoNotLie(_ content: ContentDB, file: StaticString = #filePath, line: UInt = #line) {
        let claims = content.hints.values.flatMap { $0.claims ?? [] }
        for goal in Goal.allCases {
            let mine = claims.filter { $0.toward == nil || $0.toward == goal.toward }
            for pct in [20, 25, 30, 35] {
                let ore = Matter.ironOre(purity: Purity(percent: pct))
                let ok = SequenceSpace.withRepeats(maxLength: 8).contains { s in
                    mine.allSatisfy { $0.says.holds(in: s) ?? true }
                        && goal.reached(ProcessChain.run(s, input: ore, rules: content.ruleBook).name)
                }
                XCTAssertTrue(ok, "\(goal) \(pct)%: 主張を全部満たす並びで届かない", file: file, line: line)
            }
            for c in mine {
                if case .gradeMeans(let t) = c.says, case .grade(let g, let cat) = goal.toward {
                    XCTAssertEqual(PurityGrade.of(t, category: cat), g, file: file, line: line)
                    XCTAssertNotEqual(PurityGrade.of(Purity(basisPoints: t.basisPoints - 1), category: cat), g,
                                      file: file, line: line)
                }
            }
        }
    }
}

// MARK: - ボットの道具

/// 推理ボットが使ってよい導線(order.md §5.4 の 5 種のうち、ノートに載る 4 種と、ノアの手)。
struct Clues: OptionSet {
    let rawValue: Int
    /// 失敗知見(試作の所見)。
    static let findings = Clues(rawValue: 1)
    /// 手がかりの文(端末の断片・手が知っていた手順・仲間の案)。
    static let hints = Clues(rawValue: 2)
    /// 図鑑の空欄(命名からの類推)。
    static let codex = Clues(rawValue: 4)
    /// ノアの手(工程表の見込みの純度の見当)。
    static let hand = Clues(rawValue: 8)
    static let all: Clues = [.findings, .hints, .codex, .hand]
}

protocol TrialPolicy {
    /// 次に試す並び(試すものが無ければ nil)。見てよいのはノートと手がかりの定義(文の意味)だけ。
    mutating func next(_ w: WorldState, _ content: ContentDB) -> [ProcessStep]?
}

/// 並びの集合(採掘口は付けない。試作は手持ちの鉱石から始める)。
enum SequenceSpace {
    /// パレットの並び(設計画面の下に並ぶ順)。
    static let palette: [ProcessStep] = [.millstone, .sluice, .lime, .woodFurnace, .charcoalFurnace, .anvil, .quench]
    static let kinds: [[ProcessStep]] = [[.millstone], [.sluice], [.lime], [.woodFurnace, .charcoalFurnace], [.anvil], [.quench]]

    /// 各種類を高々 1 回ずつ、順番を問う並び(長さ 1〜6、3,587 通り)。短い順・パレット順。
    static let distinct: [[ProcessStep]] = {
        var out: [[ProcessStep]] = []
        func walk(_ prefix: [ProcessStep], _ used: Set<Int>) {
            if !prefix.isEmpty { out.append(prefix) }
            for k in kinds.indices where !used.contains(k) {
                for v in kinds[k] { walk(prefix + [v], used.union([k])) }
            }
        }
        walk([], [])
        let rank = Dictionary(uniqueKeysWithValues: palette.enumerated().map { ($1, $0) })
        return out.sorted { a, b in
            if a.count != b.count { return a.count < b.count }
            return a.map { rank[$0]! }.lexicographicallyPrecedes(b.map { rank[$0]! })
        }
    }()

    /// 段 → パレットの番号、並び → 番号、並びに含む段のビット。
    static let code: [ProcessStep: Int] = Dictionary(uniqueKeysWithValues: palette.enumerated().map { ($1, $0) })
    static let index: [[ProcessStep]: Int] = Dictionary(uniqueKeysWithValues: distinct.enumerated().map { ($1, $0) })
    static let bits: [Int] = distinct.map { $0.reduce(0) { $0 | 1 << code[$1]! } }

    /// 繰り返しを許す並びのうち、効果のある段だけでできたもの(長さ maxLength まで。主張の検査用)。
    static func withRepeats(maxLength: Int) -> [[ProcessStep]] {
        var out: [[ProcessStep]] = []
        func walk(_ m: Matter, _ path: [ProcessStep]) {
            if !path.isEmpty { out.append(path) }
            guard path.count < maxLength else { return }
            for v in palette {
                let next = ProcessChain.advance(m, through: v, at: path.count).matter
                if next != m { walk(next, path + [v]) }
            }
        }
        walk(.ironOre(purity: Purity(percent: 30)), [])
        return out
    }
}

/// 推理ボット。仮説 = 並び(各種類 1 回まで)。ノートの事実と手がかりで消し、残りから選ぶ。
struct DeductionBot: TrialPolicy {
    let clues: Clues
    var rng: SeededRandom

    init(clues: Clues, seed: UInt64) {
        self.clues = clues
        self.rng = SeededRandom(state: seed &* 0x9E37_79B9 &+ 0xB07)
    }

    typealias Rule = ([ProcessStep]) -> Bool

    mutating func next(_ w: WorldState, _ content: ContentDB) -> [ProcessStep]? {
        let trials = w.notebook.trials
        let unmet = Goal.allCases.filter { g in !trials.contains { g.reached($0.outcome.name) } }
        guard !unmet.isEmpty else { return nil }

        // 1. 失敗知見: 所見の文を読んで、その段が無駄・害になる並びを消す(ノートは規則をまとめないので、ボットがまとめる)
        var masks: [[Bool]] = []
        if clues.contains(.findings) {
            var seen: Set<Finding> = []
            for t in trials {
                for f in t.outcome.findings {
                    let key = Finding(id: f.id, step: nil, args: f.args)
                    if seen.insert(key).inserted { masks.append(SpaceCache.mask(for: key)) }
                }
            }
        }

        // 2・3・4. 手がかりの文・仲間の案・図鑑の空欄: ノートに載っている手がかりの主張
        var goalMasks: [Goal: [[Bool]]] = [:]
        for note in w.notebook.notes {
            guard let id = note.hint, let def = content.hints[id] else { continue }
            guard clues.contains(def.target != nil ? .codex : .hints) else { continue }
            for c in def.claims ?? [] {
                for g in Goal.allCases where c.toward == nil || c.toward == g.toward {
                    goalMasks[g, default: []].append(SpaceCache.mask(for: c.says))
                }
            }
        }

        // 5. ノアの手: 試作の工程表の見込み(純度の見当)で、純度を上げた段を覚える
        var useful = 0
        if clues.contains(.hand) {
            for t in trials {
                guard let sheet = Sheets.model(.trial(t.record), world: w, content: content) else { continue }
                var prev = sheet.head?.sensed ?? .zero
                for row in sheet.rows {
                    guard let f = row.forecast, let s = row.step else { continue }
                    if f.sensed > prev, let code = SequenceSpace.code[s] { useful |= 1 << code }
                    prev = f.sensed
                }
            }
        }

        // 残った仮説から、まだ届いていない目標の多くに合い、純度を上げた段を多く含み、長い(一度に多く確かめる)並びを選ぶ
        let tried = Set(trials.compactMap { SequenceSpace.index[$0.steps] })
        var best: [Int] = []
        var bestKey = (0, 0)
        for i in SequenceSpace.distinct.indices where !tried.contains(i) && masks.allSatisfy({ $0[i] }) {
            let goals = unmet.filter { g in (goalMasks[g] ?? []).allSatisfy { $0[i] } }.count
            guard goals > 0 else { continue }
            let key = (goals, (SequenceSpace.bits[i] & useful).nonzeroBitCount * 10 + SequenceSpace.distinct[i].count)
            if key > bestKey {
                bestKey = key
                best = [i]
            } else if key == bestKey {
                best.append(i)
            }
        }
        if best.isEmpty { best = SequenceSpace.distinct.indices.filter { !tried.contains($0) } }
        guard !best.isEmpty else { return nil }
        return SequenceSpace.distinct[best[rng.int(below: best.count)]]
    }

    /// 所見 1 つから読み取れる「この並びは無駄・害がある」の規則(true = 残す)。
    static func rules(for f: Finding) -> [Rule] {
        func idx(_ s: [ProcessStep], _ m: ModuleKindID) -> Int? { s.firstIndex { $0.module == m } }
        func order(_ a: ModuleKindID, _ b: ModuleKindID) -> Rule {
            { s in
                guard let i = idx(s, a), let j = idx(s, b) else { return true }
                return i < j
            }
        }
        func needsBefore(_ a: ModuleKindID, _ b: ModuleKindID) -> Rule {
            { s in
                guard let j = idx(s, b) else { return true }
                guard let i = idx(s, a) else { return false }
                return i < j
            }
        }
        switch f.id {
        case .washLumpNoEffect: return [needsBefore(.millstone, .sluice)]  // 塊のままでは水が通らない → 先に砕く
        case .washMetalNoEffect: return [order(.sluice, .furnace)]
        case .washFluxWashedAway: return [order(.sluice, .mixingBowl)]  // 混ぜた石灰が流れた → 混ぜるのは洗いの後
        case .mixAfterSmeltNoEffect: return [order(.mixingBowl, .furnace)]
        case .crushMetalTooTough: return [order(.millstone, .furnace)]
        case .hammerOreNoEffect: return [needsBefore(.furnace, .anvil)]
        case .hammerCrackedAfterQuench: return [order(.anvil, .quenchTank)]
        case .quenchUnworkedNotHardened: return [needsBefore(.anvil, .quenchTank)]
        case .quenchOreNoEffect: return [needsBefore(.furnace, .quenchTank)]
        case .endedAsOre: return [{ s in s.contains(.charcoalFurnace) || s.contains(.woodFurnace) }]
        case .furnaceTooCool:
            let fuels = f.args.compactMap { if case .item(let i) = $0 { i } else { nil } }
            return [{ s in !s.contains { $0.module == .furnace && !Set($0.inputItems).isDisjoint(with: fuels) } }]
        default: return []
        }
    }
}

/// 規則・主張ごとの「残す並び」の表(seed をまたいで同じなので一度だけ計算する)。
enum SpaceCache {
    static var findings: [Finding: [Bool]] = [:]
    static var claims: [ClaimKind: [Bool]] = [:]

    static func mask(for f: Finding) -> [Bool] {
        if let m = findings[f] { return m }
        let rules = DeductionBot.rules(for: f)
        let m = SequenceSpace.distinct.map { s in rules.allSatisfy { $0(s) } }
        findings[f] = m
        return m
    }

    static func mask(for c: ClaimKind) -> [Bool] {
        if let m = claims[c] { return m }
        let m = SequenceSpace.distinct.map { c.holds(in: $0) ?? true }
        claims[c] = m
        return m
    }
}

/// 総当たり: 並びを短い順・パレット順に試す。
struct BruteForceBot: TrialPolicy {
    mutating func next(_ w: WorldState, _ content: ContentDB) -> [ProcessStep]? {
        let tried = Set(w.notebook.trials.map(\.steps))
        return SequenceSpace.distinct.first { !tried.contains($0) }
    }
}

/// 無作為: まだ試していない並びから seed で選ぶ。
struct RandomBot: TrialPolicy {
    var rng: SeededRandom
    init(seed: UInt64) { rng = SeededRandom(state: seed &* 0x2545_F491 &+ 0x7A3) }

    mutating func next(_ w: WorldState, _ content: ContentDB) -> [ProcessStep]? {
        let tried = Set(w.notebook.trials.compactMap { SequenceSpace.index[$0.steps] })
        let left = SequenceSpace.distinct.indices.filter { !tried.contains($0) }
        return left.isEmpty ? nil : SequenceSpace.distinct[left[rng.int(below: left.count)]]
    }
}

/// ボットを本体の上で走らせる。鉱石 8 個(= 8 回分)を持って始め、尽きるか両方に届くまで試す。
struct BotHarness {
    let fx: InventionFixture

    struct Run {
        var fine = false
        var hard = false
        var trials = 0
        var log: [String] = []
    }

    func play(seed: UInt64, policy: some TrialPolicy) -> Run {
        var policy = policy
        var w = fx.world(seed: seed, ore: 8)
        _ = fx.rig.simulation.runSteps(1, &w)  // 目覚めた直後(いつでも成り立つ手がかりが載る)
        var run = Run()
        while !(run.fine && run.hard), let sel = InventionFixture.oreSelector(w) {
            // 試作を重ねるうちに仲間との関係が深まる(人の担当の代わりに、3 回目の試作の前にランク 3 にする)
            if run.trials == 2 { w.people[InventionFixture.companion]?.relation.rank = 3 }
            guard let steps = policy.next(w, fx.content) else { break }
            let r = fx.rig.simulation.apply(.invention(.trial(input: sel, quantity: 1, steps: steps)), to: &w)
            guard r.rejection == nil, let t = w.notebook.trials.last else {
                run.log.append("断られた: \(r.rejection?.reason.rawValue ?? "?")")
                break
            }
            run.trials += 1
            run.fine = run.fine || Goal.fine.reached(t.outcome.name)
            run.hard = run.hard || Goal.hard.reached(t.outcome.name)
            run.log.append("\(shorthand(steps)) = \(t.outcome.name.parts) \(t.outcome.findings.map(\.id.rawValue))")
        }
        return run
    }
}
