import ReForgeEngine
import RFTestSupport
import XCTest

/// 期限の数値(日ごとに上がり、しきい値を 3 つ持つ拠点全体の数値)が、何もしなければ決めた日にしきい値へ届くこと。
/// 届く日は Day 80・120・150(±1 日)。炉の数とは連動しない(置いた物の数で変わらない)ので、時間・生存・出来事の
/// システムだけで回す。季節の上積みは非公開の層の出来事(範囲の効果)なので、非公開の層があるときだけ回す。
///
/// どの数値かは名前で書かず、形で選ぶ(perDay があり、しきい値が 3 つで、暦のように回らない数値はただ 1 つ)。
final class PacingStatTests: XCTestCase {
    static let expectedDays = [80, 120, 150]

    func testDeadlineStatReachesMarksOnSchedule() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開のコンテンツが無い(公開 CI では飛ばす)")
        var content = try TestContent.full()
        let candidates = content.stats.values.filter { ($0.perDay ?? 0) > 0 && $0.marks?.count == 3 && $0.wrap == nil }
        XCTAssertEqual(candidates.count, 1, "期限の数値の形のものが 1 つでない")
        guard let stat = candidates.first, let marks = stat.marks?.sorted() else { return }
        // 失敗で走行が止まらないように(届く日だけを見る)
        content.failureRules = [:]
        let sim = Simulation(content: content, systems: [TimeSystem(), SurvivalSystem(), NarrativeSystem()])
        var world = WorldFactory(content: content, mapGenerator: RFMapGenerator()).newWorld(seed: 5)
        var reached: [Int?] = Array(repeating: nil, count: marks.count)
        let stepsPerDay = Int(TimeSystem.dayLength(content.clock).seconds / SimStep.gameSeconds)
        var steps = 0
        while reached.contains(where: { $0 == nil }), world.clock.day <= 200, steps < stepsPerDay * 210 {
            _ = sim.runSteps(1, &world)
            steps += 1
            let v = world.survival.stats[stat.id]?.raw ?? 0
            for (i, m) in marks.enumerated() where reached[i] == nil && v >= Int64(m) { reached[i] = world.clock.day }
        }
        for (i, want) in Self.expectedDays.enumerated() {
            guard let got = reached[i] else {
                XCTFail("しきい値 \(i + 1) に Day 200 までに届かない")
                continue
            }
            XCTAssertLessThanOrEqual(abs(got - want), 1, "しきい値 \(i + 1) に届いた日 Day \(got)(決めた日は Day \(want))")
        }
    }
}
