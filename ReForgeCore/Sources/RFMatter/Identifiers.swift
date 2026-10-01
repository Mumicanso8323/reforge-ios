import RFKernel

/// 文字列を中身に持つ型付き ID。データ(規則の表・JSON)で後から足せるように enum にはしない。
/// 表示名ではない(表示は認識の層がこの ID から引く)。
public protocol StringIdentifier: RawRepresentable, Codable, CodingKeyRepresentable, Hashable, Comparable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible where RawValue == String
{
    init(rawValue: String)
}

extension StringIdentifier {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
}

/// 物質(元素・化合物)の ID。原作 `Substance.Symbol` に当たる(下付き文字は使わない)。
public struct SubstanceID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let iron: SubstanceID = "Fe"
    public static let carbon: SubstanceID = "C"
    public static let graphite: SubstanceID = "C_Gra"
    public static let hematite: SubstanceID = "Fe2O3"
    public static let magnetite: SubstanceID = "Fe3O4"
    public static let silica: SubstanceID = "SiO2"
    public static let calciumCarbonate: SubstanceID = "CaCO3"
    public static let water: SubstanceID = "H2O"
}

/// 持ち物・投入物(燃料・混ぜ物・水)の ID。原作の item_id と同じ綴り。
// ItemID は RFKernel の型(TypedID<ItemTag>)。ここでは定数だけを足す。
extension TypedID where Tag == ItemTag {
    public static var ironOre: Self { "iron_ore" }
    public static var wood: Self { "wood" }
    public static var charcoal: Self { "charcoal" }
    public static var coal: Self { "coal" }
    public static var limestone: Self { "limestone" }
    public static var water: Self { "water" }
}

/// レシピの ID。原作 recipes.json の id と同じ綴り。
// RecipeID は RFKernel の型(TypedID<RecipeTag>)。
extension TypedID where Tag == RecipeTag {
    public static var charcoalSmelt: Self { "charcoal_smelt" }
    public static var basicSmelt: Self { "basic_smelt" }
    public static var fluxSmelt: Self { "flux_smelt" }
    public static var crush: Self { "crush" }
    public static var wash: Self { "wash" }
    public static var plateForge: Self { "plate_forge" }
    public static var castIronPlate: Self { "cast_iron_plate" }
    public static var charcoalBurn: Self { "charcoal_burn" }
}

/// 工程のモジュールの種類。規則の表(`RuleBook`)のキー。新しいモジュールは ID と規則を足すだけで増やせる。
/// 工程のモジュールの種類 = RFKernel の ModuleKindID(地図に置くモジュールの種類と同じ ID)。
public typealias ModuleKind = ModuleKindID

extension TypedID where Tag == ModuleKindTag {
    /// 採掘口(鉱脈の上でだけ動く。並びの先頭)。
    public static var minehead: Self { "minehead" }
    /// 石臼(塊を粉にする)。
    public static var millstone: Self { "millstone" }
    /// 洗い樋(粉をすすいで砂を流す)。
    public static var sluice: Self { "sluice" }
    /// 混ぜ鉢(混ぜ物を入れる。R1 は石灰石)。
    public static var mixingBowl: Self { "mixing_bowl" }
    /// 炉(燃料で熱する)。
    public static var furnace: Self { "furnace" }
    /// 叩き台(熱い鉄を叩いて板にする)。
    public static var anvil: Self { "anvil" }
    /// 水槽(熱い鉄を急に冷やす)。
    public static var quenchTank: Self { "quench_tank" }
}

/// 副産物の ID(production-system-design.md の副産物一覧)。
public struct ByproductID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// 砕石(粉砕全般)。
    public static let crushedStone: ByproductID = "crushed_stone"
    /// 砂(洗い樋で流れたケイ素分)。
    public static let sand: ByproductID = "sand"
    /// スラグ(石灰が不純物を抱えて抜けたもの)。
    public static let slag: ByproductID = "slag"
    /// 排気(加熱全般。R2 の大気・公害で使う)。
    public static let exhaust: ByproductID = "exhaust"
}

/// 所見(実験ノートに自動で載る事実)の ID。文はコンテンツ側がこの ID から引く。
/// ノートは事実だけを書き、規則はまとめない(推理をプレイヤーから取らない)。
// FindingID は RFKernel の型(TypedID<FindingTag>)。
extension TypedID where Tag == FindingTag {
    /// 採掘口が並びの先頭にない(鉱脈の上でしか掘れない)。
    public static var mineheadNotAtHead: Self { "minehead.not_at_head" }
    /// 粉をさらに石臼にかけても変わらなかった。
    public static var crushAlreadyDust: Self { "crush.already_dust" }
    /// 鉄は石臼では砕けなかった。
    public static var crushMetalTooTough: Self { "crush.metal_too_tough" }
    /// 塊のままでは中まで水が通らない(洗っても変わらない)。
    public static var washLumpNoEffect: Self { "wash.lump_no_effect" }
    /// 鉄を洗い樋に通しても変わらなかった。
    public static var washMetalNoEffect: Self { "wash.metal_no_effect" }
    /// 混ぜてあった石灰が水で流れてしまった。
    public static var washFluxWashedAway: Self { "wash.flux_washed_away" }
    /// 冷えた鉄に石灰は馴染まない(炉の後で混ぜても効かない)。
    public static var mixAfterSmeltNoEffect: Self { "mix.after_smelt_no_effect" }
    /// もう混ざっていたので、足しても変わらなかった。
    public static var mixAlreadyMixed: Self { "mix.already_mixed" }
    /// 混ぜ物を入れずに混ぜ鉢を通した。
    public static var mixNothingAdded: Self { "mix.nothing_added" }
    /// 燃料の火では温度が足りず、溶けなかった(引数: 燃料)。
    public static var furnaceTooCool: Self { "furnace.too_cool" }
    /// 燃料なしで炉を通した。
    public static var furnaceNoFuel: Self { "furnace.no_fuel" }
    /// 鉱石を叩いても板にならなかった。
    public static var hammerOreNoEffect: Self { "hammer.ore_no_effect" }
    /// 冷やしてから叩いたら割れた。
    public static var hammerCrackedAfterQuench: Self { "hammer.cracked_after_quench" }
    /// 割れた鉄は叩いても戻らない。
    public static var hammerAlreadyCracked: Self { "hammer.already_cracked" }
    /// 鉱石を水に浸けても変わらなかった。
    public static var quenchOreNoEffect: Self { "quench.ore_no_effect" }
    /// もう冷えていたので、水に浸けても変わらなかった。
    public static var quenchAlreadyCold: Self { "quench.already_cold" }
    /// 最後まで炉で溶けず、鉄にならなかった。
    public static var endedAsOre: Self { "result.ended_as_ore" }
    /// 規則の表にないモジュール。
    public static var unknownModule: Self { "module.unknown" }
    /// どの規則にも当たらず、何も起きなかった(引数: モジュール・形)。
    public static var noEffect: Self { "module.no_effect" }
}

/// 名前の固有名・慣用名の ID(原作 NameGenerator の Layer 0・1)。語は認識の層が引く。
public struct ProperNameID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    // 鉄系(炭素量で分岐)
    public static let steel: ProperNameID = "steel"
    public static let hardSteel: ProperNameID = "hard_steel"
    public static let mildSteel: ProperNameID = "mild_steel"
    public static let pigIron: ProperNameID = "pig_iron"
    public static let pureIron: ProperNameID = "pure_iron"
    // 金・銀
    public static let pureGold: ProperNameID = "pure_gold"
    public static let gold22k: ProperNameID = "gold_22k"
    public static let gold18k: ProperNameID = "gold_18k"
    public static let pureSilver: ProperNameID = "pure_silver"
    public static let sterlingSilver: ProperNameID = "sterling_silver"
    // 素材 × 形
    public static let ironFrame: ProperNameID = "iron_frame"
    public static let ironRod: ProperNameID = "iron_rod"
    public static let ironWire: ProperNameID = "iron_wire"
    public static let wireMesh: ProperNameID = "wire_mesh"
    public static let goldLeaf: ProperNameID = "gold_leaf"
    public static let copperFoil: ProperNameID = "copper_foil"
    public static let silverLeaf: ProperNameID = "silver_leaf"
    public static let aluminiumFoil: ProperNameID = "aluminium_foil"
    // 状態・純度で名前が変わる物質
    public static let quartzGlass: ProperNameID = "quartz_glass"
    public static let silicaSand: ProperNameID = "silica_sand"
    public static let diamond: ProperNameID = "diamond"
    public static let pureWater: ProperNameID = "pure_water"
    public static let distilledWater: ProperNameID = "distilled_water"
    // 鉱石
    public static let hematite: ProperNameID = "hematite"
    public static let magnetite: ProperNameID = "magnetite"
    public static let limestone: ProperNameID = "limestone"
    // Layer 1 慣用名
    public static let crudeCopper: ProperNameID = "crude_copper"
    public static let oxygenFreeCopper: ProperNameID = "oxygen_free_copper"
    public static let electrolyticCopper: ProperNameID = "electrolytic_copper"
    public static let crudeTin: ProperNameID = "crude_tin"
    public static let highPurityTin: ProperNameID = "high_purity_tin"
    public static let crudeLead: ProperNameID = "crude_lead"
    public static let electrolyticLead: ProperNameID = "electrolytic_lead"
    public static let ultraPureAluminium: ProperNameID = "ultra_pure_aluminium"
    public static let highPurityAluminium: ProperNameID = "high_purity_aluminium"
    public static let sinteredTungsten: ProperNameID = "sintered_tungsten"
}

/// 合金・物質の定義の ID(原作 AlloyId)。
public struct AlloyID: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let iron: AlloyID = "iron"
    public static let hematite: AlloyID = "hematite"
    public static let castIron: AlloyID = "cast_iron"
    public static let carbonSteel: AlloyID = "carbon_steel"
}
