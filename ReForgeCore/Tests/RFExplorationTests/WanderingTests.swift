import RFContent
import RFExploration
import RFKernel
import RFMap
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// 歩いて探す: 新しい区画・POI に入ると、その場の表から探索の出来事を引く(原作 ExplorationEventDatabase.RollEvent)。
final class WanderingTests: XCTestCase {
    /// ノアを 1 マスずつ歩かせる(歩く仕組み(RFCrew)の代わりに位置を書き、1 ステップ進める)。
    private func walk(_ rig: inout ExploreRig, along cells: [GridPoint]) -> [DomainEvent] {
        var events: [DomainEvent] = []
        for c in cells {
            rig.put(.noah, c)
            events += rig.steps(1).events
        }
        return events
    }

    private func line(from a: GridPoint, to b: GridPoint) -> [GridPoint] {
        var out: [GridPoint] = []
        var p = a
        while p != b {
            p = GridPoint(p.x + (b.x > p.x ? 1 : b.x < p.x ? -1 : 0), p.y + (b.y > p.y ? 1 : b.y < p.y ? -1 : 0))
            out.append(p)
        }
        return out
    }

    func testNewRegionsRollTheFieldTableAndRangeGrows() throws {
        var rig = try ExploreRig(seed: 4)
        let start = rig.noahPos.point
        // 拠点の中を歩いても何も起きない
        let inside = walk(&rig, along: line(from: start, to: start + GridPoint(3, 1)))
        XCTAssertFalse(inside.contains { if case .explored = $0 { true } else { false } })
        // 拠点を出て北の端まで(区画 8×8 を 2 つまたぐ)、それから東の端まで
        let path = line(from: rig.noahPos.point, to: GridPoint(rig.noahPos.point.x, 0))
            + line(from: GridPoint(rig.noahPos.point.x, 0), to: GridPoint(31, 0))
        let events = walk(&rig, along: path)
        let explored = events.compactMap { e -> EventID? in if case .explored(_, let id, _) = e { id } else { nil } }
        let regions = rig.world.exploration.exploredRegions.values.reduce(0) { $0 + $1.countSet }
        XCTAssertGreaterThanOrEqual(regions, 3)
        XCTAssertEqual(explored.count, regions, "公開の平原の表は候補が尽きないので、新しい区画ごとに 1 件")
        XCTAssertEqual(explored.filter { $0 == "explore.test.plain.mark" }.count, 1, "一度きりは 1 回だけ")
        XCTAssertTrue(rig.world.research.unlocked.interactions.contains("interaction.test.u_plain"))
        XCTAssertFalse(explored.contains { $0.rawValue.contains(".river.") || $0.rawValue.contains(".rock.") })
        // 探索範囲: 拠点の中心から 16 マス → 1 + 16 / 8 = 3
        XCTAssertEqual(rig.world.exploration.farthest, 16)
        XCTAssertEqual(rig.world.exploration.range, 3)
        // 出来事は来歴に残り、得られた物はその来歴を指す
        let recs = rig.world.ledger.records.filter { $0.act == .discovered && $0.subject.kindKey.hasPrefix("event:") }
        XCTAssertEqual(recs.count, explored.count)
        XCTAssertTrue(recs.allSatisfy { $0.actor == .noah && $0.place != nil })
    }

    /// 場の表は地形で選ぶ。場の minRange に届かないうちは汎用の表だけ。
    func testFieldByTerrainAndFieldMinRange() throws {
        var rig = try ExploreRig(seed: 2) { c in c.fields["field.test.rock"]?.minRange = 3 }
        for y in 0..<32 { for x in 0..<32 where y < 12 { rig.world.map[.surface]?.setTerrain("rock", at: GridPoint(x, y)) } }
        let s = rig.noahPos.point
        // 範囲 1・2 のうちは岩山の表を引かない(汎用の quiet は範囲 2 から)
        var events = walk(&rig, along: line(from: s, to: GridPoint(s.x, 8)))
        var ids = events.compactMap { e -> EventID? in if case .explored(_, let id, _) = e { id } else { nil } }
        XCTAssertFalse(ids.contains { $0.rawValue.contains(".rock.") })
        // 範囲 3 に届いた後の新しい区画では岩山の表
        events = walk(&rig, along: line(from: GridPoint(s.x, 8), to: GridPoint(s.x, 0)) + line(from: GridPoint(s.x, 0), to: GridPoint(2, 0)))
        ids = events.compactMap { e -> EventID? in if case .explored(_, let id, _) = e { id } else { nil } }
        XCTAssertEqual(rig.world.exploration.range, 3)
        XCTAssertTrue(ids.contains("explore.test.rock.mark"))
    }

    /// POI のそばに来ると見つけて入り、初めてなら POI の場の表を引く。
    func testEnteringPOIDiscoversAndRollsPOIField() throws {
        var rig = try ExploreRig(seed: 6)
        let e = rig.world.newEntityID()
        let at = GridPoint(4, 4)
        rig.world.map[.surface]?.placements.place(MapPlacement(id: .farWreck, kind: .wreck, templateID: "wreck.far",
                                                               anchor: at, footprint: .rect(width: 2, height: 1),
                                                               isDiscovered: false, entity: e))
        let events = walk(&rig, along: line(from: rig.noahPos.point, to: at + GridPoint(0, 1)))
        XCTAssertTrue(events.contains(.entered(person: .noah, poi: e)))
        XCTAssertTrue(rig.world.knowledge.discovered.contains(e))
        XCTAssertEqual(rig.world.exploration.poi[e]?.visits, 1)
        XCTAssertEqual(rig.world.exploration.exploreFired["explore.test.wreck.look"], 1)
        // 遺品を調べる(1 回きり): 事実を知り、解禁が動き、唯一品が入る
        XCTAssertNil(rig.interact("interaction.search_far_wreck", at: at))
        XCTAssertTrue(rig.world.knowledge.knows("fact.test.beasts_read"))
        XCTAssertTrue(rig.world.research.unlocked.interactions.contains("interaction.test.u_relic"))
        XCTAssertNotNil(rig.world.inventory.entries(.base).first { $0.stuff == .item("test_relic_note") }?.unique)
        XCTAssertEqual(rig.interact("interaction.search_far_wreck", at: at)?.reason, "reason.explore.exhausted")
    }

    /// 遺品(在来生物の行動記録)を読んだ後は、森の表の危険の候補が重みの小さい方に替わる(when で分けた候補)。
    func testRelicLowersForestDanger() throws {
        var rig = try ExploreRig(seed: 1)
        for y in 0..<12 { for x in 0..<32 { rig.world.map[.surface]?.setTerrain("forest", at: GridPoint(x, y)) } }
        _ = walk(&rig, along: line(from: rig.noahPos.point, to: GridPoint(16, 8)))
        let before = rig.world.exploration.exploreFired
        XCTAssertNil(before["explore.test.forest.beast_read"])
        var ctx = StepContext(world: rig.world, content: rig.content)
        ctx.learn("fact.test.beasts_read")
        rig.world = ctx.world
        _ = walk(&rig, along: line(from: GridPoint(16, 8), to: GridPoint(16, 0)) + line(from: GridPoint(16, 0), to: GridPoint(0, 0)))
        XCTAssertEqual(rig.world.exploration.exploreFired["explore.test.forest.beast"], before["explore.test.forest.beast"],
                       "読んだ後は読む前の危険の候補を引かない")
    }

    func testSameSeedSameWalkSameEvents() throws {
        func run() throws -> [DomainEvent] {
            var rig = try ExploreRig(seed: 11)
            return walk(&rig, along: line(from: rig.noahPos.point, to: GridPoint(0, 0)) + line(from: GridPoint(0, 0), to: GridPoint(31, 31)))
        }
        XCTAssertEqual(try run(), try run())
    }
}
