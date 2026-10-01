import XCTest
@testable import ReForgeCore

/// TEST-10: オラクル突合。原本(C#)の API モードに同じ操作を流した記録と、Swift 版の在庫の増減を比べる。
///
/// 記録の取り方(hub で実行): 原本の `./run.sh api` に 1 行 1 コマンドで
///   new_game → gather_water ×3 → advance_day を 8 回 / new_game → scavenge_capsule ×11(3 回)
/// を流し、応答 JSON の state.food / state.water と result.finds を抜き出した(2026-10-01、原本 master)。
/// 原本の乱数は Random.Shared(seed 指定不可)なので、確率項目は「範囲」と「回数」だけを比べる。
///
/// 突合する項目(§6.3 で Core と同値とした項目):
///   - 水汲み: Normal で +4
///   - 1 日の食料消費: 人口 5 で −5
///   - 残骸漁り: 保存食 2〜4、10 回で尽きる
/// 差を認めて除外する項目:
///   - 初期在庫: 原本の Normal は食料 10 のみ。MVP は §6.1 で 食料 25・水 18・木材 20・石材 5・鉄鉱石 5
///   - 水の消費: 原本は advance_day 中に雨などで水が増える(+3、+13 など)。MVP は 1 人 1 日 1 の固定
///   - 食料・水の上限: 原本は採取では上限を超え、日の変わり目で 60 に丸める。MVP は常に上限で止める
///   - 食料採取: 原本 API は確率型(40/20/15/25%)。MVP は固定 +4(§6.3)
///   - 伐採: 原本は石斧が無いと枝しか拾えない。MVP は道具なしで木材 +5
///   - 残骸漁りの副産物: 原本は水パック・植物繊維・枝・石の欠片も出る。MVP は保存食のみ
final class T10_OracleTests: XCTestCase {
    let g = Fixture.game

    // MARK: 原本の記録

    /// gather_water の 1 回ごとの増分(24 回)。
    static let oracleGatherWater = Array(repeating: 4, count: 24)
    /// advance_day 前後の食料(人口 5、食料が足りている日だけ)。
    static let oracleFoodAcrossDay: [(before: Int, after: Int)] = [(10, 5), (5, 0)]
    /// scavenge_capsule の保存食(3 走 × 10 回)と、11 回目の失敗。
    static let oracleScavenge: [[Int]] = [
        [2, 2, 4, 2, 2, 4, 3, 2, 3, 3],
        [3, 3, 2, 4, 4, 2, 2, 3, 2, 3],
        [2, 2, 4, 4, 2, 4, 2, 4, 2, 3],
    ]
    static let oracleScavengeRemaining = [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]

    // MARK: 突合

    func testGatherWaterMatchesOracle() {
        var s = g.newGame(seed: 0).with(ID.water, 0)
        s.actionPointsLeft = 100
        var deltas: [Int] = []
        for _ in 0..<24 {
            let before = s.quantity(ID.water)
            s = g.must(.gather(.water), s.with(ID.water, min(before, 40)))
            deltas.append(s.quantity(ID.water) - min(before, 40))
        }
        XCTAssertEqual(deltas, Self.oracleGatherWater)
    }

    func testDailyFoodConsumptionMatchesOracle() {
        for (before, after) in Self.oracleFoodAcrossDay {
            let s = g.idleDays(1, g.newGame(seed: 0).with(ID.food, before).with(ID.water, 30))
            XCTAssertEqual(s.quantity(ID.food), after)
        }
    }

    func testScavengeMatchesOracleRangeAndCount() {
        let oracleValues = Set(Self.oracleScavenge.joined())
        XCTAssertEqual(oracleValues, [2, 3, 4])
        var swiftValues = Set<Int>()
        for seed in UInt64(0)..<3 {
            var s = g.newGame(seed: seed)
            s.actionPointsLeft = 100
            var remaining: [Int] = []
            for _ in 0..<10 {
                let before = s.quantity(ID.ration)
                s = g.must(.gather(.scavenge), s)
                swiftValues.insert(s.quantity(ID.ration) - before)
                remaining.append(s.scavengeRemaining)
            }
            XCTAssertEqual(remaining, Self.oracleScavengeRemaining)
            XCTAssertEqual(g.perform(.gather(.scavenge), on: s), .failure(.scavengeExhausted))
        }
        XCTAssertEqual(swiftValues, oracleValues)
    }
}
