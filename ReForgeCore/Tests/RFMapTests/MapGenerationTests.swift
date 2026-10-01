import Foundation
import XCTest
@testable import RFMap

/// 地図の生成: 決定性・大きさ・5 バイオーム・拠点の整地・目印の位置関係の保証(100 seed)。
final class MapGenerationTests: XCTestCase {
    // MARK: 決定性

    func testSameSeedSameMap() throws {
        let a = WorldMap.generate(seed: 12345)
        let b = WorldMap.generate(seed: 12345)
        XCTAssertEqual(a, b)
        // 保存の形(JSON)まで同じ
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        XCTAssertEqual(try enc.encode(a), try enc.encode(b))
    }

    func testDifferentSeedsDiffer() {
        let a = WorldMap.generate(seed: 1), b = WorldMap.generate(seed: 2)
        XCTAssertNotEqual(a.landmarks, b.landmarks)
        var differing = 0
        for y in 0..<96 { for x in 0..<96 where a.biome(at: GridPoint(x, y)) != b.biome(at: GridPoint(x, y)) { differing += 1 } }
        XCTAssertGreaterThan(differing, 500)
    }

    func testUsesOnlyThePassedRandomOnce() {
        var r1 = SeededRandom(state: 99)
        let a = WorldMap.generate(config: .r1, rng: &r1)
        var r2 = SeededRandom(state: 99)
        _ = r2.next()
        XCTAssertEqual(r1, r2, "生成は渡された乱数を 1 回だけ進める")
        XCTAssertEqual(a, WorldMap.generate(seed: 99))
    }

    func testPositionRelationsVaryBySeed() {
        // 拠点から見た岩山の向きが seed ごとに変わる(4 象限すべてに出る)
        var quadrants = Set<Int>()
        for m in MapFixture.r1Seeds {
            let d = m.landmarks.mountainCenter - m.landmarks.base.center
            quadrants.insert((d.x >= 0 ? 1 : 0) + (d.y >= 0 ? 2 : 0))
        }
        XCTAssertEqual(quadrants.count, 4)
    }

    // MARK: 大きさ

    func testR1SizeAndVariableSize() {
        XCTAssertEqual(MapFixture.r1Seed7.size, MapSize(width: 96, height: 96))
        XCTAssertTrue(MapFixture.r1Seed7.surface.terrain.isDense)

        let wide = WorldMap.generate(seed: 3, config: MapGenerationConfig(size: MapSize(width: 160, height: 120)))
        XCTAssertEqual(wide.size, MapSize(width: 160, height: 120))
        XCTAssertEqual(wide.landmarks.base.center, GridPoint(80, 60))
        XCTAssertNil(wide.biome(at: GridPoint(160, 0)))
        XCTAssertNotNil(wide.biome(at: GridPoint(159, 119)))
    }

    func testOriginalSizeIsProceduralAndDeterministic() {
        let a = WorldMap.generate(seed: 5, config: .original)
        XCTAssertEqual(a.size, .original)
        XCTAssertFalse(a.surface.terrain.isDense, "原作の大きさは全マスを持たない")
        XCTAssertEqual(a.landmarks.base.center, GridPoint(5000, 5000))
        // 拠点まわりの 3×3 チャンクだけ POI と鉱脈を置く
        XCTAssertEqual(a.generatedChunks.count, 9)
        let b = WorldMap.generate(seed: 5, config: .original)
        XCTAssertEqual(a, b)
        // 遠くのマスも必要なときに同じ地形が出る
        for p in [GridPoint(0, 0), GridPoint(9999, 9999), GridPoint(1234, 8765)] {
            XCTAssertEqual(a.biome(at: p), b.biome(at: p))
            XCTAssertNotNil(a.biome(at: p))
        }
        // 目印の保証は大きい地図でも同じ
        assertLandmarkGuarantees(a, "original")
    }

    func testLazyChunksDoNotDependOnOrder() {
        var a = WorldMap.generate(seed: 8, config: .original)
        var b = a
        a.ensureGenerated(around: GridPoint(5300, 5000), radiusChunks: 1)
        a.ensureGenerated(around: GridPoint(5000, 5300), radiusChunks: 1)
        b.ensureGenerated(around: GridPoint(5000, 5300), radiusChunks: 1)
        b.ensureGenerated(around: GridPoint(5300, 5000), radiusChunks: 1)
        XCTAssertEqual(a, b)
        XCTAssertGreaterThan(a.generatedChunks.count, 9)
    }

    // MARK: バイオームと拠点

    func testFiveBiomesAndBaseClearing() {
        for (seed, m) in MapFixture.r1Seeds.enumerated() {
            var counts: [Biome: Int] = [:]
            for y in 0..<96 { for x in 0..<96 { counts[m.biome(at: GridPoint(x, y))!, default: 0] += 1 } }
            for b in Biome.natural {
                XCTAssertGreaterThan(counts[b] ?? 0, 0, "seed \(seed): \(b) が無い")
            }
            // 拠点の整地は 11×7 = 77 マスちょうど
            let base = m.landmarks.base
            XCTAssertEqual(base.width, 11)
            XCTAssertEqual(base.height, 7)
            XCTAssertEqual(counts[.cleared], 77, "seed \(seed)")
            XCTAssertTrue(base.cells.allSatisfy { m.biome(at: $0) == .cleared })
        }
    }

    func testHomeWreckAtBaseCenter() {
        let m = MapFixture.r1Seed7
        let home = try! XCTUnwrap(m.surface.placements[.homeWreck])
        XCTAssertEqual(home.kind, .wreck)
        XCTAssertTrue(home.cells.contains(m.landmarks.base.center))
        XCTAssertTrue(home.cells.allSatisfy { m.landmarks.base.contains($0) })
        XCTAssertTrue(home.isDiscovered)
        XCTAssertEqual(home.remainingUses, 10)
    }

    // MARK: 目印の位置関係の保証(100 seed)

    func testLandmarkGuaranteesOver100Seeds() {
        for (seed, m) in MapFixture.r1Seeds.enumerated() {
            assertLandmarkGuarantees(m, "seed \(seed)")
        }
    }

    func testOutcropPurityVariesBySeed() {
        // 露頭の純度は seed ごとに 20〜35% の幅で散らばる(粗鉄塊〜鉄塊の境目をまたぐ)
        let purities = MapFixture.r1Seeds.map { $0.surface.deposits[.outcrop]!.purity.basisPoints }
        XCTAssertTrue(purities.allSatisfy { (2000...3500).contains($0) })
        XCTAssertLessThan(purities.min()!, 2300)
        XCTAssertGreaterThan(purities.max()!, 3200)
        XCTAssertGreaterThan(Set(purities).count, 10)
    }

    /// 生成側の検証関数を使わず、テスト側で測り直す。
    func assertLandmarkGuarantees(_ m: WorldMap, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let r = m.config.landmarks
        let lm = m.landmarks
        let o = lm.base.center
        let L = m.surface
        func near(_ b: Biome, within radius: Int) -> Double {
            var best = Double.infinity
            for y in (o.y - radius)...(o.y + radius) {
                for x in (o.x - radius)...(o.x + radius) where L.biome(at: GridPoint(x, y)) == b {
                    best = min(best, GridPoint(x, y).distance(to: o))
                }
            }
            return best
        }

        // 水辺: 最初の視界(昼の半径 8)の中に見える。整地のすぐ脇には無い
        let water = near(.water, within: 30)
        XCTAssertTrue(r.nearestWater.contains(water), "\(label): いちばん近い水辺 \(water)", file: file, line: line)
        XCTAssertLessThanOrEqual(water, Double(m.config.vision.baseRadius), "\(label): 最初の視界に水辺が入らない", file: file, line: line)

        // 拠点のまわりの輪に水辺・岩場・遺跡が無い
        for y in (lm.base.minCorner.y - r.baseClearance)...(lm.base.maxCorner.y + r.baseClearance) {
            for x in (lm.base.minCorner.x - r.baseClearance)...(lm.base.maxCorner.x + r.baseClearance) {
                let p = GridPoint(x, y)
                guard !lm.base.contains(p) else { continue }
                XCTAssertFalse([Biome.water, .rock, .ruins].contains(L.biome(at: p)!), "\(label): 拠点の輪 \(p)", file: file, line: line)
            }
        }

        // 岩山
        let dM = lm.mountainCenter.distance(to: o)
        XCTAssertTrue(r.mountain.contains(dM), "\(label): 岩山 \(dM)", file: file, line: line)
        XCTAssertEqual(L.biome(at: lm.mountainCenter), .rock, "\(label)", file: file, line: line)

        // 露頭: 鉄の鉱脈で純度 20〜35%、岩場の上、拠点からいちばん近い岩場
        let outcrop = L.deposits[.outcrop]
        XCTAssertNotNil(outcrop, "\(label): 露頭が無い", file: file, line: line)
        if let d = outcrop {
            XCTAssertEqual(d.category, .iron, file: file, line: line)
            XCTAssertTrue((2000...3500).contains(d.purity.basisPoints), "\(label): 露頭の純度 \(d.purity)", file: file, line: line)
            XCTAssertEqual(L.biome(at: d.position), .rock, file: file, line: line)
            let dist = d.position.distance(to: o)
            XCTAssertTrue(r.outcrop.contains(dist), "\(label): 露頭 \(dist)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(near(.rock, within: 40), dist - 0.0001, "\(label): 露頭より近い岩場がある", file: file, line: line)
        }

        // 森: 拠点と岩山の間にあり、直線(近道)が森を通る。直線は川を渡らない
        let dF = lm.forestCenter.distance(to: o)
        XCTAssertTrue(r.forest.contains(dF), "\(label): 森 \(dF)", file: file, line: line)
        XCTAssertLessThan(dF, dM, file: file, line: line)
        let shortcut = lineCells(o, lm.mountainCenter)
        let forestOnLine = shortcut.filter { L.biome(at: $0) == .forest }.count
        XCTAssertGreaterThanOrEqual(forestOnLine, r.forestOnShortcut, "\(label): 近道の森 \(forestOnLine)", file: file, line: line)
        XCTAssertFalse(shortcut.contains { L.biome(at: $0) == .water }, "\(label): 近道が川を渡る", file: file, line: line)

        // 川: 中心線はつながっていて水辺。岩山の脇を通る。川沿いは直線より遠回り
        XCTAssertFalse(lm.river.isEmpty, file: file, line: line)
        for (a, b) in zip(lm.river, lm.river.dropFirst()) {
            XCTAssertEqual(a.chebyshev(to: b), 1, "\(label): 川が切れている \(a)→\(b)", file: file, line: line)
        }
        XCTAssertTrue(lm.river.allSatisfy { L.biome(at: $0) == .water }, "\(label): 川の中心線が水辺でない", file: file, line: line)
        let toMountain = lm.river.map { $0.distance(to: lm.mountainCenter) }.min()!
        XCTAssertTrue(r.riverToMountain.contains(toMountain), "\(label): 川と岩山 \(toMountain)", file: file, line: line)
        let iNear = lm.river.indices.min { lm.river[$0].distanceSquared(to: o) < lm.river[$1].distanceSquared(to: o) }!
        let iM = lm.river.indices.min { lm.river[$0].distanceSquared(to: lm.mountainCenter) < lm.river[$1].distanceSquared(to: lm.mountainCenter) }!
        var arc = 0.0
        for i in min(iNear, iM)..<max(iNear, iM) { arc += lm.river[i].distance(to: lm.river[i + 1]) }
        let route = lm.river[iNear].distance(to: o) + arc + lm.river[iM].distance(to: lm.mountainCenter)
        XCTAssertGreaterThanOrEqual(route / dM, r.riverDetourRatio, "\(label): 川沿いが遠回りでない", file: file, line: line)

        // 遠い残骸: 川のそば、近道から外れ、距離の範囲の中
        let wreck = L.placements[.farWreck]
        XCTAssertNotNil(wreck, "\(label): 遠い残骸が無い", file: file, line: line)
        if let w = wreck {
            XCTAssertEqual(w.anchor, lm.farWreck, file: file, line: line)
            let dW = w.anchor.distance(to: o)
            XCTAssertTrue(r.farWreck.contains(dW), "\(label): 遠い残骸 \(dW)", file: file, line: line)
            let toRiver = lm.river.map { $0.distance(to: w.anchor) }.min()!
            XCTAssertLessThanOrEqual(toRiver, r.farWreckToRiver, "\(label)", file: file, line: line)
            XCTAssertTrue(w.cells.allSatisfy { L.biome(at: $0) != .water }, file: file, line: line)
            let offLine = shortcut.map { $0.distance(to: w.anchor) }.min()!
            XCTAssertGreaterThanOrEqual(offLine, r.farWreckOffShortcut - 1, "\(label): 遠い残骸が近道の上 \(offLine)", file: file, line: line)
        }

        // 川岸の土石(粘土)
        let clay = L.deposits[DepositID("deposit.claybank")]
        XCTAssertEqual(clay?.category, .quarry, file: file, line: line)
        if let c = clay { XCTAssertTrue(L.touchesWater(c.position), "\(label): 川岸の土石が水に接していない", file: file, line: line) }

        // 目印は地図の内側
        for p in [lm.mountainCenter, lm.forestCenter, lm.farWreck, lm.outcrop, lm.clayBank] {
            XCTAssertTrue(m.size.contains(p), file: file, line: line)
            XCTAssertGreaterThanOrEqual(min(p.x, p.y, m.size.width - 1 - p.x, m.size.height - 1 - p.y), r.edgeMargin, "\(label): \(p) が端に近い", file: file, line: line)
        }
    }

    // MARK: POI

    func testPOIsFollowTemplates() {
        var kinds = Set<PlacementKind>()
        for m in MapFixture.r1Seeds.prefix(30) {
            for p in m.surface.placements.all where p.id.rawValue.hasPrefix("poi.") {
                let t = POICatalog.template(POITemplateID(p.templateID))
                XCTAssertNotNil(t)
                guard let t else { continue }
                XCTAssertEqual(p.kind, t.kind)
                XCTAssertTrue(p.cells.allSatisfy { t.biomes.contains(m.biome(at: $0)!) }, "\(p.id) のバイオーム")
                XCTAssertGreaterThan(m.landmarks.base.ringDistance(p.anchor), m.config.poiBaseExclusion)
                if let s = t.scrap { XCTAssertTrue(s.contains(p.remainingUses ?? -1)) }
                kinds.insert(p.kind)
            }
        }
        XCTAssertTrue(kinds.isSuperset(of: [.ruins, .nest, .fertileLand]), "\(kinds)")
        XCTAssertEqual(POICatalog.all.count, 11)
    }
}
