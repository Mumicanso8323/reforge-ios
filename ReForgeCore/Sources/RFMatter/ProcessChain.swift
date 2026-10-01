/// 工程の 1 段(設計画面の 1 行)。
public struct ProcessStep: Codable, Hashable, Sendable {
    public var module: ModuleKind
    /// その段に入れる物(炉の燃料・混ぜ鉢の混ぜ物・合金の相手)。複数取れる。要らない段は空。
    public var inputs: [RecipeLot]

    public init(_ module: ModuleKind, inputs: [RecipeLot] = []) {
        self.module = module
        self.inputs = inputs
    }

    public init(_ module: ModuleKind, input: ItemID) {
        self.init(module, inputs: [RecipeLot(input)])
    }

    /// 入れた物の ID(並びは入れた順)。
    public var inputItems: [ItemID] { inputs.map(\.item) }

    enum CodingKeys: String, CodingKey { case module = "module", inputs = "inputs" }

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
    /// この物が入っている(ほかの物があってもよい)。
    case includes(ItemID)
    /// ちょうどこの物だけ(順は問わない)。
    case exactly([ItemID])

    enum CodingKeys: String, CodingKey { case absent = "absent", includes = "includes", exactly = "exactly" }
    enum IncludesCodingKeys: String, CodingKey { case _0 = "item" }
    enum ExactlyCodingKeys: String, CodingKey { case _0 = "items" }

    func matches(_ items: [ItemID]) -> Bool {
        switch self {
        case .absent: items.isEmpty
        case .includes(let id): items.contains(id)
        case .exactly(let ids): items.sorted() == ids.sorted()
        }
    }
}

/// 段の位置の条件。
public enum StepPosition: String, Codable, Hashable, Sendable {
    case first = "first"
    case notFirst = "not_first"
}

/// 特性の範囲の条件(両端を含む。nil の端は問わない)。
public struct TraitRange: Codable, Hashable, Sendable {
    public var trait: TraitID
    public var min: Int?
    public var max: Int?

    public init(_ trait: TraitID, min: Int? = nil, max: Int? = nil) {
        self.trait = trait
        self.min = min
        self.max = max
    }
}

/// 規則が当たる条件。nil の項目は問わない。全項目が合えば当たる。
public struct RuleCondition: Codable, Hashable, Sendable {
    public var stage: MatterStage?
    public var shapes: [Shape]?
    public var thermal: [ThermalState]?
    /// 叩いた回数の下限・上限(両端を含む)。
    public var workedMin: Int?
    public var workedMax: Int?
    public var tempers: [Temper]?
    /// この混ぜ物を抱えている。
    public var carries: ItemID?
    public var input: InputMatch?
    public var position: StepPosition?
    /// 特性の範囲(全部を満たす)。
    public var traits: [TraitRange]?

    public init(
        stage: MatterStage? = nil, shapes: [Shape]? = nil, thermal: [ThermalState]? = nil,
        workedMin: Int? = nil, workedMax: Int? = nil, tempers: [Temper]? = nil, carries: ItemID? = nil,
        input: InputMatch? = nil, position: StepPosition? = nil, traits: [TraitRange]? = nil
    ) {
        self.stage = stage
        self.shapes = shapes
        self.thermal = thermal
        self.workedMin = workedMin
        self.workedMax = workedMax
        self.tempers = tempers
        self.carries = carries
        self.input = input
        self.position = position
        self.traits = traits
    }

    public static let any = RuleCondition()

    func matches(_ m: Matter, step: ProcessStep?, index: Int) -> Bool {
        if let stage, m.stage != stage { return false }
        if let shapes, !shapes.contains(m.shape) { return false }
        if let thermal, !thermal.contains(m.thermal) { return false }
        if let workedMin, m.worked < workedMin { return false }
        if let workedMax, m.worked > workedMax { return false }
        if let tempers, !tempers.contains(m.temper) { return false }
        if let carries, !m.additives.contains(carries) { return false }
        if let input, !input.matches(step?.inputItems ?? []) { return false }
        switch position {
        case .none: break
        case .first?: if index != 0 { return false }
        case .notFirst?: if index == 0 { return false }
        }
        for r in traits ?? [] {
            let v = m.trait(r.trait)
            if let lo = r.min, v < lo { return false }
            if let hi = r.max, v > hi { return false }
        }
        return true
    }
}

/// 所見の引数をどこから取るか。
public enum FindingArgSource: String, Codable, Hashable, Sendable {
    /// 段に入れた物(燃料・混ぜ物。入れた物ごとに 1 つ)。
    case stepInput = "step_input"
    /// 段のモジュール。
    case module = "module"
    /// その時点の形。
    case shape = "shape"
    /// その時点の純度。
    case purity = "purity"
    /// その時点の剛・柔・割れ。
    case temper = "temper"
}

/// 規則が起こすこと。並べた順に当てる。
public enum RuleEffect: Codable, Hashable, Sendable {
    /// レシピの式で純度を変える(入力はこの物だけ。抱えている混ぜ物がレシピのフラックスなら加算も)。
    case applyRecipe(RecipeID)
    /// レシピの式で純度を変える(入力はこの物と、段に入れた物全部。原作 Execute と同じ平均。合金・混合用)。
    case applyRecipeWithInputs(RecipeID)
    /// 段階と主成分を変える(鉱石 → 鉄)。
    case becomes(MatterStage, SubstanceID)
    case setShape(Shape)
    case setThermal(ThermalState)
    /// 叩いた回数を加える。
    case addWorked(Int)
    case setTemper(Temper)
    /// この混ぜ物を抱える。
    case carry(ItemID)
    /// 抱えている混ぜ物を全部なくす。
    case dropAdditives
    case byproduct(ByproductID)
    /// 材料を使う。
    case consume(ItemID, Int)
    /// 段に入れた物をそれぞれの量だけ使う。
    case consumeStepInputs
    /// 特性を加減する。
    case addTrait(TraitID, Int)
    /// 特性を上書きする。
    case setTrait(TraitID, Int)
    /// 所見をノートに載せる。
    case finding(FindingID, [FindingArgSource])

    // 保存のキーを固定する(ケース名を変えても規則の表のデータが壊れないように)。
    enum CodingKeys: String, CodingKey {
        case applyRecipe = "apply_recipe", applyRecipeWithInputs = "apply_recipe_with_inputs"
        case becomes = "becomes", setShape = "set_shape", setThermal = "set_thermal", addWorked = "add_worked"
        case setTemper = "set_temper", carry = "carry", dropAdditives = "drop_additives", byproduct = "byproduct"
        case consume = "consume", consumeStepInputs = "consume_step_inputs", addTrait = "add_trait"
        case setTrait = "set_trait", finding = "finding"
    }
    enum ApplyRecipeCodingKeys: String, CodingKey { case _0 = "recipe" }
    enum ApplyRecipeWithInputsCodingKeys: String, CodingKey { case _0 = "recipe" }
    enum BecomesCodingKeys: String, CodingKey { case _0 = "stage", _1 = "substance" }
    enum SetShapeCodingKeys: String, CodingKey { case _0 = "shape" }
    enum SetThermalCodingKeys: String, CodingKey { case _0 = "thermal" }
    enum AddWorkedCodingKeys: String, CodingKey { case _0 = "count" }
    enum SetTemperCodingKeys: String, CodingKey { case _0 = "temper" }
    enum CarryCodingKeys: String, CodingKey { case _0 = "item" }
    enum ByproductCodingKeys: String, CodingKey { case _0 = "byproduct" }
    enum ConsumeCodingKeys: String, CodingKey { case _0 = "item", _1 = "quantity" }
    enum AddTraitCodingKeys: String, CodingKey { case _0 = "trait", _1 = "delta" }
    enum SetTraitCodingKeys: String, CodingKey { case _0 = "trait", _1 = "value" }
    enum FindingCodingKeys: String, CodingKey { case _0 = "id", _1 = "args" }
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
/// 書き出すときは `MatterCoding.encoder()`(キーを並べ替える)を使う。
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

    enum CodingKeys: String, CodingKey {
        case item = "item", module = "module", shape = "shape", purity = "purity", temper = "temper"
    }
    enum ItemCodingKeys: String, CodingKey { case _0 = "id" }
    enum ModuleCodingKeys: String, CodingKey { case _0 = "id" }
    enum ShapeCodingKeys: String, CodingKey { case _0 = "id" }
    enum PurityCodingKeys: String, CodingKey { case _0 = "value" }
    enum TemperCodingKeys: String, CodingKey { case _0 = "id" }
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
    /// 物が変わったか(変わらない段は「効果のない段」)。
    public var changed: Bool
}

/// 1 段を通した結果(`ProcessChain.advance`)。
public struct StepOutcome: Hashable, Sendable {
    public var matter: Matter
    public var ruleIndex: Int?
    public var byproducts: [ByproductID]
    public var findings: [Finding]
    public var consumed: [ItemAmount]
}

/// 試作 1 回の結果。
public struct ChainResult: Codable, Hashable, Sendable {
    public var product: Matter
    public var name: MatterName
    /// 硬さ(0〜100 の指数 + 特性 `hardness` の加減。純度の効きは掛けていない。性能は `PurityMath.effect` を掛ける)。
    public var hardness: Int
    /// 粘り(0〜100 の指数 + 特性 `toughness` の加減)。
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

        func absorb(_ o: StepOutcome) {
            m = o.matter
            byproducts += o.byproducts
            findings += o.findings
            for a in o.consumed { consumed[a.item, default: 0] += a.quantity }
        }

        for (i, step) in steps.enumerated() {
            let before = m
            let o = advance(m, through: step, at: i, rules: rules)
            absorb(o)
            trace.append(StepTrace(step: step, ruleIndex: o.ruleIndex, after: m, changed: m != before))
        }
        absorb(finish(m, rules: rules))

        let metric = rules.metrics.first { $0.when.matches(m, step: nil, index: steps.count) }
        return ChainResult(
            product: m,
            name: NameGenerator.name(for: m),
            hardness: (metric?.hardness ?? 0) + m.trait(.hardness),
            toughness: (metric?.toughness ?? 0) + m.trait(.toughness),
            byproducts: byproducts,
            findings: findings,
            consumed: consumed.map { ItemAmount($0.key, $0.value) }.sorted { $0.item < $1.item },
            trace: trace)
    }

    /// 1 段だけ通す(設計画面の途中の見込み・到達の数え上げ用)。`index` は並びの中の位置(0 始まり)。
    public static func advance(_ matter: Matter, through step: ProcessStep, at index: Int, rules: RuleBook = .r1)
        -> StepOutcome
    {
        guard let table = rules.modules[step.module] else {
            return StepOutcome(
                matter: matter, ruleIndex: nil, byproducts: [],
                findings: [Finding(id: .unknownModule, step: index, args: [.module(step.module)])], consumed: [])
        }
        guard let hit = table.firstIndex(where: { $0.when.matches(matter, step: step, index: index) }) else {
            return StepOutcome(
                matter: matter, ruleIndex: nil, byproducts: [],
                findings: [Finding(id: .noEffect, step: index, args: [.module(step.module), .shape(matter.shape)])],
                consumed: [])
        }
        var o = apply(table[hit].then, to: matter, step: step, index: index, rules: rules)
        o.ruleIndex = hit
        return o
    }

    /// 並びの最後の規則(熱いまま残った物の冷え方)を当てる。
    public static func finish(_ matter: Matter, rules: RuleBook = .r1) -> StepOutcome {
        guard let end = rules.finish.first(where: { $0.when.matches(matter, step: nil, index: -1) }) else {
            return StepOutcome(matter: matter, ruleIndex: nil, byproducts: [], findings: [], consumed: [])
        }
        return apply(end.then, to: matter, step: nil, index: nil, rules: rules)
    }

    static func apply(_ effects: [RuleEffect], to matter: Matter, step: ProcessStep?, index: Int?, rules: RuleBook)
        -> StepOutcome
    {
        var m = matter
        var byproducts: [ByproductID] = []
        var findings: [Finding] = []
        var consumed: [ItemAmount] = []
        for e in effects {
            switch e {
            case .applyRecipe(let id):
                guard let r = rules.recipes[id] else { continue }
                let hasFlux = r.fluxItem.map { m.additives.contains($0) } ?? false
                m.purity = r.outputPurity(inputPurities: [m.purity], hasFlux: hasFlux)
            case .applyRecipeWithInputs(let id):
                guard let r = rules.recipes[id] else { continue }
                let lots = step?.inputs ?? []
                let hasFlux = r.fluxItem.map { f in m.additives.contains(f) || lots.contains { $0.item == f } } ?? false
                let main = [m.purity] + lots.filter { $0.item != r.fluxItem }.map(\.purity)
                m.purity = r.outputPurity(inputPurities: main, hasFlux: hasFlux)
            case .becomes(let stage, let substance):
                m.stage = stage
                m.substance = substance
            case .setShape(let s): m.shape = s
            case .setThermal(let t): m.thermal = t
            case .addWorked(let n): m.worked += n
            case .setTemper(let t): m.temper = t
            case .carry(let item): m.addAdditive(item)
            case .dropAdditives: m.additives = []
            case .byproduct(let b): byproducts.append(b)
            case .consume(let item, let n): consumed.append(ItemAmount(item, n))
            case .consumeStepInputs:
                consumed += (step?.inputs ?? []).map { ItemAmount($0.item, $0.quantity) }
            case .addTrait(let t, let d): m.traits[t, default: 0] += d
            case .setTrait(let t, let v): m.traits[t] = v
            case .finding(let id, let sources):
                var args: [FindingArg] = []
                for src in sources {
                    switch src {
                    case .stepInput: args += (step?.inputItems ?? []).map(FindingArg.item)
                    case .module: if let step { args.append(.module(step.module)) }
                    case .shape: args.append(.shape(m.shape))
                    case .purity: args.append(.purity(m.purity))
                    case .temper: args.append(.temper(m.temper))
                    }
                }
                findings.append(Finding(id: id, step: index, args: args))
            }
        }
        return StepOutcome(matter: m, ruleIndex: nil, byproducts: byproducts, findings: findings, consumed: consumed)
    }
}
