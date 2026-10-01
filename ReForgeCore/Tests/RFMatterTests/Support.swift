import RFKernel
import RFMatter

/// テスト用の文字列化(認識の層の代わり。語の表はここだけに置く)。
struct TestNameRenderer: NameRendering {
    func render(_ name: MatterName) -> String {
        var cracked = false
        var s = ""
        for part in name.parts {
            switch part {
            case .extreme(.poor): s += "粗悪な"
            case .grade(let g, let c): s += Self.gradeWord(g, c)
            case .temper(let t):
                if t == .hard { s += "剛" } else if t == .soft { s += "柔" } else if t == .cracked { cracked = true }
            case .proper(let id): s += Self.proper[id] ?? id.rawValue
            case .substance(let id): s += Self.substance[id] ?? id.rawValue
            case .shape(let sh): s += Self.shape[sh] ?? sh.rawValue
            }
        }
        return cracked ? "割れた" + s : s
    }

    static func gradeWord(_ g: PurityGrade, _ c: MaterialCategory) -> String {
        switch (g, c) {
        case (.crude, .chemical): "希"
        case (.fine, .chemical): "濃"
        case (.crude, .liquid): "汚"
        case (.fine, .liquid): "清"
        case (.fine, .organic): "上"
        case (.pure, .organic): "極"
        case (.fine, .granular): "細"
        case (.pure, .granular): "微"
        case (.crude, _): "粗"
        case (.fine, _): "精"
        case (.pure, _): "純"
        default: ""
        }
    }

    static let proper: [ProperNameID: String] = [
        .pureIron: "純鉄", .steel: "鋼", .hardSteel: "硬鋼", .mildSteel: "軟鋼", .hematite: "赤鉄鉱",
        .ironRod: "鉄棒", .silicaSand: "珪砂", .crudeCopper: "粗銅", .electrolyticCopper: "電気銅",
    ]
    static let substance: [SubstanceID: String] = [.iron: "鉄", "Cu": "銅", .silica: "二酸化ケイ素"]
    static let shape: [Shape: String] = [.lump: "塊", .plate: "板", .dust: "粉", .ingot: "塊", .rod: "棒"]
}

extension MatterName {
    var text: String { rendered(by: TestNameRenderer()) }
}

extension Matter {
    static func iron(_ bp: Int, _ shape: Shape = .lump, temper: Temper = .none) -> Matter {
        Matter(substance: .iron, purity: Purity(basisPoints: bp), stage: .metal, shape: shape, temper: temper)
    }

    /// 精鉄板: 純度 85% 以上の板(割れていない。剛・柔は問わない)。
    var isFinePlate: Bool {
        stage == .metal && shape == .plate && temper != .cracked && purity >= Purity(percent: 85)
    }

    /// 剛鉄板: 剛の板。
    var isHardPlate: Bool { stage == .metal && shape == .plate && temper == .hard }
}

extension ChainResult {
    var isFinePlate: Bool { product.isFinePlate }
    var isHardPlate: Bool { product.isHardPlate }
    /// 効果のない段を除いた並び(採掘口は残す)。
    var reducedSteps: [ProcessStep] {
        trace.enumerated().filter { $0.offset == 0 || $0.element.changed }.map(\.element.step)
    }
}

/// 6 種の工程(採掘口は並びの先頭に固定)。炉は燃料 2 通りで、段の種類は 7。
enum ChainSpace {
    static let kinds: [[ProcessStep]] = [
        [.millstone], [.sluice], [.lime], [.woodFurnace, .charcoalFurnace], [.anvil], [.quench],
    ]
    static let variants = kinds.flatMap { $0 }

    /// 各種類を高々 1 回ずつ、順番を問う並び(長さ 1〜6)。採掘口を先頭に付けて返す。
    static func distinctOrders() -> [[ProcessStep]] {
        var out: [[ProcessStep]] = []
        func walk(_ prefix: [ProcessStep], _ used: Set<Int>) {
            if !prefix.isEmpty { out.append([.minehead] + prefix) }
            for k in kinds.indices where !used.contains(k) {
                for variant in kinds[k] { walk(prefix + [variant], used.union([k])) }
            }
        }
        walk([], [])
        return out
    }

    struct Count {
        var total = 0
        var fine = 0
        var hard = 0
        var both = 0
    }

    /// 繰り返しを許す並び(長さ 1〜maxLength、7^1 + … + 7^maxLength 通り)を、物の状態ごとにまとめて数える。
    static func countWithRepeats(maxLength: Int, ore: Matter) -> Count {
        var states: [Matter: Int] = [ProcessChain.advance(ore, through: .minehead, at: 0).matter: 1]
        var c = Count()
        for len in 1...maxLength {
            var next: [Matter: Int] = [:]
            for (m, n) in states {
                for v in variants { next[ProcessChain.advance(m, through: v, at: len).matter, default: 0] += n }
            }
            states = next
            for (m, n) in states {
                let p = ProcessChain.finish(m).matter
                c.total += n
                if p.isFinePlate { c.fine += n }
                if p.isHardPlate { c.hard += n }
                if p.isFinePlate && p.isHardPlate { c.both += n }
            }
        }
        return c
    }

    /// 精鉄板に届く「本質的に違う道」: 効果のある段だけでできた並びのうち、どの 1 段を抜いても届かなくなるもの。
    /// 効果のない段を挟んだ変種や、届いた後に余計な段を足した変種は数えない。
    static func essentialFinePaths(maxLength: Int, ore: Matter) -> [[ProcessStep]] {
        var reaching: [[ProcessStep]] = []
        func walk(_ m: Matter, _ path: [ProcessStep]) {
            if ProcessChain.finish(m).matter.isFinePlate { reaching.append(path) }
            guard path.count - 1 < maxLength else { return }
            for v in variants {
                let next = ProcessChain.advance(m, through: v, at: path.count).matter
                if next != m { walk(next, path + [v]) }
            }
        }
        walk(ProcessChain.advance(ore, through: .minehead, at: 0).matter, [.minehead])
        return reaching.filter { path in
            (1..<path.count).allSatisfy { i in
                var shorter = path
                shorter.remove(at: i)
                return !ProcessChain.run(shorter, input: ore).isFinePlate
            }
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
