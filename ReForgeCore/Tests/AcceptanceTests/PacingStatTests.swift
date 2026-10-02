import ReForgeEngine
import RFTestSupport
import XCTest
import Foundation

/// 非公開層の進行用数値が、期待値ファイルの予定どおりにしきい値へ届くこと。
final class PacingStatTests: XCTestCase {
    private static let expectationsFile = "tools/pacing-expectations.json"

    private static func expectedDays(in privateLayer: URL) throws -> [Int] {
        let data = try Data(contentsOf: privateLayer.appendingPathComponent(expectationsFile))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let days = object?["expectedDays"] as? [Int], !days.isEmpty else {
            throw NSError(domain: "PacingStatTests", code: 1)
        }
        return days
    }

    func testExpectationFileFormat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("tools"), withIntermediateDirectories: true)
        try "{\"expectedDays\":[7,11,19]}".write(to: directory.appendingPathComponent(Self.expectationsFile), atomically: true,
                                                      encoding: .utf8)
        XCTAssertEqual(try Self.expectedDays(in: directory), [7, 11, 19])
    }

    func testDeadlineStatReachesMarksOnSchedule() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開のコンテンツが無い(公開 CI では飛ばす)")
        guard let privateLayer = ContentLoader.privateLayer(publicLayer: TestContent.publicLayer,
                                                             environment: ProcessInfo.processInfo.environment),
              FileManager.default.fileExists(atPath: privateLayer.appendingPathComponent(Self.expectationsFile).path) else {
            throw XCTSkip("期待値ファイルが無い")
        }
        let expectedDays = try Self.expectedDays(in: privateLayer)
        var content = try TestContent.full()
        let candidates = content.stats.values.filter { ($0.perDay ?? 0) > 0 && $0.marks?.count == 3 && $0.wrap == nil }
        XCTAssertEqual(candidates.count, 1, "期限の数値の形のものが 1 つでない")
        guard let stat = candidates.first, let marks = stat.marks?.sorted() else { return }
        // 失敗で走行が止まらないように(届く日だけを見る)
        content.failureRules = [:]
        // 出来事は、この数値を足す・この数値を時間あたりに足す範囲の効果を付け外すものだけを残す(季節の上積み)。
        // 全部の出来事を毎ステップ調べると試験時間に収まらない
        let pacingAuras = Set(content.auras.values.filter { a in
            a.modifiers.contains { if case .statPerHour(let st, _) = $0 { st == stat.id } else { false } }
        }.map(\.id))
        func touches(_ e: Effect) -> Bool {
            switch e {
            case .stat(let id, _), .setStat(let id, _): id == stat.id
            case .addAura(let k, _, _, _, _), .removeAura(let k), .scaleAura(let k, _, _): pacingAuras.contains(k)
            default: false
            }
        }
        content.events = content.events.filter { $0.value.effects.contains(where: touches) }.mapValues { e in
            var e = e
            e.choices = nil
            e.blocking = nil
            return e
        }
        XCTAssertFalse(content.events.isEmpty, "季節の上積みの出来事が無い")
        let sim = Simulation(content: content, systems: [TimeSystem(), SurvivalSystem(), NarrativeSystem()])
        var world = WorldFactory(content: content, mapGenerator: RFMapGenerator()).newWorld(seed: 5)
        var reached: [Int?] = Array(repeating: nil, count: marks.count)
        let stepsPerDay = Int(TimeSystem.dayLength(content.clock).seconds / SimStep.gameSeconds)
        var steps = 0
        while reached.contains(where: { $0 == nil }), world.clock.day <= 240, steps < stepsPerDay * 250 {
            _ = sim.runSteps(1, &world)
            steps += 1
            let v = world.survival.stats[stat.id]?.raw ?? 0
            for (i, m) in marks.enumerated() where reached[i] == nil && v >= Int64(m) { reached[i] = world.clock.day }
        }
        for (i, want) in expectedDays.enumerated() {
            guard let got = reached[i] else {
                XCTFail("しきい値 \(i + 1) に予定範囲内で届かない")
                continue
            }
            XCTAssertLessThanOrEqual(abs(got - want), 1, "しきい値 \(i + 1) の到達日が期待値と違う")
        }
    }
}
