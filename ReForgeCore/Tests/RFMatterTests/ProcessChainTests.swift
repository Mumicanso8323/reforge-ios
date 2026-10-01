import RFKernel
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
        XCTAssertEqual(cracked.findings.map(\.id), [.hammerCrackedAfterQuench])
        XCTAssertEqual(cracked.name.text, "割れた鉄塊")

        // 熱し直すと急冷の硬さが抜け、叩いて板にできる(焼きなまし)
        let annealed = run([.minehead, .charcoalFurnace, .quench, .charcoalFurnace, .anvil, .quench])
        XCTAssertEqual(annealed.product.temper, .hard)
        XCTAssertEqual(annealed.product.shape, .plate)
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

    /// 前処理が 1 つ欠けると、鉱石 30〜60% のどれでも精(85%)に届かない。全部そろえばどれでも届く。
    func testFineNeedsAllPretreatment() {
        let full: [ProcessStep] = [.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil]
        let missing: [[ProcessStep]] = [
            [.minehead, .sluice, .lime, .charcoalFurnace, .anvil],
            [.minehead, .millstone, .lime, .charcoalFurnace, .anvil],
            [.minehead, .millstone, .sluice, .charcoalFurnace, .anvil],
        ]
        for pct in stride(from: 30, through: 60, by: 5) {
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

        let data = try JSONEncoder().encode(a)
        XCTAssertEqual(try JSONDecoder().decode(ChainResult.self, from: data), a)

        // 規則の表も JSON に出して読み戻せる(後でコンテンツ側のデータにできる)
        let bookData = try JSONEncoder().encode(RuleBook.r1)
        let book = try JSONDecoder().decode(RuleBook.self, from: bookData)
        XCTAssertEqual(book, RuleBook.r1)
        XCTAssertEqual(ProcessChain.run(steps, input: ore30, rules: book), a)
        // ID は JSON のオブジェクトのキーになる
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: bookData) as? [String: Any])
        XCTAssertNotNil((obj["modules"] as? [String: Any])?["furnace"])
        // 純度は整数 1 つで保存される
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(Purity(basisPoints: 4750)), as: UTF8.self), "4750")
    }
}
