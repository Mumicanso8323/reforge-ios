import XCTest
@testable import ReForgeCore
import ReForgeContent

/// 同梱コンテンツが §4.3 / §6.4 / §6.5 の通りに読めること。
final class ContentTests: XCTestCase {
    let c = Fixture.content

    func testItemsInDisplayOrder() {
        XCTAssertEqual(c.items.map(\.name), [
            "食料", "水", "木材", "植物繊維", "石材", "粘土", "鉄鉱石", "石炭", "木炭", "鉄インゴット", "鉄板", "保存食",
        ])
    }

    func testRecipes() {
        XCTAssertEqual(c.recipes.map(\.name), ["木炭焼成", "鉄の製錬", "叩き板金", "携行食"])
        let charcoal = c.recipe(ID.charcoalBurn)!
        XCTAssertEqual(charcoal.inputs, [RecipeInput(options: [ItemAmount(ID.wood, 3)])])
        XCTAssertEqual(charcoal.output, ItemAmount(ID.charcoal, 2))
        XCTAssertEqual(charcoal.stations, [ID.campfire, ID.charcoalPit])

        let smelt = c.recipe(ID.smeltIron)!
        XCTAssertEqual(smelt.inputs, [
            RecipeInput(options: [ItemAmount(ID.ironOre, 1)]),
            RecipeInput(options: [ItemAmount(ID.coal, 1), ItemAmount(ID.charcoal, 1)]),
        ])
        XCTAssertEqual(smelt.output, ItemAmount(ID.ironIngot, 1))

        let plate = c.recipe(ID.ironPlatePound)!
        XCTAssertEqual(plate.inputs, [RecipeInput(options: [ItemAmount(ID.ironIngot, 2)])])
        XCTAssertEqual(plate.output, ItemAmount(ID.ironPlate, 1))
        XCTAssertEqual(plate.stations, [ID.campfire])

        let ration = c.recipe(ID.rationRecipe)!
        XCTAssertEqual(ration.inputs, [RecipeInput(options: [ItemAmount(ID.food, 3)]),
                                       RecipeInput(options: [ItemAmount(ID.plantFiber, 1)])])
        XCTAssertEqual(ration.output, ItemAmount(ID.ration, 2))
        XCTAssertEqual(ration.stations, [])
    }

    func testBlueprints() {
        XCTAssertEqual(c.blueprints.map(\.name), ["焚き火台", "簡易農場", "井戸", "炭焼き窯", "基礎炉", "保管箱"])
        let cost = Dictionary(uniqueKeysWithValues: c.blueprints.map { ($0.id, $0.cost) })
        XCTAssertEqual(cost[ID.campfire], [ItemAmount(ID.wood, 2), ItemAmount(ID.plantFiber, 2)])
        XCTAssertEqual(cost[ID.simpleFarm], [ItemAmount(ID.wood, 5), ItemAmount(ID.plantFiber, 3)])
        XCTAssertEqual(cost[ID.well], [ItemAmount(ID.stone, 4), ItemAmount(ID.wood, 4)])
        XCTAssertEqual(cost[ID.charcoalPit], [ItemAmount(ID.stone, 4), ItemAmount(ID.wood, 6)])
        XCTAssertEqual(cost[ID.basicFurnace], [ItemAmount(ID.stone, 3), ItemAmount(ID.ironPlate, 2)])
        XCTAssertEqual(cost[ID.storageCrate], [ItemAmount(ID.wood, 6), ItemAmount(ID.ironPlate, 2)])
    }
}
