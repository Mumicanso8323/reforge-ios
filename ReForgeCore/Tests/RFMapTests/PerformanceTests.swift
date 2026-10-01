import Foundation
import XCTest
@testable import RFMap

/// 性能の目安。上限はデバッグビルドでも通る緩い値にし、実測を出力する。
final class PerformanceTests: XCTestCase {
    private func time<T>(_ body: () -> T) -> (T, Double) {
        let t0 = Date()
        let r = body()
        return (r, Date().timeIntervalSince(t0))
    }

    func testR1GenerationAndPathTimes() {
        var gen: [Double] = []
        var maps: [WorldMap] = []
        for s in 0..<10 {
            let (m, t) = time { WorldMap.generate(seed: UInt64(1000 + s)) }
            gen.append(t)
            maps.append(m)
        }
        var path: [Double] = []
        for m in maps {
            // 地図の端から端(全体を探す最悪に近い)
            let (_, t) = time { m.findPath(from: GridPoint(0, 0), to: GridPoint(95, 95), options: PathOptions(knownOnly: false)) }
            path.append(t)
            let (_, t2) = time { m.findPath(from: m.landmarks.base.center, to: m.landmarks.outcrop, options: PathOptions(knownOnly: false)) }
            path.append(t2)
        }
        let genMax = gen.max()!, genAvg = gen.reduce(0, +) / Double(gen.count)
        let pathMax = path.max()!, pathAvg = path.reduce(0, +) / Double(path.count)
        print(String(format: "RFMap 性能: 96x96 生成 平均 %.1f ms / 最大 %.1f ms、経路 平均 %.2f ms / 最大 %.2f ms",
                     genAvg * 1000, genMax * 1000, pathAvg * 1000, pathMax * 1000))
        XCTAssertLessThan(genMax, 3.0, "96×96 の生成が遅すぎる")
        XCTAssertLessThan(pathMax, 0.5, "96×96 の経路探索が遅すぎる")
    }

    func testOriginalSizeGenerationTime() {
        let (m, t) = time { WorldMap.generate(seed: 77, config: .original) }
        let (_, tp) = time { m.findPath(from: m.landmarks.base.center, to: m.landmarks.farWreck, options: PathOptions(knownOnly: false)) }
        print(String(format: "RFMap 性能: 10000x10000 生成 %.1f ms、経路(拠点→遠い残骸) %.2f ms", t * 1000, tp * 1000))
        XCTAssertLessThan(t, 10.0)
        XCTAssertLessThan(tp, 2.0)
    }
}
