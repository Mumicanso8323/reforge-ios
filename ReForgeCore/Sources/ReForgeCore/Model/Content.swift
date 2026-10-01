public typealias ItemID = String
public typealias RecipeID = String
public typealias BuildingID = String

/// ロジックが名前で参照する ID(原本 JSON の id と同じ)。
public enum ID {
    public static let food: ItemID = "food"
    public static let water: ItemID = "water"
    public static let wood: ItemID = "wood"
    public static let plantFiber: ItemID = "plant_fiber"
    public static let stone: ItemID = "stone"
    public static let clay: ItemID = "clay"
    public static let ironOre: ItemID = "iron_ore"
    public static let coal: ItemID = "coal"
    public static let charcoal: ItemID = "charcoal"
    public static let ironIngot: ItemID = "iron_ingot"
    public static let ironPlate: ItemID = "iron_plate"
    public static let ration: ItemID = "ration"

    public static let campfire: BuildingID = "campfire"
    public static let simpleFarm: BuildingID = "simple_farm"
    public static let well: BuildingID = "well"
    public static let charcoalPit: BuildingID = "charcoal_pit"
    public static let basicFurnace: BuildingID = "basic_furnace"
    public static let storageCrate: BuildingID = "storage_crate"

    public static let charcoalBurn: RecipeID = "charcoal_burn"
    public static let smeltIron: RecipeID = "smelt_iron"
    public static let ironPlatePound: RecipeID = "iron_plate_pound"
    public static let rationRecipe: RecipeID = "ration"
}

public struct ItemAmount: Codable, Equatable, Hashable, Sendable {
    public var item: ItemID
    public var quantity: Int

    public init(_ item: ItemID, _ quantity: Int) {
        self.item = item
        self.quantity = quantity
    }
}

public struct ItemDef: Equatable, Sendable {
    public let id: ItemID
    public let name: String

    public init(id: ItemID, name: String) {
        self.id = id
        self.name = name
    }
}

/// 製作の入力 1 枠。options のどれか 1 つを満たせばよい(先頭ほど優先して使う)。
public struct RecipeInput: Equatable, Sendable {
    public let options: [ItemAmount]

    public init(options: [ItemAmount]) {
        precondition(!options.isEmpty, "入力の候補は 1 つ以上")
        self.options = options
    }
}

public struct RecipeDef: Equatable, Sendable {
    public let id: RecipeID
    public let name: String
    public let inputs: [RecipeInput]
    public let output: ItemAmount
    /// どれか 1 つが建っていれば作れる。空なら条件なし。
    public let stations: [BuildingID]
    /// 日誌の書き出し(「木炭を焼いた」など)。
    public let journal: String

    public init(id: RecipeID, name: String, inputs: [RecipeInput], output: ItemAmount,
                stations: [BuildingID], journal: String) {
        self.id = id
        self.name = name
        self.inputs = inputs
        self.output = output
        self.stations = stations
        self.journal = journal
    }
}

public struct BlueprintDef: Equatable, Sendable {
    public let id: BuildingID
    public let name: String
    public let cost: [ItemAmount]
    /// 建てる画面の効果の 1 文(§7 S4 の確定文言)。
    public let effect: String

    public init(id: BuildingID, name: String, cost: [ItemAmount], effect: String) {
        self.id = id
        self.name = name
        self.cost = cost
        self.effect = effect
    }
}

/// 不変のコンテンツ。並び順は画面の表示順。
public struct ContentDB: Equatable, Sendable {
    public let items: [ItemDef]
    public let recipes: [RecipeDef]
    public let blueprints: [BlueprintDef]

    public init(items: [ItemDef], recipes: [RecipeDef], blueprints: [BlueprintDef]) {
        self.items = items
        self.recipes = recipes
        self.blueprints = blueprints
    }

    public func item(_ id: ItemID) -> ItemDef? { items.first { $0.id == id } }
    public func recipe(_ id: RecipeID) -> RecipeDef? { recipes.first { $0.id == id } }
    public func blueprint(_ id: BuildingID) -> BlueprintDef? { blueprints.first { $0.id == id } }

    /// 画面に出す名前。未知の ID は英語 ID を出さず「不明な物」にする(REQ-05)。
    public func itemName(_ id: ItemID) -> String { item(id)?.name ?? "不明な物" }
    public func buildingName(_ id: BuildingID) -> String { blueprint(id)?.name ?? "不明な建物" }
    public func recipeName(_ id: RecipeID) -> String { recipe(id)?.name ?? "不明な作業" }
}
