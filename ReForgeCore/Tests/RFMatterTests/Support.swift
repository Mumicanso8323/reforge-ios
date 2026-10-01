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
            case .temper(.hard): s += "剛"
            case .temper(.soft): s += "柔"
            case .temper(.cracked): cracked = true
            case .temper(.none): break
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
}

/// 6 種の工程(採掘口は並びの先頭に固定)。炉は燃料 2 通り。
enum ChainSpace {
    static let kinds: [[ProcessStep]] = [
        [.millstone], [.sluice], [.lime], [.woodFurnace, .charcoalFurnace], [.anvil], [.quench],
    ]

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

    /// 同じ種類の繰り返しも許す並び(長さ 1〜maxLength)。
    static func withRepeats(maxLength: Int) -> [[ProcessStep]] {
        let variants = kinds.flatMap { $0 }
        var out: [[ProcessStep]] = []
        var frontier: [[ProcessStep]] = [[]]
        for _ in 1...maxLength {
            frontier = frontier.flatMap { p in variants.map { p + [$0] } }
            out += frontier.map { [.minehead] + $0 }
        }
        return out
    }
}

extension ChainResult {
    /// 精鉄板: 純度 85% 以上の板(割れていない。剛・柔は問わない)。
    var isFinePlate: Bool {
        product.stage == .metal && product.shape == .plate && product.temper != .cracked
            && product.purity >= Purity(percent: 85)
    }

    /// 剛鉄板: 剛の板。
    var isHardPlate: Bool {
        product.stage == .metal && product.shape == .plate && product.temper == .hard
    }
}

func shorthand(_ steps: [ProcessStep]) -> String {
    steps.map { s -> String in
        switch s.module {
        case .minehead: "掘"
        case .millstone: "砕"
        case .sluice: "洗"
        case .mixingBowl: "混"
        case .furnace: s.input == .wood ? "熱(薪)" : "熱(炭)"
        case .anvil: "叩"
        case .quenchTank: "冷"
        default: s.module.rawValue
        }
    }.joined(separator: "→")
}
