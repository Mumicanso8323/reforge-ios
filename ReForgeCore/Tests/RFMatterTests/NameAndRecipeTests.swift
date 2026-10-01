import RFKernel
import Foundation
import XCTest
@testable import RFMatter

/// 命名(原作 NameGenerator)とレシピの純度式(原作 Recipe.Execute)。
final class NameAndRecipeTests: XCTestCase {
    // MARK: 命名の境目(20 / 45 / 85 / 98、以上で上の段)

    func testMetalPrefixBoundaries() {
        let cases: [(Int, String)] = [
            (1999, "粗悪な鉄塊"), (2000, "粗鉄塊"), (4499, "粗鉄塊"), (4500, "鉄塊"),
            (8499, "鉄塊"), (8500, "精鉄塊"), (9799, "精鉄塊"), (9800, "純鉄塊"),
        ]
        for (bp, expected) in cases {
            XCTAssertEqual(NameGenerator.name(for: .iron(bp)).text, expected, "\(Purity(basisPoints: bp))")
        }
    }

    func testGradeIsPartsNotText() {
        let n = NameGenerator.name(for: .iron(8600, .plate, temper: .hard))
        XCTAssertEqual(n.parts, [.grade(.fine, .metal), .temper(.hard), .substance(.iron), .shape(.plate)])
        XCTAssertEqual(n.grade, .fine)
        XCTAssertEqual(n.temper, .hard)
        // 無修飾の段と 20% 未満は段の部品を出さない
        XCTAssertNil(NameGenerator.name(for: .iron(5000)).grade)
        XCTAssertEqual(NameGenerator.name(for: .iron(1000)).parts.first, .extreme(.poor))
    }

    /// 文字列化は差し替えられる(同じ部品から別の語)。
    func testRendererIsReplaceable() {
        struct OldWords: NameRendering {
            func render(_ name: MatterName) -> String {
                name.parts.map { p -> String in
                    switch p {
                    case .substance(.iron): "くろがね"
                    case .shape(.plate): "の板"
                    default: ""
                    }
                }.joined()
            }
        }
        let n = NameGenerator.name(for: .iron(5000, .plate))
        XCTAssertEqual(n.rendered(by: OldWords()), "くろがねの板")
        XCTAssertEqual(n.text, "鉄板")
    }

    func testShapeSuffixAndTemper() {
        XCTAssertEqual(NameGenerator.name(for: .iron(5000, .plate)).text, "鉄板")
        XCTAssertEqual(NameGenerator.name(for: .iron(3000, .plate)).text, "粗鉄板")
        XCTAssertEqual(NameGenerator.name(for: .iron(9000, .plate)).text, "精鉄板")
        XCTAssertEqual(NameGenerator.name(for: .iron(5000, .plate, temper: .hard)).text, "剛鉄板")
        XCTAssertEqual(NameGenerator.name(for: .iron(5000, .plate, temper: .soft)).text, "柔鉄板")
        XCTAssertEqual(NameGenerator.name(for: .iron(5000, .plate, temper: .cracked)).text, "割れた鉄板")
        XCTAssertEqual(NameGenerator.name(for: .iron(5000, .dust)).text, "鉄粉")
    }

    /// 原作 Layer 0・1 の固有名と慣用名。
    func testProperAndConventionalNames() {
        XCTAssertEqual(NameGenerator.name(for: .iron(9990, .plate)).text, "純鉄板")
        XCTAssertEqual(NameGenerator.name(for: .iron(9990, .plate)).parts, [.proper(.pureIron), .shape(.plate)])
        XCTAssertEqual(NameGenerator.name(for: .iron(6000, .rod)).text, "鉄棒")
        let steel = Matter(
            substance: .iron, purity: Purity(percent: 97), stage: .metal, shape: .plate,
            components: [Component(.carbon, Purity(basisPoints: 205))])
        XCTAssertEqual(NameGenerator.name(for: steel).text, "鋼板")
        XCTAssertEqual(NameGenerator.name(for: .ironOre(purity: Purity(percent: 30))).text, "赤鉄鉱塊")
        XCTAssertEqual(NameGenerator.name(substance: .silica, purity: Purity(percent: 60), shape: .dust).text, "珪砂")
        XCTAssertEqual(NameGenerator.name(substance: "Cu", purity: Purity(percent: 90), shape: .plate).text, "粗銅板")
        XCTAssertEqual(NameGenerator.name(substance: "Cu", purity: Purity(basisPoints: 9992), shape: nil).text, "電気銅")
    }

    func testCategoryPrefixes() {
        XCTAssertEqual(PurityGrade.of(Purity(percent: 90), category: .granular), .pure)
        XCTAssertEqual(PurityGrade.of(Purity(percent: 30), category: .chemical), .crude)
        XCTAssertEqual(PurityGrade.of(Purity(percent: 10), category: .chemical), .crude)
        XCTAssertEqual(PurityGrade.of(Purity(percent: 96), category: .organic), .pure)
        XCTAssertEqual(MaterialCategory.of(.iron), .metal)
        XCTAssertEqual(MaterialCategory.of(.water), .liquid)
        XCTAssertEqual(MaterialCategory.of(.graphite), .granular)
    }

    func testPurityEffect() {
        XCTAssertEqual(PurityMath.nines(Purity(percent: 90)), 1, accuracy: 1e-9)
        XCTAssertEqual(PurityMath.nines(Purity(percent: 99)), 2, accuracy: 1e-9)
        XCTAssertEqual(PurityMath.effect(Purity(percent: 99)), 1.4, accuracy: 1e-9)
        XCTAssertEqual(PurityMath.nines(.full), 6)
    }

    // MARK: 純度の式

    func testRecipeFormula() throws {
        let charcoal = try XCTUnwrap(RecipeBook.original[.charcoalSmelt])
        // 55 × 0.7 + 30 × 0.3 = 47.5
        XCTAssertEqual(charcoal.outputPurity(inputPurities: [Purity(percent: 30)], hasFlux: false), Purity(basisPoints: 4750))
        // 混ぜ物: basic_smelt は 60 × 0.7 + 30 × 0.3 + 18 = 69
        let basic = try XCTUnwrap(RecipeBook.original[.basicSmelt])
        XCTAssertEqual(basic.outputPurity(inputPurities: [Purity(percent: 30)], hasFlux: true), Purity(percent: 69))
        XCTAssertEqual(basic.outputPurity(inputPurities: [Purity(percent: 30)], hasFlux: false), Purity(percent: 51))
        // 叩き(W 1.0)は純度を変えない
        let forge = try XCTUnwrap(RecipeBook.original[.plateForge])
        XCTAssertEqual(forge.outputPurity(inputPurities: [Purity(basisPoints: 4750)], hasFlux: false), Purity(basisPoints: 4750))
        // 60 × 0.7 + 100 × 0.3 + 18 = 90、flux_smelt を超える加算でも 100% で止まる
        XCTAssertEqual(basic.outputPurity(inputPurities: [.full], hasFlux: true), Purity(percent: 90))
        var strong = basic
        strong.fluxPurityBonus = Purity(percent: 40)
        XCTAssertEqual(strong.outputPurity(inputPurities: [.full], hasFlux: true), .full)
    }

    /// 原作 Execute の判定: 入力がそろわなければ nil、平均はフラックス以外の全入力(燃料も含む)。
    func testRecipeExecuteLikeOriginal() throws {
        let charcoal = try XCTUnwrap(RecipeBook.original[.charcoalSmelt])
        XCTAssertNil(charcoal.execute([RecipeLot(.ironOre, purity: Purity(percent: 30))]))
        // (30 + 100) / 2 = 65 → 55 × 0.7 + 65 × 0.3 = 58
        XCTAssertEqual(
            charcoal.execute([RecipeLot(.ironOre, purity: Purity(percent: 30)), RecipeLot(.charcoal)]),
            Purity(percent: 58))
        let basic = try XCTUnwrap(RecipeBook.original[.basicSmelt])
        let lots = [
            RecipeLot(.ironOre, purity: Purity(percent: 30)), RecipeLot(.coal, purity: Purity(percent: 30)),
            RecipeLot(.limestone, purity: Purity(percent: 5)),
        ]
        // 石灰石は平均から外れて +18
        XCTAssertEqual(basic.execute(lots), Purity(percent: 69))
    }

    /// 表の値が原作 recipes.json と同じ(原作の JSON の形で読んだものと比べる)。
    func testRecipeValuesMatchOriginalJSON() throws {
        let json = """
            [
            {"id": "charcoal_smelt", "name_ja": "木炭製錬", "inputs": [{"item_id": "iron_ore", "quantity": 1}, {"item_id": "charcoal", "quantity": 1}], "output": {"item_id": "molten_iron", "name_ja": "溶融鉄", "quantity": 1}, "base_purity": 55.0, "flux_item_id": null, "flux_purity_bonus": 0.0, "input_purity_weight": 0.3, "requires_fire": true, "craft_duration_seconds": 0.0, "required_skill_id": null, "required_skill_level": 1},
            {"id": "basic_smelt", "name_ja": "基礎製錬", "inputs": [{"item_id": "iron_ore", "quantity": 1}, {"item_id": "coal", "quantity": 1}], "output": {"item_id": "molten_iron", "name_ja": "溶融鉄", "quantity": 1}, "base_purity": 60.0, "flux_item_id": "limestone", "flux_purity_bonus": 18.0, "input_purity_weight": 0.3, "requires_fire": false, "craft_duration_seconds": 0.0, "required_skill_id": null, "required_skill_level": 1},
            {"id": "flux_smelt", "name_ja": "フラックス製錬", "inputs": [{"item_id": "iron_ore", "quantity": 1}, {"item_id": "coal", "quantity": 1}, {"item_id": "limestone", "quantity": 1}], "output": {"item_id": "molten_iron", "name_ja": "溶融鉄", "quantity": 1}, "base_purity": 78.0, "flux_item_id": null, "flux_purity_bonus": 0.0, "input_purity_weight": 0.2, "requires_fire": false, "craft_duration_seconds": 0.0, "required_skill_id": null, "required_skill_level": 1},
            {"id": "crush", "name_ja": "粉砕", "inputs": [{"item_id": "iron_ore", "quantity": 1}], "output": {"item_id": "crushed_iron", "name_ja": "粉砕鉄", "quantity": 1}, "base_purity": 70.0, "flux_item_id": null, "flux_purity_bonus": 0.0, "input_purity_weight": 0.4, "requires_fire": false, "craft_duration_seconds": 0.0, "required_skill_id": null, "required_skill_level": 1},
            {"id": "wash", "name_ja": "洗浄", "inputs": [{"item_id": "crushed_iron", "quantity": 1}, {"item_id": "water", "quantity": 1}], "output": {"item_id": "refined_iron_dust", "name_ja": "精製鉄粉", "quantity": 1}, "base_purity": 85.0, "flux_item_id": null, "flux_purity_bonus": 0.0, "input_purity_weight": 0.3, "requires_fire": false, "craft_duration_seconds": 0.0, "required_skill_id": null, "required_skill_level": 1},
            {"id": "plate_forge", "name_ja": "板金加工（型成形）", "inputs": [{"item_id": "iron_ingot", "quantity": 1}, {"item_id": "stone", "quantity": 1}], "output": {"item_id": "iron_plate", "name_ja": "鉄板", "quantity": 1}, "base_purity": 0.0, "flux_item_id": null, "flux_purity_bonus": 0.0, "input_purity_weight": 1.0, "requires_fire": false, "craft_duration_seconds": 0.0, "required_skill_id": null, "required_skill_level": 1}
            ]
            """
        let records = try OriginalRecipeRecord.decoder().decode([OriginalRecipeRecord].self, from: Data(json.utf8))
        for r in records.map(\.recipe) {
            XCTAssertEqual(RecipeBook.original[r.id], r, r.id.rawValue)
        }
        // R1 の差分は木炭炉のフラックスだけ
        var expected = try XCTUnwrap(RecipeBook.original[.charcoalSmelt])
        expected.fluxItem = .limestone
        expected.fluxPurityBonus = Purity(percent: 25)
        XCTAssertEqual(RecipeBook.r1[.charcoalSmelt], expected)
        XCTAssertEqual(RecipeBook.r1[.crush], RecipeBook.original[.crush])
    }

    func testSubstanceTableCarriesEighteenProperties() throws {
        let fe = try XCTUnwrap(SubstanceTable.r1[.iron])
        XCTAssertEqual(Mirror(reflecting: fe.properties).children.count, 18)
        XCTAssertEqual(fe.properties.hardness, 6.0)
        XCTAssertEqual(fe.state(atKelvin: 300), .solid)
        XCTAssertEqual(fe.state(atKelvin: 1900), .liquid)
        XCTAssertEqual(AlloyDefinition.r1.first { $0.id == .carbonSteel }?.compositions.first?.count, 2)
    }
}
