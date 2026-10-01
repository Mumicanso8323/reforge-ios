import RFKernel
import Foundation

/// レシピに入れる 1 口(原作 `ItemStack` の、純度の計算に要る部分)。
public struct RecipeLot: Codable, Hashable, Sendable {
    public var item: ItemID
    public var quantity: Int
    public var purity: Purity

    /// 原作 `ItemStack` の純度の既定値は 100%。
    public init(_ item: ItemID, quantity: Int = 1, purity: Purity = .full) {
        self.item = item
        self.quantity = quantity
        self.purity = purity
    }
}

/// レシピの入力の定義。
public struct RecipeInput: Codable, Hashable, Sendable {
    public var item: ItemID
    public var quantity: Int

    public init(_ item: ItemID, _ quantity: Int = 1) {
        self.item = item
        self.quantity = quantity
    }
}

/// レシピ(原作 `Production/Recipe.cs`)。純度の計算だけを移植した。
///
/// 出力純度 = base × (1 − W) + 入力の平均純度 × W + 混ぜ物(フラックスがあるとき)、0〜100% に丸める。
/// 数値は万分率の整数で持つ(`inputPurityWeight` 3000 = W 0.3)。
public struct Recipe: Codable, Hashable, Sendable, Identifiable {
    public var id: RecipeID
    public var inputs: [RecipeInput]
    public var output: ItemID
    /// 基礎出力純度(入力純度 100%・フラックスなしのとき)。
    public var basePurity: Purity
    /// 入力純度が出力純度に効く係数 W(万分率。10000 = 入力の純度がそのまま出る)。
    public var inputPurityWeight: Int
    /// フラックス(石灰石など)。nil ならフラックスを取らない。
    public var fluxItem: ItemID?
    /// フラックスがあるときの純度の加算(絶対値)。
    public var fluxPurityBonus: Purity
    /// 火が要るか。
    public var requiresFire: Bool

    public init(
        id: RecipeID, inputs: [RecipeInput], output: ItemID, basePurity: Purity, inputPurityWeight: Int,
        fluxItem: ItemID? = nil, fluxPurityBonus: Purity = .zero, requiresFire: Bool = false
    ) {
        self.id = id
        self.inputs = inputs
        self.output = output
        self.basePurity = basePurity
        self.inputPurityWeight = min(max(inputPurityWeight, 0), 10000)
        self.fluxItem = fluxItem
        self.fluxPurityBonus = fluxPurityBonus
        self.requiresFire = requiresFire
    }

    /// 原作 `Recipe.Execute` と同じ判定: 必要な入力が全部そろっていなければ nil。
    /// 平均はフラックス以外の全入力(燃料・水を含む)で取る。
    public func execute(_ lots: [RecipeLot]) -> Purity? {
        for req in inputs {
            guard lots.contains(where: { $0.item == req.item && $0.quantity >= req.quantity }) else { return nil }
        }
        let hasFlux = fluxItem.map { f in lots.contains { $0.item == f && $0.quantity > 0 } } ?? false
        let main = lots.filter { $0.item != fluxItem }
        return outputPurity(inputPurities: main.map(\.purity), hasFlux: hasFlux)
    }

    /// 入力の純度の並びから出力純度を出す(入力が空なら平均を 100% とみなす。原作どおり)。
    /// 端数は万分率の 0.5 を切り上げる。
    public func outputPurity(inputPurities: [Purity], hasFlux: Bool) -> Purity {
        let n = max(inputPurities.count, 1)
        let sum = inputPurities.isEmpty ? 10000 : inputPurities.reduce(0) { $0 + $1.basisPoints }
        let w = inputPurityWeight
        let numerator = basePurity.basisPoints * (10000 - w) * n + sum * w
        let denominator = 10000 * n
        var bp = (numerator + denominator / 2) / denominator
        if hasFlux { bp += fluxPurityBonus.basisPoints }
        return Purity(basisPoints: bp)
    }
}

/// レシピの表。
public struct RecipeBook: Codable, Hashable, Sendable {
    public var recipes: [RecipeID: Recipe]

    public init(_ list: [Recipe]) {
        recipes = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    public subscript(_ id: RecipeID) -> Recipe? { recipes[id] }

    /// 原作 `src/ReForge.Core/Data/Json/recipes.json` の値(鉄の系統の工程に関わるもの)。
    public static let original = RecipeBook([
        Recipe(id: .charcoalSmelt, inputs: [RecipeInput(.ironOre), RecipeInput(.charcoal)], output: "molten_iron",
               basePurity: Purity(percent: 55), inputPurityWeight: 3000, requiresFire: true),
        Recipe(id: .basicSmelt, inputs: [RecipeInput(.ironOre), RecipeInput(.coal)], output: "molten_iron",
               basePurity: Purity(percent: 60), inputPurityWeight: 3000,
               fluxItem: .limestone, fluxPurityBonus: Purity(percent: 18)),
        Recipe(id: .fluxSmelt, inputs: [RecipeInput(.ironOre), RecipeInput(.coal), RecipeInput(.limestone)],
               output: "molten_iron", basePurity: Purity(percent: 78), inputPurityWeight: 2000),
        Recipe(id: .crush, inputs: [RecipeInput(.ironOre)], output: "crushed_iron",
               basePurity: Purity(percent: 70), inputPurityWeight: 4000),
        Recipe(id: .wash, inputs: [RecipeInput("crushed_iron"), RecipeInput(.water)], output: "refined_iron_dust",
               basePurity: Purity(percent: 85), inputPurityWeight: 3000),
        Recipe(id: .plateForge, inputs: [RecipeInput("iron_ingot"), RecipeInput("stone")], output: "iron_plate",
               basePurity: .zero, inputPurityWeight: 10000),
        Recipe(id: .castIronPlate, inputs: [RecipeInput("molten_iron")], output: "iron_plate",
               basePurity: .zero, inputPurityWeight: 10000),
        Recipe(id: .charcoalBurn, inputs: [RecipeInput(.wood, 3)], output: .charcoal,
               basePurity: Purity(percent: 80), inputPurityWeight: 1000, requiresFire: true),
    ])

    /// R1 の表 = 原作 + `RecipeOverride.r1` + `RecipeBook.r1Additions`。
    public static let r1 = original.applying(RecipeOverride.r1).adding(r1Additions)

    /// R1 で足したレシピ(原作の recipes.json に無いもの)。
    ///
    /// 叩き重ね(`r1_fold`): 熱し直した板をもう一度叩くと、残っていた滓が絞り出されて純度が上がる。
    /// base 94・W 0.5。石灰を使わずに精へ届く 2 本目の道のための値で、露頭の鉱石 20〜35% では
    /// 「砕く→洗う→炉→叩く→(熱し直す→叩く)×2」が 85% を越え(85.72〜85.85%)、
    /// 洗いを抜くと越えない(83.88〜84.33%)。叩き重ねは 2 回まで(規則の表で制限)。
    public static let r1Additions: [Recipe] = [
        Recipe(id: .fold, inputs: [RecipeInput("iron_plate")], output: "iron_plate",
               basePurity: Purity(percent: 94), inputPurityWeight: 5000, requiresFire: true),
    ]

    /// レシピを足した表を返す(同じ ID は置き換え)。
    public func adding(_ list: [Recipe]) -> RecipeBook {
        var copy = self
        for r in list { copy.recipes[r.id] = r }
        return copy
    }

    /// 差分を当てた表を返す(原作の値は書き換えない)。
    public func applying(_ overrides: [RecipeOverride]) -> RecipeBook {
        var copy = self
        for o in overrides {
            guard var r = copy.recipes[o.recipe] else { continue }
            if let v = o.basePurity { r.basePurity = v }
            if let v = o.inputPurityWeight { r.inputPurityWeight = v }
            if let v = o.fluxItem { r.fluxItem = v }
            if let v = o.fluxPurityBonus { r.fluxPurityBonus = v }
            copy.recipes[o.recipe] = r
        }
        return copy
    }
}

/// レシピの差分(order.md §5.6 の `r1-overrides.json` に当たる)。
public struct RecipeOverride: Codable, Hashable, Sendable {
    public var recipe: RecipeID
    public var basePurity: Purity?
    public var inputPurityWeight: Int?
    public var fluxItem: ItemID?
    public var fluxPurityBonus: Purity?
    /// 差分の理由(人が読む注記。表示には使わない)。
    public var reason: String

    public init(
        recipe: RecipeID, basePurity: Purity? = nil, inputPurityWeight: Int? = nil,
        fluxItem: ItemID? = nil, fluxPurityBonus: Purity? = nil, reason: String
    ) {
        self.recipe = recipe
        self.basePurity = basePurity
        self.inputPurityWeight = inputPurityWeight
        self.fluxItem = fluxItem
        self.fluxPurityBonus = fluxPurityBonus
        self.reason = reason
    }

    /// R1 の差分。
    ///
    /// 木炭炉(`charcoal_smelt`)は原作ではフラックスを取らない。order.md §5.4 は「混ぜ鉢(石灰石)を炉の前に」で
    /// `basic_smelt` の +18 を効かせるが、木炭炉の base 55・W 0.3 に +18 では、前処理を全部しても
    /// 55×0.7 + 85×0.3 + 18 = 82% が上限で、「精」(85%)に届かない。
    /// そこで木炭炉に石灰石のフラックスを持たせ、加算を +25 にする。
    /// 鉱石 30〜60% のどれでも「砕く→洗う→混ぜる→木炭炉」がそろったときだけ 85% を越え、
    /// どれか 1 つ欠けると届かない(洗いを抜いた鉱石 60% で 83.30%)。
    public static let r1: [RecipeOverride] = [
        RecipeOverride(
            recipe: .charcoalSmelt, fluxItem: .limestone, fluxPurityBonus: Purity(percent: 25),
            reason: "木炭炉 +18 では精に届かない。前処理がそろったときだけ届く +25 にする"),
    ]
}

/// 原作 recipes.json の 1 件の形(snake_case)。コンテンツ側が原作の JSON をそのまま読むための口。
public struct OriginalRecipeRecord: Decodable, Sendable {
    public struct Lot: Decodable, Sendable {
        public var itemId: String
        public var quantity: Int
    }

    public var id: String
    public var inputs: [Lot]
    public var output: Lot
    public var basePurity: Double
    public var fluxItemId: String?
    public var fluxPurityBonus: Double
    public var inputPurityWeight: Double
    public var requiresFire: Bool

    /// 原作の JSON を読む decoder(snake_case)。
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// 万分率に直したレシピ(百分率は ×100、W は ×10000 を四捨五入)。
    public var recipe: Recipe {
        Recipe(
            id: RecipeID(rawValue: id),
            inputs: inputs.map { RecipeInput(ItemID(rawValue: $0.itemId), $0.quantity) },
            output: ItemID(rawValue: output.itemId),
            basePurity: Purity(basisPoints: Int((basePurity * 100).rounded())),
            inputPurityWeight: Int((inputPurityWeight * 10000).rounded()),
            fluxItem: fluxItemId.map(ItemID.init(rawValue:)),
            fluxPurityBonus: Purity(basisPoints: Int((fluxPurityBonus * 100).rounded())),
            requiresFire: requiresFire)
    }
}
