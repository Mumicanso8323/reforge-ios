import Foundation
import XCTest
@testable import RFMatter

/// 連結の工程(order.md §5.4 の発明の表)。
final class ProcessChainTests: XCTestCase {
    let ore30 = Matter.ironOre(purity: Purity(percent: 30))

    func run(_ steps: [ProcessStep], ore: Matter? = nil) -> ChainResult {
        ProcessChain.run(steps, input: ore ?? ore30)
    }

    // MARK: 最初の鉄

    /// order.md §5.6: 鉱石 30% を木炭炉で 1 回 → 50% 前後(粗鉄塊と鉄塊の境目)。
    func testFirstIronIsAroundFiftyPercent() {
        let r = run([.minehead, .charcoalFurnace])
        XCTAssertEqual(r.product.stage, .metal)
        XCTAssertEqual(r.product.purity, Purity(basisPoints: 4750))
        XCTAssertTrue((Purity(percent: 45)...Purity(percent: 55)).contains(r.product.purity))
        XCTAssertEqual(r.name.text, "鉄塊")
        XCTAssertEqual(r.consumed, [ItemAmount(.charcoal, 1)])
        XCTAssertEqual(r.byproducts, [.exhaust])
        XCTAssertTrue(r.findings.isEmpty)
        // §5.2 の場面の並び〔鉱石〕→〔炉〕→〔叩き台〕は、急冷しないので柔らかい板
        XCTAssertEqual(run([.minehead, .charcoalFurnace, .anvil]).name.text, "柔鉄板")
    }

    /// 露頭の鉱石 20〜35%(`R1Ore.outcrop`)では、連結を通して粗鉄塊と鉄塊の両方が出て、粗鉄板も作れる。
    func testOutcropGivesCrudeAndStandardIron() {
        var lumps: Set<String> = []
        var crudePlate = false
        for bp in stride(from: R1Ore.outcrop.lowerBound.basisPoints, through: R1Ore.outcrop.upperBound.basisPoints, by: 100) {
            let ore = Matter.ironOre(purity: Purity(basisPoints: bp))
            lumps.insert(run([.minehead, .charcoalFurnace], ore: ore).name.text)
            let plate = run([.minehead, .charcoalFurnace, .anvil], ore: ore)
            if plate.product.shape == .plate && plate.name.grade == .crude { crudePlate = true }
        }
        XCTAssertEqual(lumps, ["粗鉄塊", "鉄塊"])
        XCTAssertTrue(crudePlate)
        let r20 = run([.minehead, .charcoalFurnace], ore: .ironOre(purity: Purity(percent: 20)))
        XCTAssertEqual(r20.product.purity, Purity(basisPoints: 4450))
        let r35 = run([.minehead, .charcoalFurnace], ore: .ironOre(purity: Purity(percent: 35)))
        XCTAssertEqual(r35.product.purity, Purity(basisPoints: 4900))
        // 粗い板は柔(急冷すれば剛)。語順は認識の層が決めるので、ここは部品で見る
        let crude = run([.minehead, .charcoalFurnace, .anvil], ore: .ironOre(purity: Purity(percent: 20)))
        XCTAssertEqual(crude.name.parts, [.grade(.crude, .metal), .temper(.soft), .substance(.iron), .shape(.plate)])
    }

    // MARK: §5.4 の規則

    /// 塊では洗えない。粉なら砂が流れて純度が上がる。
    func testSluiceNeedsDust() {
        let lump = run([.minehead, .sluice])
        XCTAssertEqual(lump.product.purity, Purity(percent: 30))
        XCTAssertEqual(lump.findings.map(\.id), [.washLumpNoEffect, .endedAsOre])
        XCTAssertEqual(lump.findings.first?.args, [.shape(.lump)])
        XCTAssertEqual(lump.findings.first?.step, 1)
        XCTAssertEqual(lump.consumed, [ItemAmount(.water, 1)])

        let dust = run([.minehead, .millstone, .sluice])
        XCTAssertEqual(dust.product.shape, .dust)
        XCTAssertEqual(dust.trace[1].after.purity, Purity(basisPoints: 5400))  // crush: 70×0.6 + 30×0.4
        XCTAssertEqual(dust.product.purity, Purity(basisPoints: 7570))  // wash: 85×0.7 + 54×0.3
        XCTAssertEqual(dust.byproducts, [.crushedStone, .sand])
    }

    /// 石灰は炉の前でだけ効く(炉の後では「冷えた鉄に石灰は馴染まない」)。
    func testLimeOnlyBeforeFurnace() {
        let before = run([.minehead, .lime, .charcoalFurnace])
        XCTAssertEqual(before.product.purity, Purity(basisPoints: 4750 + 2500))
        XCTAssertTrue(before.byproducts.contains(.slag))
        XCTAssertTrue(before.product.additives.isEmpty)

        let after = run([.minehead, .charcoalFurnace, .lime])
        XCTAssertEqual(after.product.purity, Purity(basisPoints: 4750))
        XCTAssertFalse(after.byproducts.contains(.slag))
        XCTAssertEqual(after.findings.map(\.id), [.mixAfterSmeltNoEffect])
        XCTAssertEqual(after.findings.first?.args, [.item(.limestone)])
        XCTAssertEqual(after.consumed, [ItemAmount(.charcoal, 1), ItemAmount(.limestone, 1)])
    }

    /// 石灰を混ぜてから洗うと、石灰が流れて効かない。
    func testWashingAfterLimeLosesIt() {
        let r = run([.minehead, .millstone, .lime, .sluice, .charcoalFurnace])
        XCTAssertTrue(r.findings.map(\.id).contains(.washFluxWashedAway))
        XCTAssertFalse(r.byproducts.contains(.slag))
        XCTAssertEqual(r.product.purity, Purity(basisPoints: 6121))  // 55×0.7 + 75.7×0.3
    }

    /// 薪では溶けない。
    func testWoodDoesNotMelt() {
        let r = run([.minehead, .woodFurnace, .anvil])
        XCTAssertEqual(r.product.stage, .ore)
        XCTAssertEqual(r.findings.map(\.id), [.furnaceTooCool, .hammerOreNoEffect, .endedAsOre])
        XCTAssertEqual(r.findings.first?.args, [.item(.wood)])
        XCTAssertEqual(r.consumed, [ItemAmount(.wood, 1)])
    }

    /// 叩いた後に急冷で剛、急冷なしで柔、急冷の後に叩くと割れる。
    func testHammerAndQuenchOrder() {
        let hard = run([.minehead, .charcoalFurnace, .anvil, .quench])
        XCTAssertEqual(hard.product.temper, .hard)
        XCTAssertEqual(hard.name.text, "剛鉄板")
        XCTAssertEqual(hard.hardness, 85)
        XCTAssertEqual(hard.toughness, 30)

        let soft = run([.minehead, .charcoalFurnace, .anvil])
        XCTAssertEqual(soft.product.temper, .soft)
        XCTAssertEqual(soft.product.thermal, .airCooled)
        XCTAssertGreaterThan(soft.toughness, hard.toughness)
        XCTAssertLessThan(soft.hardness, hard.hardness)

        let cracked = run([.minehead, .charcoalFurnace, .quench, .anvil])
        XCTAssertEqual(cracked.product.temper, .cracked)
        XCTAssertEqual(cracked.toughness, 0)
        XCTAssertEqual(cracked.findings.map(\.id), [.quenchUnworkedNotHardened, .hammerCrackedAfterQuench])
        XCTAssertEqual(cracked.name.text, "割れた鉄塊")

        // 熱し直すと急冷の硬さが抜け、叩いて板にできる(焼きなまし)
        let annealed = run([.minehead, .charcoalFurnace, .quench, .charcoalFurnace, .anvil, .quench])
        XCTAssertEqual(annealed.product.temper, .hard)
        XCTAssertEqual(annealed.product.shape, .plate)
    }

    /// 剛は叩いた後の急冷だけ。叩いていない塊は冷やしても硬くならない(所見が出る)。
    func testQuenchingUnworkedLumpDoesNotHarden() {
        let r = run([.minehead, .charcoalFurnace, .quench])
        XCTAssertEqual(r.product.temper, .none)
        XCTAssertEqual(r.product.thermal, .quenched)
        XCTAssertEqual(r.findings.map(\.id), [.quenchUnworkedNotHardened])
        XCTAssertEqual(r.findings.first?.args, [.shape(.lump)])
        XCTAssertEqual(r.name.text, "鉄塊")
    }

    /// 叩き重ね: 熱し直してから叩くと純度が上がる。熱し直さずに叩いても伸びない。3 回目は変わらない。
    func testFolding() {
        let once = run([.minehead, .charcoalFurnace, .anvil])
        let twice = run([.minehead, .charcoalFurnace, .anvil, .charcoalFurnace, .anvil])
        XCTAssertEqual(twice.product.worked, 2)
        XCTAssertEqual(twice.product.purity, Purity(basisPoints: 7075))  // 94×0.5 + 47.5×0.5
        XCTAssertGreaterThan(twice.product.purity, once.product.purity)
        XCTAssertEqual(twice.consumed, [ItemAmount(.charcoal, 2)])

        let cold = run([.minehead, .charcoalFurnace, .anvil, .anvil])
        XCTAssertEqual(cold.product.purity, once.product.purity)
        XCTAssertEqual(cold.findings.map(\.id), [.hammerTooCool])

        let fold: [ProcessStep] = [.charcoalFurnace, .anvil]
        let max = run([.minehead] + fold + fold + fold)
        let over = run([.minehead] + fold + fold + fold + fold)
        XCTAssertEqual(max.product.worked, 3)
        XCTAssertEqual(over.product.purity, max.product.purity)
        XCTAssertEqual(over.findings.map(\.id), [.hammerNoFurther])
    }

    /// 石灰を使わない 2 本目の道: 砕く→洗う→炉→叩く→(熱し直す→叩く)×2。洗いを抜くと届かない。
    func testFoldPathToFinePlate() {
        let path: [ProcessStep] = [
            .minehead, .millstone, .sluice, .charcoalFurnace, .anvil, .charcoalFurnace, .anvil, .charcoalFurnace, .anvil,
        ]
        var noWash = path
        noWash.remove(at: 2)
        for pct in 20...35 {
            let ore = Matter.ironOre(purity: Purity(percent: pct))
            XCTAssertTrue(run(path, ore: ore).isFinePlate, "\(pct)%")
            XCTAssertFalse(run(noWash, ore: ore).isFinePlate, "\(pct)%")
        }
        let r = run(path)
        XCTAssertEqual(r.product.purity, Purity(basisPoints: 8581))
        XCTAssertEqual(r.consumed, [ItemAmount(.charcoal, 3), ItemAmount(.water, 1)])
        XCTAssertFalse(r.byproducts.contains(.slag))
    }

    /// 混ぜ鉢に石灰石以外を入れても抱えない(所見が出る)。石灰石と別の物を一緒に入れても同じ。
    func testMixingBowlRejectsOtherAdditives() {
        let sand = run([.minehead, ProcessStep(.mixingBowl, input: "sand"), .charcoalFurnace])
        XCTAssertEqual(sand.findings.map(\.id), [.mixUnknownAdditive])
        XCTAssertEqual(sand.findings.first?.args, [.item("sand")])
        XCTAssertEqual(sand.product.purity, Purity(basisPoints: 4750))
        XCTAssertTrue(sand.trace[1].after.additives.isEmpty)

        let both = run([.minehead, ProcessStep(.mixingBowl, inputs: [RecipeLot(.limestone), RecipeLot("sand")])])
        XCTAssertEqual(both.findings.first?.id, .mixUnknownAdditive)
        XCTAssertEqual(both.findings.first?.args, [.item(.limestone), .item("sand")])
        XCTAssertTrue(both.product.additives.isEmpty)
        XCTAssertEqual(both.consumed, [ItemAmount(.limestone, 1), ItemAmount("sand", 1)])
    }

    /// 特性の加減と条件(R2 以降で 18 特性を加工で変える口)。
    func testTraitsAreData() {
        var book = RuleBook.r1
        book.modules["oil_bath"] = [
            ModuleRule(
                when: .init(stage: .metal, traits: [TraitRange(.toughness, max: 9)]),
                then: [.addTrait(.toughness, 10), .addTrait(.hardness, -5)]),
            ModuleRule(when: .any, then: [.finding(.noEffect, [.module])]),
        ]
        let steps: [ProcessStep] = [.minehead, .charcoalFurnace, .anvil, ProcessStep("oil_bath"), ProcessStep("oil_bath")]
        let r = ProcessChain.run(steps, input: ore30, rules: book)
        XCTAssertEqual(r.product.traits, [.toughness: 10, .hardness: -5])
        XCTAssertEqual(r.toughness, 80 + 10)
        XCTAssertEqual(r.hardness, 40 - 5)
        XCTAssertEqual(r.findings.map(\.id), [.noEffect])
    }

    /// 1 段に複数の入力を取れる(合金の相手など)。原作 Execute と同じく、段の入力も平均に入る。
    func testMultipleInputsPerStep() {
        var book = RuleBook.r1
        book.modules["alloy_pot"] = [
            ModuleRule(
                when: .init(stage: .metal, input: .includes("tin")),
                then: [.consumeStepInputs, .applyRecipeWithInputs(.charcoalSmelt)]),
        ]
        let pot = ProcessStep("alloy_pot", inputs: [RecipeLot("tin", purity: Purity(percent: 90)), RecipeLot(.charcoal)])
        let r = ProcessChain.run([.minehead, .charcoalFurnace, pot], input: ore30, rules: book)
        // 平均 (47.5 + 90 + 100) / 3 = 79.1666… → 55×0.7 + 79.1666…×0.3 = 62.25
        XCTAssertEqual(r.product.purity, Purity(basisPoints: 6225))
        XCTAssertEqual(r.consumed, [ItemAmount(.charcoal, 2), ItemAmount("tin", 1)])
    }

    /// 精鉄板と剛鉄板に同時に届く並び(砕く→洗う→混ぜる→木炭炉→叩く→冷やす)。
    func testFineHardPlate() {
        let r = run([.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil, .quench])
        XCTAssertEqual(r.product.purity, Purity(basisPoints: 8621))
        XCTAssertEqual(r.name.text, "精剛鉄板")
        XCTAssertTrue(r.isFinePlate)
        XCTAssertTrue(r.isHardPlate)
        XCTAssertEqual(r.byproducts, [.crushedStone, .sand, .exhaust, .slag])
        XCTAssertEqual(
            r.consumed,
            [ItemAmount(.charcoal, 1), ItemAmount(.limestone, 1), ItemAmount(.water, 1)])
        XCTAssertTrue(r.findings.isEmpty)
        XCTAssertEqual(r.trace.map(\.step), [.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil, .quench])
    }

    /// 叩き重ねなしでは、前処理が 1 つ欠けると鉱石 20〜60% のどれでも精(85%)に届かない。全部そろえばどれでも届く。
    func testFineNeedsAllPretreatment() {
        let full: [ProcessStep] = [.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil]
        let missing: [[ProcessStep]] = [
            [.minehead, .sluice, .lime, .charcoalFurnace, .anvil],
            [.minehead, .millstone, .lime, .charcoalFurnace, .anvil],
            [.minehead, .millstone, .sluice, .charcoalFurnace, .anvil],
        ]
        for pct in stride(from: 20, through: 60, by: 5) {
            let ore = Matter.ironOre(purity: Purity(percent: pct))
            XCTAssertTrue(run(full, ore: ore).isFinePlate, "\(pct)%")
            for steps in missing {
                XCTAssertFalse(run(steps, ore: ore).isFinePlate, "\(pct)% \(shorthand(steps))")
            }
        }
    }

    func testMineheadOnlyAtHead() {
        let r = run([.charcoalFurnace, .minehead])
        XCTAssertEqual(r.findings.map(\.id), [.mineheadNotAtHead])
        XCTAssertEqual(r.findings.first?.step, 1)
    }

    func testUnknownModuleAndNoFuel() {
        let r = run([.minehead, ProcessStep("drying_rack"), ProcessStep(.furnace)])
        XCTAssertEqual(r.findings.map(\.id), [.unknownModule, .furnaceNoFuel, .endedAsOre])
        XCTAssertEqual(r.findings.first?.args, [.module("drying_rack")])
    }

    func testMillstoneOnDustAndMetal() {
        XCTAssertEqual(run([.minehead, .millstone, .millstone]).findings.first?.id, .crushAlreadyDust)
        XCTAssertEqual(run([.minehead, .charcoalFurnace, .millstone]).findings.first?.id, .crushMetalTooTough)
        XCTAssertEqual(run([.minehead, .lime, .lime]).findings.first?.id, .mixAlreadyMixed)
    }

    // MARK: データ駆動・決定的・Codable

    /// モジュールは規則の表に足すだけで増やせる(コードは変えない)。
    func testModulesAreData() {
        var book = RuleBook.r1
        book.modules["sieve"] = [
            ModuleRule(
                when: .init(stage: .ore, shapes: [.dust]),
                then: [.applyRecipe(.wash), .byproduct(.sand)]),
        ]
        let r = ProcessChain.run(
            [.minehead, .millstone, ProcessStep("sieve")], input: ore30, rules: book)
        XCTAssertEqual(r.product.purity, Purity(basisPoints: 7570))
        XCTAssertEqual(r.findings.map(\.id), [.endedAsOre])
    }

    func testDeterministicAndCodable() throws {
        let steps: [ProcessStep] = [.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil, .quench]
        let a = run(steps)
        XCTAssertEqual(a, run(steps))

        let data = try MatterCoding.encoder().encode(a)
        XCTAssertEqual(try JSONDecoder().decode(ChainResult.self, from: data), a)
        XCTAssertEqual(try MatterCoding.encoder().encode(a), data)

        // 規則の表も JSON に出して読み戻せる(後でコンテンツ側のデータにできる)
        let bookData = try MatterCoding.encoder().encode(RuleBook.r1)
        let book = try JSONDecoder().decode(RuleBook.self, from: bookData)
        XCTAssertEqual(book, RuleBook.r1)
        XCTAssertEqual(ProcessChain.run(steps, input: ore30, rules: book), a)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: bookData) as? [String: Any])
        XCTAssertNotNil((obj["modules"] as? [String: Any])?["furnace"])
    }

    /// 保存の形の退行検出: 固定の JSON 文字列と突き合わせる(キーや ID の綴りが変わったら落ちる)。
    func testGoldenJSON() throws {
        let matter = Matter(
            substance: .hematite, purity: Purity(basisPoints: 3000), stage: .ore, shape: .dust,
            additives: [.limestone], traits: [.hardness: 3])
        let matterJSON = #"{"additives":["limestone"],"components":[],"purity":3000,"shape":"dust","stage":"ore","substance":"Fe2O3","temper":"none","thermal":"ambient","traits":{"hardness":3},"worked":0}"#
        XCTAssertEqual(String(decoding: try MatterCoding.encoder().encode(matter), as: UTF8.self), matterJSON)
        XCTAssertEqual(try JSONDecoder().decode(Matter.self, from: Data(matterJSON.utf8)), matter)

        let effects: [RuleEffect] = [
            .applyRecipe(.crush), .becomes(.metal, .iron), .consume(.water, 1), .dropAdditives,
            .finding(.furnaceTooCool, [.stepInput]), .addTrait(.toughness, -2),
        ]
        let effectsJSON = #"[{"apply_recipe":{"recipe":"crush"}},{"becomes":{"stage":"metal","substance":"Fe"}},{"consume":{"item":"water","quantity":1}},{"drop_additives":{}},{"finding":{"args":["step_input"],"id":"furnace.too_cool"}},{"add_trait":{"delta":-2,"trait":"toughness"}}]"#
        XCTAssertEqual(String(decoding: try MatterCoding.encoder().encode(effects), as: UTF8.self), effectsJSON)
        XCTAssertEqual(try JSONDecoder().decode([RuleEffect].self, from: Data(effectsJSON.utf8)), effects)

        let name = NameGenerator.name(for: .iron(8600, .plate, temper: .hard))
        let nameJSON = #"{"parts":[{"grade":{"category":"metal","grade":"fine"}},{"temper":{"temper":"hard"}},{"substance":{"substance":"Fe"}},{"shape":{"shape":"plate"}}]}"#
        XCTAssertEqual(String(decoding: try MatterCoding.encoder().encode(name), as: UTF8.self), nameJSON)
        XCTAssertEqual(try JSONDecoder().decode(MatterName.self, from: Data(nameJSON.utf8)), name)

        let finding = Finding(id: .furnaceTooCool, step: 1, args: [.item(.wood), .purity(Purity(basisPoints: 3000))])
        let findingJSON = #"{"args":[{"item":{"id":"wood"}},{"purity":{"value":3000}}],"id":"furnace.too_cool","step":1}"#
        XCTAssertEqual(String(decoding: try MatterCoding.encoder().encode(finding), as: UTF8.self), findingJSON)
        XCTAssertEqual(try JSONDecoder().decode(Finding.self, from: Data(findingJSON.utf8)), finding)

        let input = InputMatch.exactly([.limestone])
        XCTAssertEqual(
            String(decoding: try MatterCoding.encoder().encode(input), as: UTF8.self), #"{"exactly":{"items":["limestone"]}}"#)
    }

    func testDecodingRejectsBadPurityAndNormalizesAdditives() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(Purity.self, from: Data("10001".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Purity.self, from: Data("-1".utf8)))
        XCTAssertEqual(try JSONDecoder().decode(Purity.self, from: Data("10000".utf8)), .full)
        let json = #"{"additives":["water","limestone","water"],"components":[],"purity":3000,"shape":"lump","stage":"ore","substance":"Fe2O3","temper":"none","thermal":"ambient","traits":{},"worked":0}"#
        let m = try JSONDecoder().decode(Matter.self, from: Data(json.utf8))
        XCTAssertEqual(m.additives, [.limestone, .water])
    }
}
