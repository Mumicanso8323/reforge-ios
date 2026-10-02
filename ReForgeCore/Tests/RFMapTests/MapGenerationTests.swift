import Foundation
import RFKernel
import XCTest
@testable import RFMap

/// 地図の生成: 決定性・大きさ・5 バイオーム・拠点の整地・目印の位置関係の保証(100 seed)。
/// 位置関係は生成側の測り方を写さず、テスト側で Pathfinder の経路を引いて測り直す。
final class MapGenerationTests: XCTestCase {
    // MARK: 決定性

    func testSameSeedSameMap() throws {
        let a = try WorldMap.generate(seed: 12345)
        let b = try WorldMap.generate(seed: 12345)
        XCTAssertEqual(a, b)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        XCTAssertEqual(try enc.encode(a), try enc.encode(b))
    }

    func testDifferentSeedsDiffer() throws {
        let a = try WorldMap.generate(seed: 1), b = try WorldMap.generate(seed: 2)
        XCTAssertNotEqual(a.landmarks, b.landmarks)
        var differing = 0
        for y in 0..<96 { for x in 0..<96 where a.biome(at: GridPoint(x, y)) != b.biome(at: GridPoint(x, y)) { differing += 1 } }
        XCTAssertGreaterThan(differing, 500)
    }

    func testUsesOnlyThePassedRandomOnce() throws {
        var r1 = SeededRandom(state: 99)
        let a = try WorldMap.generate(config: .r1, rng: &r1)
        var r2 = SeededRandom(state: 99)
        _ = r2.next()
        XCTAssertEqual(r1, r2, "生成は渡された乱数を 1 回だけ進める")
        XCTAssertEqual(a, try WorldMap.generate(seed: 99))
    }

    /// 地形と目印の固定の指紋。三角関数を使わない生成なので、端末・版が変わっても同じ値になる。
    /// 生成の手順を意図して変えたときだけ、ここの値を更新する。
    func testGoldenFingerprint() throws {
        func fingerprint(_ m: WorldMap) -> UInt64 {
            var h = FNV1a()
            let lm = m.lm
            for p in [lm.base.center, lm.mountainCenter, lm.forestCenter, lm.farWreck, lm.outcrop, lm.clayBank] { h.add(p) }
            h.add(lm.mountainRadius)
            for p in lm.river { h.add(p) }
            for p in lm.fords { h.add(p) }
            for y in 0..<m.size.height {
                for x in 0..<m.size.width { h.add(Int(m.biome(at: GridPoint(x, y))!.rawValue)) }
            }
            return h.value
        }
        let golden: [UInt64: UInt64] = [
            7: 0xf547_9d2d_24db_29e1,
            42: 0x3e88_7f2a_3fcf_305a,
            2026: 0x65ab_68af_c526_ac16,
        ]
        for (seed, want) in golden.sorted(by: { $0.key < $1.key }) {
            let got = fingerprint(try WorldMap.generate(seed: seed))
            XCTAssertEqual(got, want, "seed \(seed) の指紋 0x\(String(got, radix: 16))")
        }
    }

    func testPositionRelationsVaryBySeed() {
        var quadrants = Set<Int>()
        for m in MapFixture.r1Seeds {
            let d = m.lm.mountainCenter - m.lm.base.center
            quadrants.insert((d.x >= 0 ? 1 : 0) + (d.y >= 0 ? 2 : 0))
        }
        XCTAssertEqual(quadrants.count, 4)
    }

    // MARK: 失敗は投げる(黙って未検証の地図を返さない)

    func testEvery100SeedsVerifiedWithoutFallback() {
        var fallback = 0
        var attempts: [Int] = []
        for m in MapFixture.r1Seeds {
            let r = m.generationReport!
            if !r.verified { fallback += 1 }
            XCTAssertGreaterThanOrEqual(r.attempts, 1)
            XCTAssertLessThanOrEqual(r.attempts, m.config.maxLayoutAttempts)
            attempts.append(r.attempts)
        }
        XCTAssertEqual(fallback, 0, "保証を満たさない地図に落ちた seed がある")
        print("RFMap: 目印の試行回数 最大 \(attempts.max()!) / 中央 \(median(attempts.map(Double.init)))")
    }

    func testTooSmallMapThrows() {
        let c = MapGenerationConfig(size: GridSize(width: 40, height: 96))
        XCTAssertThrowsError(try WorldMap.generate(seed: 1, config: c)) { e in
            XCTAssertEqual(e as? MapGenerationError, .mapTooSmall(GridSize(width: 40, height: 96)))
        }
    }

    func testImpossibleRulesThrowUnlessFallbackAllowed() throws {
        var c = MapGenerationConfig.r1
        c.landmarks.forestOnShortcut = 500
        c.maxLayoutAttempts = 3
        XCTAssertThrowsError(try WorldMap.generate(seed: 1, config: c)) { e in
            XCTAssertEqual(e as? MapGenerationError, .layoutNotFound(attempts: 3))
        }
        c.allowUnverifiedFallback = true
        let m = try WorldMap.generate(seed: 1, config: c)
        XCTAssertEqual(m.generationReport, GenerationReport(attempts: 3, verified: false), "未検証は記録に残る")
    }

    // MARK: 大きさ

    func testR1SizeAndVariableSize() throws {
        XCTAssertEqual(MapFixture.r1Seed7.size, GridSize(width: 96, height: 96))
        XCTAssertTrue(MapFixture.r1Seed7.surface.terrain.isDense)

        let wide = try WorldMap.generate(seed: 3, config: MapGenerationConfig(size: GridSize(width: 160, height: 120)))
        XCTAssertEqual(wide.size, GridSize(width: 160, height: 120))
        XCTAssertEqual(wide.lm.base.center, GridPoint(80, 60))
        XCTAssertNil(wide.biome(at: GridPoint(160, 0)))
        XCTAssertNotNil(wide.biome(at: GridPoint(159, 119)))
        XCTAssertEqual(wide.generationReport?.verified, true)
        assertLandmarkGuarantees(wide, "160x120")
    }

    func testOriginalSizeIsProceduralAndDeterministic() throws {
        let a = try WorldMap.generate(seed: 5, config: .original)
        XCTAssertEqual(a.size, .original)
        XCTAssertFalse(a.surface.terrain.isDense, "原作の大きさは全マスを持たない")
        XCTAssertEqual(a.lm.base.center, GridPoint(5000, 5000))
        XCTAssertEqual(a.generatedChunks.count, 9)
        let b = try WorldMap.generate(seed: 5, config: .original)
        XCTAssertEqual(a, b)
        for p in [GridPoint(0, 0), GridPoint(9999, 9999), GridPoint(1234, 8765)] {
            XCTAssertEqual(a.biome(at: p), b.biome(at: p))
            XCTAssertNotNil(a.biome(at: p))
        }
        XCTAssertEqual(a.generationReport?.verified, true)
        assertLandmarkGuarantees(a, "original")
    }

    func testLazyChunksDoNotDependOnOrder() throws {
        var a = try WorldMap.generate(seed: 8, config: .original)
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
            XCTAssertGreaterThan(counts[.river] ?? 0, 0, "seed \(seed): 川の流れが無い")
            XCTAssertGreaterThan(counts[.ford] ?? 0, 0, "seed \(seed): 浅瀬が無い")
            let base = m.lm.base
            XCTAssertEqual(base.width, 11)
            XCTAssertEqual(base.height, 7)
            XCTAssertEqual(counts[.cleared], 77, "seed \(seed)")
            XCTAssertTrue(base.cells.allSatisfy { m.biome(at: $0) == .cleared })
            XCTAssertEqual(m.baseArea, GridRect(origin: base.minCorner, size: GridSize(width: 11, height: 7)))
            XCTAssertEqual(m.spawn, WorldPoint(.surface, base.center))
        }
    }

    func testHomeWreckAtBaseCenter() throws {
        let m = MapFixture.r1Seed7
        let home = try XCTUnwrap(m.surface.placements[.homeWreck])
        XCTAssertEqual(home.kind, .wreck)
        XCTAssertTrue(home.cells.contains(m.lm.base.center))
        XCTAssertTrue(home.cells.allSatisfy { m.lm.base.contains($0) })
        XCTAssertTrue(home.isDiscovered)
        XCTAssertEqual(home.remainingUses, 10)
    }

    // MARK: 川(流れは歩けない・浅瀬は高コストで渡れる・岸の水辺は歩ける)

    func testRiverIsImpassableExceptFordsAndEverythingIsReachable() {
        let costs = MoveCostTable.original
        XCTAssertNil(costs.cost(.river))
        XCTAssertEqual(costs.cost(.ford), 40)
        XCTAssertEqual(costs.cost(.water), 20)
        for (seed, m) in MapFixture.r1Seeds.enumerated() {
            let lm = m.lm
            // 中心線はつながっていて、流れか浅瀬
            for (a, b) in zip(lm.river, lm.river.dropFirst()) {
                XCTAssertEqual(max(abs(a.x - b.x), abs(a.y - b.y)), 1, "seed \(seed): 川が切れている")
            }
            XCTAssertTrue(lm.river.allSatisfy { m.biome(at: $0)!.isRiver }, "seed \(seed)")
            XCTAssertTrue(lm.fords.allSatisfy { m.biome(at: $0) == .ford }, "seed \(seed)")
            // 流れのマスは岸の水辺に接する(川沿いの道を歩ける)
            let riverCells = (0..<96).flatMap { y in (0..<96).map { GridPoint($0, y) } }.filter { m.biome(at: $0) == .river }
            XCTAssertTrue(riverCells.allSatisfy { p in
                p.neighbors8.contains { [.water, .ford, .river].contains(m.biome(at: $0)) }
            })
            // 拠点から通れるマスはすべて届く(川で切れた飛び地が無い。浅瀬で渡れる)
            var seen = Set<GridPoint>([lm.base.center])
            var queue = [lm.base.center]
            while let p = queue.popLast() {
                for q in p.neighbors8 where !seen.contains(q) {
                    guard let b = m.biome(at: q), costs.cost(b) != nil else { continue }
                    seen.insert(q)
                    queue.append(q)
                }
            }
            let passable = (0..<96 * 96).filter { i in costs.cost(m.biome(at: GridPoint(i % 96, i / 96))!) != nil }.count
            XCTAssertEqual(seen.count, passable, "seed \(seed): 拠点から届かない通れるマスがある")
        }
    }

    // MARK: 目印の位置関係の保証(100 seed、Pathfinder で測る)

    func testLandmarkGuaranteesOver100Seeds() {
        var forestSteps: [Double] = []
        var ratios: [Double] = []
        var nearRiver: [Double] = []
        for (seed, m) in MapFixture.r1Seeds.enumerated() {
            if let s = assertLandmarkGuarantees(m, "seed \(seed)") {
                forestSteps.append(Double(s.forestSteps))
                ratios.append(s.safeRatio)
                nearRiver.append(s.wreckRouteNearRiver)
            }
        }
        XCTAssertEqual(forestSteps.count, 100)
        print(String(format: "RFMap 実測(100 seed): 近道の森のマス 最小 %.0f / 中央 %.1f、森を避けた道のコスト比 最小 %.2f / 中央 %.2f、遠い残骸への道の川沿いの割合 最小 %.2f / 中央 %.2f",
                     forestSteps.min()!, median(forestSteps), ratios.min()!, median(ratios),
                     nearRiver.min()!, median(nearRiver)))
    }

    func testOutcropPurityVariesBySeed() {
        let purities = MapFixture.r1Seeds.map { $0.surface.deposits[.outcrop]!.purity.basisPoints }
        XCTAssertTrue(purities.allSatisfy { (2000...3500).contains($0) })
        XCTAssertLessThan(purities.min()!, 2300)
        XCTAssertGreaterThan(purities.max()!, 3200)
        XCTAssertGreaterThan(Set(purities).count, 10)
    }

    struct Measured {
        var forestSteps: Int
        var safeRatio: Double
        var wreckRouteNearRiver: Double
    }

    @discardableResult
    func assertLandmarkGuarantees(_ m: WorldMap, _ label: String,
                                  file: StaticString = #filePath, line: UInt = #line) -> Measured? {
        let r = m.config.landmarks
        let lm = m.lm
        let o = lm.base.center
        let L = m.surface
        func near(within radius: Int, _ match: (Biome) -> Bool) -> Double {
            var best = Double.infinity
            for y in (o.y - radius)...(o.y + radius) {
                for x in (o.x - radius)...(o.x + radius) {
                    if let b = L.biome(at: GridPoint(x, y)), match(b) { best = min(best, GridPoint(x, y).distance(to: o)) }
                }
            }
            return best
        }

        // 水辺: 最初の視界(昼の半径 8)の中に見える
        let water = near(within: 30) { $0.isWet }
        XCTAssertTrue(r.nearestWater.contains(water), "\(label): いちばん近い水 \(water)", file: file, line: line)
        XCTAssertLessThanOrEqual(water, Double(m.config.vision.baseRadius), "\(label): 最初の視界に水が入らない", file: file, line: line)

        // 拠点のまわりの輪に水・岩場・遺跡が無い
        for y in (lm.base.minCorner.y - r.baseClearance)...(lm.base.maxCorner.y + r.baseClearance) {
            for x in (lm.base.minCorner.x - r.baseClearance)...(lm.base.maxCorner.x + r.baseClearance) {
                let p = GridPoint(x, y)
                guard !lm.base.contains(p), let b = L.biome(at: p) else { continue }
                XCTAssertFalse(b.isWet || b == .rock || b == .ruins, "\(label): 拠点の輪 \(p) が \(b)", file: file, line: line)
            }
        }

        // 岩山
        let dM = lm.mountainCenter.distance(to: o)
        XCTAssertTrue(r.mountain.contains(dM), "\(label): 岩山 \(dM)", file: file, line: line)
        XCTAssertEqual(L.biome(at: lm.mountainCenter), .rock, "\(label)", file: file, line: line)

        // 露頭: 鉄で純度 20〜35%、岩場の上、拠点からいちばん近い岩場
        guard let outcrop = L.deposits[.outcrop] else {
            XCTFail("\(label): 露頭が無い", file: file, line: line)
            return nil
        }
        XCTAssertEqual(outcrop.category, .iron, file: file, line: line)
        XCTAssertTrue((2000...3500).contains(outcrop.purity.basisPoints), "\(label): 露頭の純度 \(outcrop.purity)", file: file, line: line)
        XCTAssertEqual(L.biome(at: outcrop.position), .rock, file: file, line: line)
        let dO = outcrop.position.distance(to: o)
        XCTAssertTrue(r.outcrop.contains(dO), "\(label): 露頭 \(dO)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(near(within: 40) { $0 == .rock }, dO - 0.0001, "\(label): 露頭より近い岩場がある", file: file, line: line)

        // 森: 拠点 → 露頭の最小コストの経路が森を N マス以上踏み、川(流れ・浅瀬)を渡らない。
        //     森を避けると最小コストの 1.2 倍以上かかる(森の近道は本当に安い)
        let dF = lm.forestCenter.distance(to: o)
        XCTAssertTrue(r.forest.contains(dF), "\(label): 森 \(dF)", file: file, line: line)
        guard let shortcut = truthPath(m, from: o, to: outcrop.position),
              let safe = truthPath(m, from: o, to: outcrop.position, avoid: [.forest]) else {
            XCTFail("\(label): 露頭へ届かない", file: file, line: line)
            return nil
        }
        let forestSteps = shortcut.steps.filter { L.biome(at: $0) == .forest }.count
        XCTAssertGreaterThanOrEqual(forestSteps, r.forestOnShortcut, "\(label): 近道の森 \(forestSteps)", file: file, line: line)
        XCTAssertFalse(shortcut.steps.contains { L.biome(at: $0)!.isRiver }, "\(label): 近道が川を渡る", file: file, line: line)
        XCTAssertFalse(safe.steps.contains { L.biome(at: $0) == .forest }, file: file, line: line)
        let ratio = Double(safe.cost) / Double(shortcut.cost)
        XCTAssertGreaterThanOrEqual(ratio, r.safeRouteCostRatio, "\(label): 森を避けた道が安すぎる \(ratio)", file: file, line: line)

        // 川: 岩山の脇を通る
        let toMountain = lm.river.map { $0.distance(to: lm.mountainCenter) }.min()!
        XCTAssertTrue(r.riverToMountain.contains(toMountain), "\(label): 川と岩山 \(toMountain)", file: file, line: line)

        // 遠い残骸: 川の「拠点の最寄り点 → 岩山の最寄り点」の弧の内側に射影される。
        //           拠点からの最小コストの経路は川沿い(中心線から 6 マス以内)を半分以上歩く。近道からは外れる
        guard let wreck = L.placements[.farWreck] else {
            XCTFail("\(label): 遠い残骸が無い", file: file, line: line)
            return nil
        }
        XCTAssertEqual(wreck.anchor, lm.farWreck, file: file, line: line)
        let dW = wreck.anchor.distance(to: o)
        XCTAssertTrue(r.farWreck.contains(dW), "\(label): 遠い残骸 \(dW)", file: file, line: line)
        XCTAssertTrue(wreck.cells.allSatisfy { !L.biome(at: $0)!.isWet }, file: file, line: line)
        let toRiver = distanceToRiver(m, wreck.anchor)
        XCTAssertLessThanOrEqual(toRiver, r.farWreckToRiver, "\(label)", file: file, line: line)
        func nearestIndex(_ p: GridPoint) -> Int {
            lm.river.indices.min { lm.river[$0].distanceSquared(to: p) < lm.river[$1].distanceSquared(to: p) }!
        }
        let iNear = nearestIndex(o), iM = nearestIndex(lm.mountainCenter), iW = nearestIndex(wreck.anchor)
        XCTAssertTrue(min(iNear, iM) < iW && iW < max(iNear, iM),
                      "\(label): 遠い残骸が拠点 → 岩山の弧の外 (\(iNear), \(iW), \(iM))", file: file, line: line)
        guard let wreckRoute = truthPath(m, from: o, to: wreck.anchor) else {
            XCTFail("\(label): 遠い残骸へ届かない", file: file, line: line)
            return nil
        }
        let along = Double(wreckRoute.steps.filter { distanceToRiver(m, $0) <= r.wreckRouteRiverBand }.count)
            / Double(wreckRoute.steps.count)
        XCTAssertGreaterThanOrEqual(along, r.wreckRouteNearRiver, "\(label): 遠い残骸への道が川沿いでない \(along)", file: file, line: line)
        let offShortcut = shortcut.steps.map { $0.distance(to: wreck.anchor) }.min()!
        XCTAssertGreaterThanOrEqual(offShortcut, r.farWreckOffShortcut, "\(label): 遠い残骸が近道の上 \(offShortcut)", file: file, line: line)

        // 川岸の土石(粘土)
        let clay = L.deposits[.clayBank]
        XCTAssertEqual(clay?.category, .quarry, file: file, line: line)
        if let c = clay { XCTAssertTrue(L.touchesWater(c.position), "\(label): 川岸の土石が水に接していない", file: file, line: line) }

        // 目印は地図の内側
        for p in [lm.mountainCenter, lm.forestCenter, lm.farWreck, lm.outcrop, lm.clayBank] {
            XCTAssertGreaterThanOrEqual(min(p.x, p.y, m.size.width - 1 - p.x, m.size.height - 1 - p.y), r.edgeMargin,
                                        "\(label): \(p) が端に近い", file: file, line: line)
        }
        return Measured(forestSteps: forestSteps, safeRatio: ratio, wreckRouteNearRiver: along)
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
                XCTAssertGreaterThan(m.lm.base.ringDistance(p.anchor), m.config.poiBaseExclusion)
                if let s = t.scrap { XCTAssertTrue(s.contains(p.remainingUses ?? -1)) }
                kinds.insert(p.kind)
            }
        }
        XCTAssertTrue(kinds.isSuperset(of: [.ruins, .nest, .fertileLand]), "\(kinds)")
        XCTAssertEqual(POICatalog.all.count, 11)
    }
}
