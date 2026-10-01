import RFKernel
import Foundation
import XCTest
@testable import RFMatter

/// 6 種の工程の並びのうち、精鉄板・剛鉄板に届く並びは存在するが少ない(総当たりでは届きにくい)。
final class ReachabilityTests: XCTestCase {
    struct Tally {
        var total = 0
        var fine: [[ProcessStep]] = []
        var hard: [[ProcessStep]] = []
        var both: [[ProcessStep]] = []
    }

    func tally(_ space: [[ProcessStep]], orePercent: Int) -> Tally {
        var t = Tally()
        let ore = Matter.ironOre(purity: Purity(percent: orePercent))
        for steps in space {
            let r = ProcessChain.run(steps, input: ore)
            t.total += 1
            if r.isFinePlate { t.fine.append(steps) }
            if r.isHardPlate { t.hard.append(steps) }
            if r.isFinePlate && r.isHardPlate { t.both.append(steps) }
        }
        return t
    }

    func pct(_ n: Int, _ d: Int) -> String { String(format: "%.2f%%", Double(n) * 100 / Double(d)) }

    /// 各種類を高々 1 回(順番が違えば別の並び)。炉は燃料 2 通り。
    func testDistinctOrders() {
        let space = ChainSpace.distinctOrders()
        // 種類の並び 1956 通り(長さ 1〜6 の順列の和)。炉を含む 1631 通りは燃料で 2 倍 → 325 + 3262
        XCTAssertEqual(space.count, 3587)
        let t = tally(space, orePercent: 30)
        print("[到達] 各種類 1 回まで: 並び \(t.total) 通り / 精鉄板 \(t.fine.count) (\(pct(t.fine.count, t.total)))"
            + " / 剛鉄板 \(t.hard.count) (\(pct(t.hard.count, t.total)))"
            + " / 精かつ剛 \(t.both.count) (\(pct(t.both.count, t.total)))")
        for s in t.fine { print("  精鉄板: \(shorthand(s))") }

        XCTAssertFalse(t.fine.isEmpty)
        XCTAssertFalse(t.hard.isEmpty)
        XCTAssertFalse(t.both.isEmpty)
        // 大半は届かない
        XCTAssertLessThan(Double(t.fine.count) / Double(t.total), 0.01)
        XCTAssertLessThan(Double(t.hard.count) / Double(t.total), 0.2)
        // 試作 8 回の予算で無作為に引いて精鉄板に当たる見込みは 2 割を大きく下回る
        let p = Double(t.fine.count) / Double(t.total)
        XCTAssertLessThan(1 - pow(1 - p, 8), 0.2)
    }

    /// 同じ種類の繰り返しも許す(長さ 4 まで)。
    func testWithRepeats() {
        let space = ChainSpace.withRepeats(maxLength: 4)
        XCTAssertEqual(space.count, 7 + 49 + 343 + 2401)
        let t = tally(space, orePercent: 30)
        print("[到達] 繰り返しあり長さ 4 まで: 並び \(t.total) 通り / 精鉄板 \(t.fine.count) (\(pct(t.fine.count, t.total)))"
            + " / 剛鉄板 \(t.hard.count) (\(pct(t.hard.count, t.total)))")
        // 長さ 4 では精鉄板(砕・洗・混・熱・叩の 5 段が要る)に届かない
        XCTAssertTrue(t.fine.isEmpty)
        XCTAssertFalse(t.hard.isEmpty)
        XCTAssertLessThan(Double(t.hard.count) / Double(t.total), 0.2)
    }
}
