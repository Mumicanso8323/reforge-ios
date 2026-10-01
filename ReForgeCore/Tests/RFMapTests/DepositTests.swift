import Foundation
import XCTest
import RFKernel
@testable import RFMap

/// 鉱脈: 組成と純度の幅、有限の採掘回数、枯渇、決定的な産出。
final class DepositTests: XCTestCase {
    func testIronRangesMatchOriginal() {
        var rng = SeededRandom(state: 1)
        for i in 0..<300 {
            let d = DepositGenerator.make(id: DepositID("t\(i)"), at: GridPoint(0, 0), category: .iron, rng: &rng)
            XCTAssertTrue((3400...6000).contains(d.purity.basisPoints), "\(d.purity)")   // 35〜60%(合計が 100% を超えたときの縮めで少し下がる)
            XCTAssertTrue((30...70).contains(d.remainingExtractions))
            XCTAssertEqual(d.remainingExtractions, d.initialExtractions)
            XCTAssertLessThanOrEqual(d.composition.reduce(0) { $0 + $1.share.basisPoints }, 10000)
            XCTAssertTrue((0..<3).contains(d.appearanceVariant))
        }
    }

    func testAllCategoriesGenerate() {
        var rng = SeededRandom(state: 2)
        for c in DepositCategory.allCases {
            let d = DepositGenerator.make(id: DepositID(c.rawValue), at: GridPoint(1, 1), category: c, rng: &rng)
            XCTAssertTrue(DepositGenerator.extractionRange(c).contains(d.remainingExtractions), "\(c)")
            XCTAssertGreaterThan(d.purity.basisPoints, 0, "\(c)")
            var r = SeededRandom(state: 3)
            var copy = d
            XCTAssertFalse(copy.extract(rng: &r).isEmpty, "\(c) は掘れば何か出る")
        }
    }

    func testDepletion() {
        var rng = SeededRandom(state: 9)
        var d = DepositGenerator.make(id: DepositID("x"), at: GridPoint(2, 2), category: .iron, rng: &rng)
        let n = d.remainingExtractions
        var mined = 0
        while !d.isDepleted {
            let y = d.extract(rng: &rng)
            XCTAssertFalse(y.isEmpty)
            mined += 1
            XCTAssertEqual(d.remainingExtractions, n - mined)
            XCTAssertEqual(d.depth, mined, "1 回掘るごとに 1m 深く")
        }
        XCTAssertEqual(mined, n)
        // 枯れたら何も出ず、状態も変わらない
        let before = d
        XCTAssertTrue(d.extract(rng: &rng).isEmpty)
        XCTAssertEqual(d, before)
    }

    func testWorldMapExtractionDepletesAndPersists() throws {
        var m = MapFixture.r1Seed7
        var rng = SeededRandom(state: 77)
        let n = m.surface.deposits[.outcrop]!.remainingExtractions
        let first = try XCTUnwrap(m.extract(.outcrop, rng: &rng))
        XCTAssertTrue(first.contains { $0.item == "iron_ore" })
        XCTAssertEqual(m.surface.deposits[.outcrop]!.remainingExtractions, n - 1)
        for _ in 1..<n { XCTAssertNotNil(m.extract(.outcrop, rng: &rng)) }
        XCTAssertTrue(m.surface.deposits[.outcrop]!.isDepleted)
        XCTAssertNil(m.extract(.outcrop, rng: &rng), "枯れた鉱脈は掘れない")
        XCTAssertNil(m.extract(DepositID("deposit.none"), rng: &rng))
        // 保存しても枯れたまま
        let back = try JSONDecoder().decode(WorldMap.self, from: JSONEncoder().encode(m))
        XCTAssertTrue(back.surface.deposits[.outcrop]!.isDepleted)
    }

    func testExtractionIsDeterministic() {
        var rng1 = SeededRandom(state: 5), rng2 = SeededRandom(state: 5)
        var a = MapFixture.r1Seed7.surface.deposits[.outcrop]!
        var b = a
        for _ in 0..<20 { XCTAssertEqual(a.extract(rng: &rng1), b.extract(rng: &rng2)) }
        XCTAssertEqual(a, b)
    }

    func testOutcropPurityAndYieldPurity() {
        let d = MapFixture.r1Seed7.surface.deposits[.outcrop]!
        // 鉄鉱石の純度は Fe の含有率(Fe2O3 の 70%)に表層の補正(−10%)をかけたもの
        let fe = d.content(of: .fe).basisPoints
        XCTAssertEqual(fe, d.composition.reduce(0) { $0 + $1.share.basisPoints * Element.share(of: .fe, in: $1.substance) / 10000 })
        var copy = d
        var rng = SeededRandom(state: 1)
        let ore = copy.extract(rng: &rng).first { $0.item == "iron_ore" }!
        XCTAssertEqual(ore.purity.basisPoints, fe * 9000 / 10000)
    }

    func testDepositsSitOnRockExceptClayBank() {
        for m in MapFixture.r1Seeds.prefix(20) {
            for d in m.surface.deposits.all {
                let b = m.biome(at: d.position)!
                if d.id == .clayBank {
                    XCTAssertTrue(b == .plain || b == .forest)
                } else {
                    XCTAssertTrue(b == .rock || b == .ruins, "\(d.id) が \(b) の上")
                }
                XCTAssertNil(m.surface.placements.placement(at: d.position), "\(d.id) が配置物と重なる")
            }
        }
    }
}
