import Foundation
import RFKernel
import XCTest
@testable import RFMap

/// 経路探索: 最短コスト(素朴なダイクストラと一致)・地形ごとのコスト・角の切り抜け禁止・霧(タップの既定)・
/// 外から渡す既知・作業領域の使い回し・避ける地形。
final class PathfinderTests: XCTestCase {
    /// 文字で描く小さな層。'.' 平地 'f' 森 'r' 岩場 '~' 川の流れ 'w' 水辺 '=' 浅瀬
    private func layer(_ rows: [String]) -> MapLayer {
        let map: [Character: Biome] = [".": .plain, "f": .forest, "r": .rock, "~": .river, "w": .water, "=": .ford]
        let size = GridSize(width: rows[0].count, height: rows.count)
        let cells = rows.flatMap { $0.map { map[$0]! } }
        return MapLayer(id: .surface, terrain: TerrainGrid(size: size, cells: cells))
    }

    func testOriginalStaminaCosts() {
        let c = MoveCostTable.original
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.plain)!), 0.01)
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.forest)!), 0.02)
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.rock)!), 0.03)
        XCTAssertEqual(MoveCostTable.stamina(c.cost(.cleared)!), 0.005)
        XCTAssertNil(c.cost(.river), "川の流れは歩けない")
        XCTAssertEqual(c.cost(.ford), 40, "浅瀬は高コストで渡れる")
        XCTAssertEqual(c.diagonalCost(.plain), 14, "斜めは 1.4 倍")
        XCTAssertEqual(c.diagonalCost(.rock), 42)
    }

    func testMoveCostTableCodableIsKeyedByBiomeID() throws {
        let data = try JSONEncoder().encode(MoveCostTable.original)
        let dict = try JSONDecoder().decode([String: Int].self, from: data)
        XCTAssertEqual(dict["plain"], 10)
        XCTAssertEqual(dict["forest"], 20)
        XCTAssertNil(dict["river"])
        // 並びに依存しない(キーの順を入れ替えても同じ表)
        let json = #"{"rock":30,"ford":40,"plain":10,"water":20,"forest":20,"ruins":20,"cleared":5}"#
        XCTAssertEqual(try JSONDecoder().decode(MoveCostTable.self, from: Data(json.utf8)), .original)
    }

    func testMatchesDijkstraOnGeneratedMaps() {
        var rng = SeededRandom(state: 2026)
        let ws = PathWorkspace()
        var checked = 0
        for m in MapFixture.r1Seeds.prefix(6) {
            let layer = m.surface
            for _ in 0..<10 {
                let s = GridPoint(rng.int(below: 96), rng.int(below: 96))
                let g = GridPoint(rng.int(below: 96), rng.int(below: 96))
                let path = layer.route(from: s, to: g, options: .truth, workspace: ws).path
                let ref = referenceDijkstra(size: m.size, from: s, to: g, costs: .original) { layer.biome(at: $0) }
                XCTAssertEqual(path?.cost, ref, "\(s)→\(g)")
                if let path {
                    XCTAssertEqual(Pathfinder.cost(of: path.steps, from: s) { layer.biome(at: $0) }, path.cost)
                    XCTAssertEqual(path.steps.last ?? s, g)
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 60)
    }

    func testNoDiagonalCornerCutting() {
        // (0,0) → (1,1) の斜めは、(1,0) と (0,1) の両方が川なら通れない
        let l = layer([
            ".~.",
            "~..",
            "...",
        ])
        let p = l.findPath(from: GridPoint(0, 0), to: GridPoint(1, 1), options: .truth)
        XCTAssertNil(p, "通れない 2 マスの間の角は抜けない")
        XCTAssertNil(Pathfinder.cost(of: [GridPoint(1, 1)], from: GridPoint(0, 0)) { l.biome(at: $0) })
        // 片方が通れれば斜めに行ける
        let l2 = layer([
            "..",
            "~.",
        ])
        let p2 = l2.findPath(from: GridPoint(0, 0), to: GridPoint(1, 1), options: .truth)
        XCTAssertEqual(p2, MapPath(steps: [GridPoint(1, 1)], cost: 14))
    }

    func testRiverAndFord() {
        let l = layer([
            "..w~w..",
            "..w~w..",
            "..w=w..",
            "..w~w..",
        ])
        let p = l.findPath(from: GridPoint(0, 0), to: GridPoint(6, 0), options: .truth)!
        XCTAssertTrue(p.steps.contains(GridPoint(3, 2)), "浅瀬で渡る")
        XCTAssertFalse(p.steps.contains { l.biome(at: $0) == .river })
        // 浅瀬を通れなくすると届かない
        XCTAssertNil(l.findPath(from: GridPoint(0, 0), to: GridPoint(6, 0), options: PathOptions(fog: .ignore, avoid: [.ford])))
    }

    func testTapDefaultAssumesPlainInFogAndReplansAsFogClears() {
        var m = MapFixture.r1Seed7
        let o = m.lm.base.center
        let goal = m.lm.outcrop
        // 岩山はまだ霧の中: タップの既定は霧の先を平地と仮定して通す
        guard case .throughFog(let p, let firstUnknown) = m.route(from: o, to: goal) else {
            return XCTFail("霧の先へは throughFog")
        }
        XCTAssertFalse(m.surface.visibility.isKnown(p.steps[firstUnknown]))
        XCTAssertTrue(p.steps[..<firstUnknown].allSatisfy { m.surface.visibility.isKnown($0) })
        // 既知だけなら届かない
        XCTAssertEqual(m.route(from: o, to: goal, options: .knownOnly), .blocked)
        // 歩いて霧を晴らしながら引き直すと、最後は既知だけで届く
        var pos = o
        var replans = 0
        while true {
            let r = m.route(from: pos, to: goal)
            guard let path = r.path, !path.steps.isEmpty else { break }
            if case .known = r { break }
            replans += 1
            pos = path.steps[0]
            m.updateVision(at: pos, isNight: false, hasTorch: false)
            XCTAssertLessThan(replans, 200)
        }
        if case .known = m.route(from: pos, to: goal) {} else { XCTFail("晴れたら known") }
        XCTAssertGreaterThan(replans, 0)
    }

    func testBlockedByKnownWallsEvenWithFog() {
        // 目的地が既知の川で囲まれている → 霧があっても blocked
        var l = layer([
            ".....",
            ".~~~.",
            ".~.~.",
            ".~~~.",
            ".....",
        ])
        l.visibility.update(center: GridPoint(2, 2), radius: 3)
        XCTAssertEqual(l.route(from: GridPoint(0, 0), to: GridPoint(2, 2)), .blocked)
        // 霧の中の壁は知らないので、平地と仮定して通そうとする
        let l2 = layer([
            ".....",
            ".~~~.",
            ".~.~.",
            ".~~~.",
            ".....",
        ])
        if case .throughFog = l2.route(from: GridPoint(0, 0), to: GridPoint(2, 2)) {} else { XCTFail("知らない壁は通れると仮定") }
        XCTAssertEqual(l2.route(from: GridPoint(0, 0), to: GridPoint(2, 2), options: .truth), .blocked)
    }

    func testExternalKnowledgeAndWorkspaceReuse() {
        let l = layer([
            "......",
            "......",
            "......",
        ])
        let known: Set<GridPoint> = Set((0..<6).map { GridPoint($0, 0) })
        var opts = PathOptions(fog: .knownOnly, knowledge: .cells(known))
        XCTAssertEqual(l.route(from: GridPoint(0, 0), to: GridPoint(5, 0), options: opts).path?.cost, 50)
        XCTAssertEqual(l.route(from: GridPoint(0, 0), to: GridPoint(5, 2), options: opts), .blocked)
        var v = VisibilityLayer(size: l.size)
        v.markExplored(from: GridPoint(0, 0), to: GridPoint(5, 2))
        opts.knowledge = .visibility(v)
        if case .known = l.route(from: GridPoint(0, 0), to: GridPoint(5, 2), options: opts) {} else { XCTFail() }

        // 作業領域を大きさの違う地図で使い回しても、毎回新しく作ったときと同じ結果
        let ws = PathWorkspace()
        var rng = SeededRandom(state: 5)
        for m in [MapFixture.r1Seed7, MapFixture.r1Seeds[3]] {
            for _ in 0..<5 {
                let s = GridPoint(rng.int(below: 96), rng.int(below: 96))
                let g = GridPoint(rng.int(below: 96), rng.int(below: 96))
                XCTAssertEqual(m.surface.route(from: s, to: g, options: .truth, workspace: ws),
                               m.surface.route(from: s, to: g, options: .truth))
            }
            XCTAssertEqual(l.route(from: GridPoint(0, 0), to: GridPoint(5, 2), options: .truth, workspace: ws),
                           l.route(from: GridPoint(0, 0), to: GridPoint(5, 2), options: .truth))
        }
        XCTAssertGreaterThanOrEqual(ws.capacity, 96 * 96)
    }

    func testAvoidSetAndBlockedCells() {
        let m = MapFixture.r1Seed7
        let layer = m.surface
        let o = m.lm.base.center
        let safe = layer.findPath(from: o, to: m.lm.outcrop, options: PathOptions(fog: .ignore, avoid: [.forest]))!
        XCTAssertFalse(safe.steps.contains { layer.biome(at: $0) == .forest })
        // 霧の仮定の地形を避けるなら、霧は通れない
        XCTAssertEqual(layer.route(from: o, to: m.lm.outcrop, options: PathOptions(fog: .assume(.plain), avoid: [.plain])), .blocked)
        // 塞いだマスは通らない
        let direct = layer.findPath(from: o, to: o + GridPoint(6, 0), options: .truth)!
        let blocked = Set(direct.steps.dropLast())
        let detour = layer.findPath(from: o, to: o + GridPoint(6, 0), options: PathOptions(fog: .ignore, blocked: blocked))!
        XCTAssertTrue(detour.steps.allSatisfy { !blocked.contains($0) })
        XCTAssertGreaterThan(detour.cost, direct.cost)
        // 目的地が通れない地形なら blocked。同じマスなら空の経路
        XCTAssertNil(layer.findPath(from: o + GridPoint(0, 10), to: o, costs: MoveCostTable.original.with(.cleared, nil), options: .truth))
        XCTAssertEqual(layer.findPath(from: o, to: o), MapPath(steps: [], cost: 0))
    }

    func testCheaperTerrainIsPreferred() {
        let size = GridSize(width: 9, height: 3)
        let biomeAt: (GridPoint) -> Biome? = { p in
            guard size.contains(p) else { return nil }
            if p.y == 1 && p.x > 0 && p.x < 8 { return .rock }
            if p.y == 2 { return nil }
            return .plain
        }
        let p = Pathfinder.findPath(size: size, from: GridPoint(0, 1), to: GridPoint(8, 1), biomeAt: biomeAt)!
        XCTAssertEqual(p.cost, 88)
        XCTAssertEqual(p.steps.count, 8)
        XCTAssertEqual(p.stamina, 0.088, accuracy: 1e-9)
    }

    func testLargeMapUsesWindow() throws {
        let m = try WorldMap.generate(seed: 11, config: .original)
        let path = m.findPath(from: m.lm.base.center, to: m.lm.farWreck, options: .truth)
        XCTAssertEqual(path?.steps.last, m.lm.farWreck)
    }
}
