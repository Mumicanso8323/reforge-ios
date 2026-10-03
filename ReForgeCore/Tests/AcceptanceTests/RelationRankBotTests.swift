import ReForgeEngine
import RFTestSupport
import XCTest

/// R1 レビュー L5(担当 U14): 関係ランクを条件にした手がかり(仲間の専門知識、order.md §5.4)は、毎晩焚き火で
/// 話すだけで届く。手がかりの条件(person(id, relationAtLeast(n)))から相手とランクを読み、毎晩話すボットで確かめる。
///
/// - 関係の数え方だけを見るので、失敗の規則は外し、毎朝体の値を満たす(飢えで走行が止まらないように)。
/// - 公開の層には関係ランクの手がかりが無いので、非公開の層があるときだけ回す。
final class RelationRankBotTests: XCTestCase {
    /// 序を読み終え、暗い場面の行為(最初の行為)を済ませる。時計の保留が最初の行為でだけ解ける内容(PT-B8 の firstAct)でも、
    /// ボットが日を進められるように。保留の無い内容では何もしない。
    private func startFirstAct(_ sim: Simulation, _ content: ContentDB, _ world: inout WorldState) {
        var n = 0
        while world.clock.held && world.narrative.scene != nil && n < 30 {
            _ = sim.apply(.narrative(.advanceScene), to: &world)
            n += 1
        }
        guard world.clock.held,
              let act = FrameBuilder(content: content).build(world, revision: 0, previous: nil, report: nil).darkStart?.action
        else { return }
        _ = sim.apply(act.start, to: &world)
        // 保留の間、最初の行為は押している実時間でだけ進む(画面のタイマーの代わり)
        var carry: Int64 = 0
        n = 0
        while world.clock.held && n < 20000 {
            _ = sim.advanceHeld(&world, realSeconds: 1.0 / 10, carry: &carry)
            n += 1
        }
        _ = sim.apply(act.end, to: &world)
        XCTAssertFalse(world.clock.held, "最初の行為で時計の保留が解けない")
    }

    /// 毎晩話して、相手がランク `rank` に届いた夜(届かなければ nil)。
    private func nightsToRank(content base: ContentDB, person: PersonID, rank: Int, maxNights: Int) -> Int? {
        var content = base
        content.failureRules = [:]
        let sim = Simulation(content: content)
        var world = WorldFactory(content: content, mapGenerator: RFMapGenerator()).newWorld(seed: 3)
        startFirstAct(sim, content, &world)
        for night in 1...maxNights {
            var n = 0
            while world.clock.phase == .day && n < 20000 {
                _ = sim.runSteps(1, &world)
                n += 1
            }
            _ = sim.apply(.time(.startNightWork), to: &world)
            let r = sim.apply(.crew(.talk(person: person)), to: &world)
            XCTAssertNil(r.rejection, "夜 \(night): 話せない \(String(describing: r.rejection))")
            if (world.people[person]?.relation.rank ?? 0) >= rank { return night }
            _ = sim.apply(.time(.sleep), to: &world)
            for id in content.people.keys {
                world.people[id]?.body.satiety = Milli(100)
                world.people[id]?.body.hydration = Milli(100)
            }
        }
        return nil
    }

    func testRankHintsAreReachableByTalkingEveryNight() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開のコンテンツが無い(公開 CI では飛ばす)")
        let content = try TestContent.full()
        var targets: [PersonID: Int] = [:]
        for hint in content.hints.values {
            guard case .person(let id, .relationAtLeast(let rank)) = hint.when else { continue }
            targets[id] = max(targets[id] ?? 0, rank)
        }
        XCTAssertFalse(targets.isEmpty, "関係ランクを条件にした手がかりが無い")
        for (person, rank) in targets.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let night = nightsToRank(content: content, person: person, rank: rank, maxNights: 20)
            XCTAssertNotNil(night, "\(person) がランク \(rank) に 20 夜で届かない")
            print("[R1-L5] \(person) ランク \(rank): \(night.map { "\($0) 夜目" } ?? "届かない")")
        }
    }
}
