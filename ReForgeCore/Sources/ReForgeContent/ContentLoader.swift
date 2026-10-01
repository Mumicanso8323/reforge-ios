import Foundation
import ReForgeCore

/// 同梱 JSON(原本の抜き出し + mvp-overrides.json)から ContentDB を作る(§6.7)。
/// 原本は改変せず、読み込んだあとにオーバーライドを適用する。
public enum ContentLoader {
    public enum LoadError: Error, Equatable {
        case missingResource(String)
        case unknownID(String)
    }

    /// アプリに同梱したコンテンツ。
    public static func bundled() throws -> ContentDB {
        func data(_ name: String) throws -> Data {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")
                ?? Bundle.module.url(forResource: name, withExtension: "json") else {
                throw LoadError.missingResource(name)
            }
            return try Data(contentsOf: url)
        }
        return try load(items: data("items"), recipes: data("recipes"), blueprints: data("blueprints"),
                        overrides: data("mvp-overrides"))
    }

    public static func load(items: Data, recipes: Data, blueprints: Data, overrides: Data) throws -> ContentDB {
        let dec = JSONDecoder()
        let rawItems = try dec.decode([RawItem].self, from: items)
        let rawRecipes = try dec.decode([RawRecipe].self, from: recipes)
        let rawBlueprints = try dec.decode([RawBlueprint].self, from: blueprints)
        let ov = try dec.decode(Overrides.self, from: overrides)

        let itemDefs = try ov.items.order.map { id -> ItemDef in
            guard let raw = rawItems.first(where: { $0.id == id }) else { throw LoadError.unknownID(id) }
            return ItemDef(id: id, name: ov.items.rename[id] ?? raw.name_ja)
        }
        let known = Set(itemDefs.map(\.id))
        func check(_ id: ItemID) throws -> ItemID {
            guard known.contains(id) else { throw LoadError.unknownID(id) }
            return id
        }

        let recipeDefs = try ov.recipes.map { o -> RecipeDef in
            let sources = try o.from.map { src -> RawRecipe in
                guard let r = rawRecipes.first(where: { $0.id == src }) else { throw LoadError.unknownID(src) }
                return r
            }
            let inputs: [RecipeInput]
            if let given = o.inputs {
                inputs = try given.map { opts in
                    RecipeInput(options: try opts.map { ItemAmount(try check($0.item_id), $0.quantity) })
                }
            } else {
                inputs = try sources[0].inputs.map { RecipeInput(options: [ItemAmount(try check($0.item_id), $0.quantity)]) }
            }
            let outRaw = o.output ?? sources[sources.count - 1].output
            return RecipeDef(id: o.id, name: o.name, inputs: inputs,
                             output: ItemAmount(try check(outRaw.item_id), outRaw.quantity),
                             stations: o.stations, journal: o.journal)
        }

        let blueprintDefs = try ov.blueprints.map { o -> BlueprintDef in
            guard let raw = rawBlueprints.first(where: { $0.id == o.id }) else { throw LoadError.unknownID(o.id) }
            let req = o.requirements ?? raw.requirements
            return BlueprintDef(id: o.id, name: raw.name_ja,
                                cost: try req.map { ItemAmount(try check($0.item_id), $0.quantity) },
                                effect: o.effect)
        }
        let buildingIDs = Set(blueprintDefs.map(\.id))
        for r in recipeDefs {
            for st in r.stations where !buildingIDs.contains(st) { throw LoadError.unknownID(st) }
        }
        return ContentDB(items: itemDefs, recipes: recipeDefs, blueprints: blueprintDefs)
    }

    // MARK: 原本 JSON の形(使う項目だけ)

    struct RawAmount: Decodable {
        let item_id: String
        let quantity: Int
    }

    struct RawItem: Decodable {
        let id: String
        let name_ja: String
    }

    struct RawRecipe: Decodable {
        let id: String
        let name_ja: String
        let inputs: [RawAmount]
        let output: RawAmount
    }

    struct RawBlueprint: Decodable {
        let id: String
        let name_ja: String
        let requirements: [RawAmount]
    }

    // MARK: mvp-overrides.json

    struct Overrides: Decodable {
        struct Items: Decodable {
            let order: [String]
            let rename: [String: String]
        }

        struct Recipe: Decodable {
            let id: String
            let from: [String]
            let name: String
            let inputs: [[RawAmount]]?
            let output: RawAmount?
            let stations: [String]
            let journal: String
        }

        struct Blueprint: Decodable {
            let id: String
            let requirements: [RawAmount]?
            let effect: String
        }

        let items: Items
        let recipes: [Recipe]
        let blueprints: [Blueprint]
    }
}
