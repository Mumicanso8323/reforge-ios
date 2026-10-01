import Foundation
import XCTest
@testable import RFMap

/// 経路探索: 最短コスト(素朴なダイクストラと一致)・地形ごとのコスト・通れないマス・既知だけを通る。
final class PathfinderTests: XCTestCase {
    func testOriginalStaminaCosts() {
        let c = MoveCostTable.original
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.plain)!), 0.01)
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.forest)!), 0.02)
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.rock)!), 0.03)
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.cleared)!), 0.005)
        XCTAssertEqual(c.diagonalCost(.plain), 14, "斜めは 1.4 倍")
        XCTAssertEqual(c.diagonalCost(.rock), 42)
    }

    func testMatchesDijkstraOnGeneratedMaps() {
        var rng = SeededRandom(state: 2026)
        var checked = 0
        for m in MapFixture.r1Seeds.prefix(6) {
            let layer = m.surface
            for _ in 0..<10 {
                let s = GridPoint(rng.int(below: 96), rng.int(below: 96))
                let g = GridPoint(rng.int(below: 96), rng.int(below: 96))
                let opts = PathOptions(knownOnly: false)
                let path = layer.findPath(from: s, to: g, options: opts)
                let ref = referenceDijkstra(size: m.size, from: s, to: g, costs: .original) { layer.biome(at: $0) }
                XCTAssertEqual(path?.cost, ref, "\(s)→\(g)")
                if let path {
                    // 経路そのものを歩き直して同じコストになる
                    XCTAssertEqual(Pathfinder.cost(of: path.steps, from: s) { layer.biome(at: $0) }, path.cost)
                    XCTAssertEqual(path.steps.last ?? s, g)
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 60)
    }

    func testImpassableTerrainAndBlockedCells() {
        let m = MapFixture.r1Seed7
        let layer = m.surface
        let o = m.landmarks.base.center
        // 水辺を通れなくしても、川の向こうの遠い残骸へは回り道か届かないかのどちらか。経路に水辺は入らない
        let noWater = MoveCostTable.original.with(.water, nil)
        if let p = layer.findPath(from: o, to: m.landmarks.farWreck, costs: noWater, options: PathOptions(knownOnly: false)) {
            XCTAssertFalse(p.steps.contains { layer.biome(at: $0) == .water })
        }
        // 塞いだマスは通らない
        let direct = layer.findPath(from: o, to: o + GridPoint(6, 0), options: PathOptions(knownOnly: false))!
        let blocked = Set(direct.steps.dropLast())
        let detour = layer.findPath(from: o, to: o + GridPoint(6, 0), options: PathOptions(knownOnly: false, blocked: blocked))!
        XCTAssertTrue(detour.steps.allSatisfy { !blocked.contains($0) })
        XCTAssertGreaterThan(detour.cost, direct.cost)
        // 目的地が通れない地形なら nil
        let allBlocked = MoveCostTable.original.with(.cleared, nil)
        XCTAssertNil(layer.findPath(from: o + GridPoint(0, 10), to: o, costs: allBlocked, options: PathOptions(knownOnly: false)))
        // 同じマスなら空の経路
        XCTAssertEqual(layer.findPath(from: o, to: o), MapPath(steps: [], cost: 0))
    }

    func testKnownOnlyRespectsFog() {
        var m = MapFixture.r1Seed7
        let o = m.landmarks.base.center
        // 岩山はまだ霧の中: 既知だけを通る探索では届かない
        XCTAssertNil(m.findPath(from: o, to: m.landmarks.outcrop))
        XCTAssertNotNil(m.findPath(from: o, to: m.landmarks.outcrop, options: PathOptions(knownOnly: false)))
        // 歩いて視界を広げれば届く
        let route = m.findPath(from: o, to: m.landmarks.outcrop, options: PathOptions(knownOnly: false))!
        for p in route.steps { m.updateVision(at: p, isNight: false, hasTorch: false) }
        XCTAssertNotNil(m.findPath(from: o, to: m.landmarks.outcrop))
    }

    func testCheaperTerrainIsPreferred() {
        // 3 行の小さな地図: 中央の行は岩場、上の行は平地。左端から右端へは上を回る方が安い
        let size = MapSize(width: 9, height: 3)
        let biomeAt: (GridPoint) -> Biome? = { p in
            guard size.contains(p) else { return nil }
            if p.y == 1 && p.x > 0 && p.x < 8 { return .rock }
            if p.y == 2 { return nil }
            return .plain
        }
        let p = Pathfinder.findPath(size: size, from: GridPoint(0, 1), to: GridPoint(8, 1), biomeAt: biomeAt)!
        // 斜め上(14)→ 平地 6 マス(60)→ 斜め下(14)= 88。岩場をまっすぐなら 7×30+10 = 220
        XCTAssertEqual(p.cost, 88)
        XCTAssertEqual(p.steps.count, 8)
        XCTAssertEqual(p.stamina, 0.088, accuracy: 1e-9)
    }

    func testLargeMapUsesWindowAndStaysOptimalLocally() {
        let m = WorldMap.generate(seed: 11, config: .original)
        let o = m.landmarks.base.center
        let goal = m.landmarks.farWreck
        let path = m.findPath(from: o, to: goal, options: PathOptions(knownOnly: false))
        XCTAssertNotNil(path)
        XCTAssertEqual(path?.steps.last, goal)
    }
}
