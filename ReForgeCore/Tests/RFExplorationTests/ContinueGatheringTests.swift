import RFContent
import RFExploration
import RFKernel
import RFMap
import RFRules
import RFSim
import RFWorld
import XCTest

/// PT-B1 続けて採る(TEST-B1-1〜4・6・7、INV-B1-1〜3)。公開の層の試験用の採集の行為(中立の ID)に continues を付ける。
final class ContinueGatheringTests: XCTestCase {
    static let sticks: InteractionID = "interaction.pick_sticks"
    static let companion: PersonID = "person.test_a"

    func rig(continues: Bool = true, radius: Int? = nil, seed: UInt64 = 1) throws -> ExploreRig {
        try ExploreRig(seed: seed) { c in
            c.interactions[Self.sticks]?.continues = continues ? true : nil
            c.interactions[Self.sticks]?.continueRadius = radius
        }
    }

    /// 採れるマス(森)にして、見えている(知っている)ことにする。
    func forest(_ r: inout ExploreRig, _ cells: [GridPoint], known: Bool = true) {
        var k = r.world.knowledge.mapKnown[.surface] ?? GridBitset(size: r.world.map[.surface]!.size)
        for c in cells {
            r.world.map[.surface]?.setTerrain("forest", at: c)
            k[c] = known
        }
        r.world.knowledge.mapKnown[.surface] = k
    }

    func row(_ r: ExploreRig, _ n: Int, dy: Int = 0) -> [GridPoint] {
        (1...n).map { r.noahPos.point + GridPoint($0, dy) }
    }

    /// TEST-B1-1: 採れるマスが 3 つ並んだ地図で、押し続けると 3 単位が採れ、4 単位目で「近くにもう無い」で止まる。
    func testContinuesAcrossThreeCellsThenStops() throws {
        var r = try rig()
        r.steps(1)
        let cells = row(r, 3)
        forest(&r, cells)
        XCTAssertNil(r.interact(Self.sticks, at: cells[0]))
        XCTAssertEqual(r.records(.gathered).count, 3)
        XCTAssertEqual(Set(r.records(.gathered).compactMap(\.place?.point)), Set(cells), "3 つのマスを 1 回ずつ")
        XCTAssertNil(r.world.exploration.active[.noah], "止まった")
        XCTAssertEqual(r.world.exploration.continueStop?.interaction, Self.sticks)
        // 止まった後も 1 単位も増えない
        r.steps(200)
        XCTAssertEqual(r.records(.gathered).count, 3)
    }

    /// TEST-B1-2 / INV-B1-1: 1 回ずつ 3 回押した世界と、続けて 3 単位採った世界で、在庫と来歴の数が同じ。
    func testSameYieldsAsPressingOneByOne() throws {
        var a = try rig(continues: true, seed: 5)
        a.steps(1)
        let cells = row(a, 3)
        forest(&a, cells)
        XCTAssertNil(a.interact(Self.sticks, at: cells[0]))

        var b = try rig(continues: false, seed: 5)
        b.steps(1)
        forest(&b, cells)
        for c in cells {
            b.put(.noah, c)
            XCTAssertNil(b.interact(Self.sticks, at: c))
        }
        XCTAssertEqual(a.records(.gathered).count, 3)
        XCTAssertEqual(b.records(.gathered).count, 3)
        XCTAssertEqual(a.qty("stick"), b.qty("stick"))
        XCTAssertEqual(a.records(.gathered).map(\.tags), b.records(.gathered).map(\.tags))
        XCTAssertEqual(a.records(.gathered).map(\.detail), b.records(.gathered).map(\.detail))
        XCTAssertEqual(Set(a.records(.gathered).compactMap(\.place)), Set(b.records(.gathered).compactMap(\.place)))
    }

    /// TEST-B1-3 / INV-B1-2: 2 単位目の途中で離し、押し直すと続きから進む。
    func testReleaseKeepsProgressAndResumes() throws {
        var r = try rig()
        r.steps(1)
        let near = [r.noahPos.point + GridPoint(1, 0), r.noahPos.point + GridPoint(0, 1)]
        forest(&r, near)
        let at = { (g: GridPoint) in WorldPoint(.surface, g) }
        r.apply(.exploration(.interact(interaction: Self.sticks, at: at(near[0]), holding: true)))
        var n = 0
        while r.records(.gathered).count < 1 && n < 100 { r.steps(1); n += 1 }
        XCTAssertEqual(r.records(.gathered).count, 1)
        r.steps(1)
        let saved = try XCTUnwrap(r.world.exploration.active[.noah]).progress
        XCTAssertGreaterThan(saved, 0)
        // 離す(押した場所は 1 つ目のマスのまま。進行中は 2 つ目のマス)
        r.apply(.exploration(.interact(interaction: Self.sticks, at: at(near[0]), holding: false)))
        r.steps(20)
        let held = try XCTUnwrap(r.world.exploration.active[.noah])
        XCTAssertFalse(held.holding)
        XCTAssertEqual(held.progress, saved, "離している間は進まない・捨てない")
        // 押し直す
        r.apply(.exploration(.interact(interaction: Self.sticks, at: at(near[0]), holding: true)))
        XCTAssertEqual(r.world.exploration.active[.noah]?.progress, saved, "続きから")
        let seconds = Int64(try XCTUnwrap(r.content.interactions[Self.sticks]).seconds)
        let steps = Int((seconds - saved + SimStep.gameSeconds - 1) / SimStep.gameSeconds)
        r.steps(steps)
        XCTAssertEqual(r.records(.gathered).count, 2, "残りの時間だけで 2 単位目ができる")
    }

    /// TEST-B1-4 / INV-B1-3: 候補が同じ距離に複数あるとき、(距離, y, x) の小さい方を選ぶ。乱数を使わない。
    func testTieBreakIsDistanceThenYThenX() throws {
        var r = try rig()
        r.steps(1)
        let p = r.noahPos.point
        let cells = [p + GridPoint(3, 1), p + GridPoint(3, -1), p + GridPoint(-3, 0), p + GridPoint(0, 3)]
        forest(&r, cells)
        let def = try XCTUnwrap(r.content.interactions[Self.sticks])
        let before = r.world
        let pick = ContinueRules.next(interaction: def, from: r.noahPos, world: r.world, content: r.content)
        XCTAssertEqual(pick, WorldPoint(.surface, p + GridPoint(3, -1)), "距離 3 が 4 つ → y が一番小さいもの")
        XCTAssertEqual(r.world, before, "世界を変えない")
        for _ in 0..<5 {
            XCTAssertEqual(ContinueRules.next(interaction: def, from: r.noahPos, world: r.world, content: r.content), pick)
        }
        // 近い方が先(距離が違えば座標より距離)
        forest(&r, [p + GridPoint(2, 2)])
        XCTAssertEqual(ContinueRules.next(interaction: def, from: r.noahPos, world: r.world, content: r.content),
                       WorldPoint(.surface, p + GridPoint(2, 2)))
        // 半径の外は選ばない
        var narrow = try rig(radius: 1)
        narrow.steps(1)
        forest(&narrow, [narrow.noahPos.point + GridPoint(3, 0)])
        let nd = try XCTUnwrap(narrow.content.interactions[Self.sticks])
        XCTAssertNil(ContinueRules.next(interaction: nd, from: narrow.noahPos, world: narrow.world, content: narrow.content))
        // 見えていないマスは選ばない
        var hidden = try rig()
        hidden.steps(1)
        let h = hidden.noahPos.point + GridPoint(3, 0)
        forest(&hidden, [h], known: false)
        let hd = try XCTUnwrap(hidden.content.interactions[Self.sticks])
        XCTAssertNil(ContinueRules.next(interaction: hd, from: hidden.noahPos, world: hidden.world, content: hidden.content))
    }

    /// 同じマスでまだ採れるなら同じマス(回数の上限が残る行為)。
    func testStaysOnSameCellWhileItYields() throws {
        var r = try rig(seed: 2)
        r.steps(1)
        let cell = r.noahPos.point + GridPoint(1, 0)
        forest(&r, [cell])
        r.world.map[.surface]?.setTerrain("forest", at: cell)
        // クールダウン無し・回数 3 の行為にする
        var content = r.content
        content.interactions[Self.sticks]?.cooldownDays = nil
        content.interactions[Self.sticks]?.limit = 3
        r.content = content
        r.sim = Simulation(content: content)
        XCTAssertNil(r.interact(Self.sticks, at: cell))
        XCTAssertEqual(r.records(.gathered).count, 3)
        XCTAssertEqual(Set(r.records(.gathered).compactMap(\.place?.point)), [cell])
        XCTAssertNotNil(r.world.exploration.continueStop)
    }

    /// TEST-B1-6: 仲間の採取の配属で、配属のマスが尽きたら半径の中の次のマスへ移る。半径の外へは出ない。
    func testCompanionHopsInsideRadiusOnly() throws {
        var r = try rig(radius: 2)
        r.steps(1)
        let n = r.noahPos.point
        let home = n + GridPoint(0, 4)
        let inside = [home + GridPoint(1, 0), home + GridPoint(2, 0)]
        let outside = home + GridPoint(5, 0)
        forest(&r, [home] + inside + [outside])
        r.put(Self.companion, home + GridPoint(0, 1))
        r.world.people[Self.companion]?.assignment = .gather(interaction: Self.sticks, at: WorldPoint(.surface, home))
        // 配属のマスはもう採れない(クールダウン中)
        let key = ExplorationState.countKey(Self.sticks, poi: nil, at: WorldPoint(.surface, home))
        r.world.exploration.harvestedDay[key] = r.world.clock.day
        r.steps(1)
        guard case .gather(_, let first)? = r.world.people[Self.companion]?.assignment else { return XCTFail("配属が変わった") }
        XCTAssertNotEqual(first.point, home)
        XCTAssertTrue(inside.contains(first.point), "半径の中の次のマス(距離の小さい順)")
        XCTAssertEqual(first.point, inside[0])
        // 昼のうちに回し切る: 半径の中のマスが尽きても、半径の外へは出ない
        var n2 = 0
        while r.world.clock.phase == .day && n2 < 2_000 {
            r.steps(1)
            n2 += 1
            if case .gather(_, let at)? = r.world.people[Self.companion]?.assignment {
                XCTAssertLessThanOrEqual(at.point.chebyshev(to: home), 2, "配属の時の場所から半径 2 の中")
            }
        }
        let gathered = Set(r.records(.gathered).filter { $0.actor == Self.companion }.compactMap(\.place?.point))
        XCTAssertTrue(gathered.isSubset(of: Set(inside)), "採ったのは半径の中だけ: \(gathered)")
        XCTAssertFalse(gathered.isEmpty)
        XCTAssertFalse(gathered.contains(outside))
        XCTAssertNotNil(r.world.exploration.harvestedDay[ExplorationState.countKey(Self.sticks, poi: nil, at: WorldPoint(.surface, inside[1]))])
        XCTAssertNil(r.world.exploration.harvestedDay[ExplorationState.countKey(Self.sticks, poi: nil, at: WorldPoint(.surface, outside))])
    }

    /// TEST-B1-7: continues の無い行為は今とまったく同じ(1 単位で止まる)。
    func testWithoutContinuesStopsAfterOneUnit() throws {
        var r = try rig(continues: false)
        r.steps(1)
        let cells = row(r, 3)
        forest(&r, cells)
        XCTAssertNil(r.interact(Self.sticks, at: cells[0]))
        XCTAssertEqual(r.records(.gathered).count, 1)
        XCTAssertNil(r.world.exploration.active[.noah])
        XCTAssertNil(r.world.exploration.continueStop)
        r.steps(100)
        XCTAssertEqual(r.records(.gathered).count, 1)
    }

    /// 保存の形: 続けて採る前の状態は、新しい項目を書かない。
    func testSaveShapeUnchangedUntilContinuing() throws {
        let r = try rig()
        let data = try JSONEncoder().encode(r.world.exploration)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("continueHome"))
        XCTAssertFalse(text.contains("continueStop"))
        XCTAssertEqual(try JSONDecoder().decode(ExplorationState.self, from: data), r.world.exploration)
    }
}
