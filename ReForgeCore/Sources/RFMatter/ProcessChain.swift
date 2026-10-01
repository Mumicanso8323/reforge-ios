import RFKernel

/// 工程の 1 段(設計画面の 1 行)。
public struct ProcessStep: Codable, Hashable, Sendable {
    public var module: ModuleKind
    /// その段に入れる物(炉の燃料・混ぜ鉢の混ぜ物)。要らない段は nil。
    public var input: ItemID?

    public init(_ module: ModuleKind, input: ItemID? = nil) {
        self.module = module
        self.input = input
    }

    public static let minehead = ProcessStep(.minehead)
    public static let millstone = ProcessStep(.millstone)
    public static let sluice = ProcessStep(.sluice)
    public static let lime = ProcessStep(.mixingBowl, input: .limestone)
    public static let charcoalFurnace = ProcessStep(.furnace, input: .charcoal)
    public static let woodFurnace = ProcessStep(.furnace, input: .wood)
    public static let anvil = ProcessStep(.anvil)
    public static let quench = ProcessStep(.quenchTank)
}

/// 段に入れた物の条件。
public enum InputMatch: Codable, Hashable, Sendable {
    /// 何も入れていない。
    case absent
    /// この物を入れた。
    case item(ItemID)
}

/// 段の位置の条件。
public enum StepPosition: String, Codable, Hashable, Sendable {
    case first
    case notFirst
}

/// 規則が当たる条件。nil の項目は問わない。全項目が合えば当たる。
public struct RuleCondition: Codable, Hashable, Sendable {
    public var stage: MatterStage?
    public var shapes: [Shape]?
    public var thermal: [ThermalState]?
    public var worked: Bool?
    public var tempers: [Temper]?
    /// この混ぜ物を抱えている。
    public var carries: ItemID?
    public var input: InputMatch?
    public var position: StepPosition?

    public init(
        stage: MatterStage? = nil, shapes: [Shape]? = nil, thermal: [ThermalState]? = nil, worked: Bool? = nil,
        tempers: [Temper]? = nil, carries: ItemID? = nil, input: InputMatch? = nil, position: StepPosition? = nil
    ) {
        self.stage = stage
        self.shapes = shapes
        self.thermal = thermal
        self.worked = worked
        self.tempers = tempers
        self.carries = carries
        self.input = input
        self.position = position
    }

    public static let any = RuleCondition()

    func matches(_ m: Matter, step: ProcessStep, index: Int) -> Bool {
        if let stage, m.stage != stage { return false }
        if let shapes, !shapes.contains(m.shape) { return false }
        if let thermal, !thermal.contains(m.thermal) { return false }
        if let worked, m.worked != worked { return false }
        if let tempers, !tempers.contains(m.temper) { return false }
        if let carries, !m.additives.contains(carries) { return false }
        switch input {
        case .none: break
        case .absent?: if step.input != nil { return false }
        case .item(let id)?: if step.input != id { return false }
        }
        switch position {
        case .none: break
        case .first?: if index != 0 { return false }
        case .notFirst?: if index == 0 { return false }
        }
        return true
    }
}

/// 所見の引数をどこから取るか。
public enum FindingArgSource: String, Codable, Hashable, Sendable {
    /// 段に入れた物(燃料・混ぜ物)。
    case stepInput
    /// 段のモジュール。
    case module
    /// その時点の形。
    case shape
    /// その時点の純度。
    case purity
    /// その時点の剛・柔・割れ。
    case temper
}

/// 規則が起こすこと。並べた順に当てる。
public enum RuleEffect: Codable, Hashable, Sendable {
    /// レシピの式で純度を変える(抱えている混ぜ物がレシピのフラックスなら加算も)。
    case applyRecipe(RecipeID)
    /// 段階と主成分を変える(鉱石 → 鉄)。
    case becomes(MatterStage, SubstanceID)
    case setShape(Shape)
    case setThermal(ThermalState)
    case setWorked(Bool)
    case setTemper(Temper)
    /// 段に入れた物を混ぜ物として抱える。
    case carryStepInput
    /// 抱えている混ぜ物を全部なくす。
    case dropAdditives
    case byproduct(ByproductID)
    /// 材料を使う。
    case consume(ItemID, Int)
    /// 段に入れた物を使う(入れていなければ何もしない)。
    case consumeStepInput(Int)
    /// 所見をノートに載せる。
    case finding(FindingID, [FindingArgSource])
}

/// 規則 1 行。
public struct ModuleRule: Codable, Hashable, Sendable {
    public var when: RuleCondition
    public var then: [RuleEffect]

    public init(when: RuleCondition, then: [RuleEffect]) {
        self.when = when
        self.then = then
    }
}

/// 硬さ・粘りの表の 1 行。
public struct MetricRule: Codable, Hashable, Sendable {
    public var when: RuleCondition
    /// 硬さ(0〜100 の指数)。
    public var hardness: Int
    /// 粘り(0〜100 の指数)。
    public var toughness: Int

    public init(when: RuleCondition, hardness: Int, toughness: Int) {
        self.when = when
        self.hardness = hardness
        self.toughness = toughness
    }
}

/// 規則の表。モジュールの効きはすべてここにあり、コードは表を引くだけ。
/// モジュールを足すときは `modules` に ID と規則を足す(各モジュールの規則は上から最初に当たった 1 行だけが効く)。
public struct RuleBook: Codable, Hashable, Sendable {
    public var modules: [ModuleKind: [ModuleRule]]
    /// 並びの最後に当てる規則(熱いまま残った物が空気で冷える)。
    public var finish: [ModuleRule]
    /// 硬さ・粘りの表(上から最初に当たった行)。
    public var metrics: [MetricRule]
    public var recipes: RecipeBook

    public init(modules: [ModuleKind: [ModuleRule]], finish: [ModuleRule], metrics: [MetricRule], recipes: RecipeBook) {
        self.modules = modules
        self.finish = finish
        self.metrics = metrics
        self.recipes = recipes
    }
}

/// 所見の引数。
public enum FindingArg: Codable, Hashable, Sendable {
    case item(ItemID)
    case module(ModuleKind)
    case shape(Shape)
    case purity(Purity)
    case temper(Temper)
}

/// 所見(実験ノートの 1 行の材料)。文は持たない。
public struct Finding: Codable, Hashable, Sendable {
    public var id: FindingID
    /// 何段目で起きたか(0 始まり。並びの最後の冷え方なら nil)。
    public var step: Int?
    public var args: [FindingArg]

    public init(id: FindingID, step: Int?, args: [FindingArg] = []) {
        self.id = id
        self.step = step
        self.args = args
    }
}

/// 使った材料の量。
public struct ItemAmount: Codable, Hashable, Sendable {
    public var item: ItemID
    public var quantity: Int

    public init(_ item: ItemID, _ quantity: Int) {
        self.item = item
        self.quantity = quantity
    }
}

/// 1 段ごとの記録(ノートの略記「砕→洗→熱→叩」と途中の見込み用)。
public struct StepTrace: Codable, Hashable, Sendable {
    public var step: ProcessStep
    /// 当たった規則の行番号(当たらなければ nil)。
    public var ruleIndex: Int?
    /// その段を通った後の物。
    public var after: Matter
}

/// 試作 1 回の結果。
public struct ChainResult: Codable, Hashable, Sendable {
    public var product: Matter
    public var name: MatterName
    /// 硬さ(0〜100 の指数。純度の効きは掛けていない。性能は `PurityMath.effect` を掛けて出す)。
    public var hardness: Int
    /// 粘り(0〜100 の指数)。
    public var toughness: Int
    /// 副産物(出た順。同じ物が 2 回出れば 2 つ)。
    public var byproducts: [ByproductID]
    public var findings: [Finding]
    /// 使った材料(ID 順。最初の鉱石は含まない)。
    public var consumed: [ItemAmount]
    public var trace: [StepTrace]
}

/// 連結の工程(発明の核)。モジュールの並びと入力の物から結果を出す純関数。
///
/// 原作の `ProcessingChain` は段数で量が増えるだけで性質は変わらなかった。ここは order.md §5.4 と
/// game-design.md §2・§6 の設計から新しく作った。規則は `RuleBook`(データ)にあり、既定は `RuleBook.r1`。
public enum ProcessChain {
    public static func run(_ steps: [ProcessStep], input: Matter, rules: RuleBook = .r1) -> ChainResult {
        var m = input
        var byproducts: [ByproductID] = []
        var findings: [Finding] = []
        var consumed: [ItemID: Int] = [:]
        var trace: [StepTrace] = []

        func apply(_ effects: [RuleEffect], step: ProcessStep?, index: Int?) {
            for e in effects {
                switch e {
                case .applyRecipe(let id):
                    guard let r = rules.recipes[id] else { continue }
                    let hasFlux = r.fluxItem.map { m.additives.contains($0) } ?? false
                    m.purity = r.outputPurity(inputPurities: [m.purity], hasFlux: hasFlux)
                case .becomes(let stage, let substance):
                    m.stage = stage
                    m.substance = substance
                case .setShape(let s): m.shape = s
                case .setThermal(let t): m.thermal = t
                case .setWorked(let w): m.worked = w
                case .setTemper(let t): m.temper = t
                case .carryStepInput:
                    if let item = step?.input { m.addAdditive(item) }
                case .dropAdditives: m.additives = []
                case .byproduct(let b): byproducts.append(b)
                case .consume(let item, let n): consumed[item, default: 0] += n
                case .consumeStepInput(let n):
                    if let item = step?.input { consumed[item, default: 0] += n }
                case .finding(let id, let sources):
                    let args: [FindingArg] = sources.compactMap { src in
                        switch src {
                        case .stepInput: return step?.input.map(FindingArg.item)
                        case .module: return step.map { FindingArg.module($0.module) }
                        case .shape: return .shape(m.shape)
                        case .purity: return .purity(m.purity)
                        case .temper: return .temper(m.temper)
                        }
                    }
                    findings.append(Finding(id: id, step: index, args: args))
                }
            }
        }

        for (i, step) in steps.enumerated() {
            guard let table = rules.modules[step.module] else {
                findings.append(Finding(id: .unknownModule, step: i, args: [.module(step.module)]))
                trace.append(StepTrace(step: step, ruleIndex: nil, after: m))
                continue
            }
            let hit = table.firstIndex { $0.when.matches(m, step: step, index: i) }
            if let hit {
                apply(table[hit].then, step: step, index: i)
            } else {
                findings.append(Finding(id: .noEffect, step: i, args: [.module(step.module), .shape(m.shape)]))
            }
            trace.append(StepTrace(step: step, ruleIndex: hit, after: m))
        }

        if let end = rules.finish.first(where: { $0.when.matches(m, step: ProcessStep(.minehead), index: steps.count) }) {
            apply(end.then, step: nil, index: nil)
        }

        let metric = rules.metrics.first { $0.when.matches(m, step: ProcessStep(.minehead), index: steps.count) }
        return ChainResult(
            product: m,
            name: NameGenerator.name(for: m),
            hardness: metric?.hardness ?? 0,
            toughness: metric?.toughness ?? 0,
            byproducts: byproducts,
            findings: findings,
            consumed: consumed.map { ItemAmount($0.key, $0.value) }.sorted { $0.item < $1.item },
            trace: trace)
    }
}
