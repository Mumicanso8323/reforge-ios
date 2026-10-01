import Foundation
import XCTest
@testable import RFMatter

/// 6 種の工程の並びのうち、精鉄板・剛鉄板に届く並びは存在するが少ない(総当たりでは届きにくい)。
/// 一方で、精鉄板への本質的に違う道は 2 本以上ある(道筋の複数性)。
final class ReachabilityTests: XCTestCase {
    let ore30 = Matter.ironOre(purity: Purity(percent: 30))

    func pct(_ n: Int, _ d: Int) -> String { String(format: "%.2f%%", Double(n) * 100 / Double(d)) }

    /// 試作 8 回を無作為に選んで 1 回でも当たる確率。
    func random8(_ hits: Int, _ total: Int) -> Double { 1 - pow(1 - Double(hits) / Double(total), 8) }

    /// 各種類を高々 1 回(順番が違えば別の並び)。炉は燃料 2 通り。
    func testDistinctOrders() {
        let space = ChainSpace.distinctOrders()
        // 種類の並び 1956 通り(長さ 1〜6 の順列の和)。炉を含む 1631 通りは燃料で 2 倍 → 325 + 3262
        XCTAssertEqual(space.count, 3587)
        let results = space.map { ProcessChain.run($0, input: ore30) }
        let fine = results.filter(\.isFinePlate)
        let hard = results.filter(\.isHardPlate)
        let both = results.filter { $0.isFinePlate && $0.isHardPlate }
        // 効果のない段(鉱石を水槽に通す等)を除いて同じ並びになるものは 1 つの道に数える
        let fineReduced = Set(fine.map(\.reducedSteps))
        print("[到達] 各種類 1 回まで: 並び \(space.count) / 精鉄板 \(fine.count) (\(pct(fine.count, space.count)))"
            + " → 効果のない段を除くと \(fineReduced.count) / 剛鉄板 \(hard.count) (\(pct(hard.count, space.count)))"
            + " / 精かつ剛 \(both.count) / 無作為 8 回で精鉄板 \(String(format: "%.2f%%", random8(fine.count, space.count) * 100))")

        XCTAssertEqual(fine.count, 6)
        XCTAssertEqual(
            fineReduced,
            [[.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil],
             [.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil, .quench]])
        XCTAssertFalse(hard.isEmpty)
        XCTAssertFalse(both.isEmpty)
        XCTAssertLessThan(Double(hard.count) / Double(space.count), 0.2)
        XCTAssertLessThan(random8(fine.count, space.count), 0.05)
    }

    /// 繰り返しを許す並び(長さ 8 まで。叩き重ねの道が入る長さ)。
    func testWithRepeats() {
        for maxLength in [6, 8] {
            let c = ChainSpace.countWithRepeats(maxLength: maxLength, ore: ore30)
            let expectedTotal = (1...maxLength).reduce(0) { $0 + Int(pow(7.0, Double($1))) }
            XCTAssertEqual(c.total, expectedTotal)
            let r8 = random8(c.fine, c.total)
            print("[到達] 繰り返しあり長さ \(maxLength) まで: 並び \(c.total) / 精鉄板 \(c.fine) (\(pct(c.fine, c.total)))"
                + " / 剛鉄板 \(c.hard) (\(pct(c.hard, c.total))) / 精かつ剛 \(c.both)"
                + " / 無作為 8 回で精鉄板 \(String(format: "%.2f%%", r8 * 100))")
            XCTAssertGreaterThan(c.fine, 0)
            XCTAssertLessThan(Double(c.hard) / Double(c.total), 0.2)
            XCTAssertLessThan(r8, 0.05)
        }
    }

    /// 精鉄板への本質的に違う道(効果のない段・余計な段の変種を除いたもの)が 2 本以上あり、
    /// 石灰の道と、石灰を使わない叩き重ねの道の両方を含む。露頭の鉱石 20〜35% のどれでも同じ。
    func testEssentialPaths() {
        let lime: [ProcessStep] = [.minehead, .millstone, .sluice, .lime, .charcoalFurnace, .anvil]
        let fold: [ProcessStep] = [
            .minehead, .millstone, .sluice, .charcoalFurnace, .anvil, .charcoalFurnace, .anvil, .charcoalFurnace, .anvil,
        ]
        for pct in [20, 25, 30, 35] {
            let paths = ChainSpace.essentialFinePaths(maxLength: 8, ore: .ironOre(purity: Purity(percent: pct)))
            // 入れ替えても効きが同じ段(混ぜてから砕く/砕いてから混ぜる)の違いは同じ道とみなし、段の組み合わせで数える
            let combos = Set(paths.map { $0.map { shorthand([$0]) }.sorted() })
            if pct == 30 {
                for p in paths { print("[道] \(shorthand(p))") }
                print("[道] 最小の並び \(paths.count) 本 / 段の組み合わせで \(combos.count) 通り")
                XCTAssertEqual(combos.count, 4)
            }
            XCTAssertGreaterThanOrEqual(combos.count, 2, "\(pct)%")
            XCTAssertGreaterThanOrEqual(paths.count, 2, "\(pct)%")
            XCTAssertTrue(paths.contains(lime), "\(pct)%")
            XCTAssertTrue(paths.contains(fold), "\(pct)%")
            // 石灰を使わない道がある
            XCTAssertTrue(paths.contains { !$0.contains(.lime) }, "\(pct)%")
        }
    }
}
