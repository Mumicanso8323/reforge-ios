import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// TEST-R1-02 measures the generated W-05 bundle, or the neutral public copy
/// when the private layer is unavailable. Both fuel paths must beat the fully
/// heated hand-only route, catch up by dawn five, and remove hand mining.
final class ProductionBotTests: XCTestCase {
    func testR1_02_LineBeatsHandwork() throws {
        let count = Int(ProcessInfo.processInfo.environment["REFORGE_R1_02_SEEDS"] ?? "") ?? 100
        var minima: [LineBotPath: (ratio: Int, seed: UInt64)] = [:]

        for seed in UInt64(0)..<UInt64(count) {
            // Load per run: a generated layer may be present in the integrator's
            // environment, and ContentDB is intentionally not shared by runners.
            let loaded = try LineBotContent.load()
            let hand = LineBot.handOnly(content: loaded.content, seed: seed, days: 6)
            for path in [LineBotPath.A, .B] {
                let line = LineBot.line(content: loaded.content, seed: seed, path: path, days: 10)
                let handBest = (1...6).map { hand.plates[$0, default: 0] }.max() ?? 0
                let lineBest = (4...10).map { line.plates[$0, default: 0] }.max() ?? 0
                let ratio = handBest == 0 ? 0 : lineBest * 1000 / handBest
                if minima[path] == nil || ratio < minima[path]!.ratio { minima[path] = (ratio, seed) }

                XCTAssertEqual(hand.stalls + line.stalls, 0,
                               "W05|seed=\(seed)|path=\(path.rawValue)|clockStalled handDay=\(String(describing: hand.stallDay)) lineDay=\(String(describing: line.stallDay))")
                XCTAssertGreaterThan(handBest, 0, "W05|seed=\(seed)|path=\(path.rawValue)|handBest=0")
                XCTAssertGreaterThanOrEqual(lineBest * 2, handBest * 9,
                                            "W05|seed=\(seed)|path=\(path.rawValue)|lineBest=\(lineBest)|handBest=\(handBest)|ratioPermille=\(ratio)")
                XCTAssertGreaterThanOrEqual(line.platesOnHandAtDawn[5, default: 0], hand.platesOnHandAtDawn[5, default: 0],
                                            "W05|seed=\(seed)|path=\(path.rawValue)|dawn5 line=\(line.platesOnHandAtDawn[5, default: 0]) hand=\(hand.platesOnHandAtDawn[5, default: 0])")

                func handShare(_ day: Int) -> Int {
                    let handOre = line.handOre[day, default: 0]
                    let lineOre = line.lineOre[day, default: 0]
                    return handOre + lineOre == 0 ? 0 : handOre * 100 / (handOre + lineOre)
                }
                XCTAssertGreaterThanOrEqual(handShare(1), 80, "W05|seed=\(seed)|path=\(path.rawValue)|day=1")
                XCTAssertLessThanOrEqual(handShare(4), 30, "W05|seed=\(seed)|path=\(path.rawValue)|day=4")

                if seed == 0 {
                    let table = (1...10).map { day in
                        "d\(day),handPlate=\(hand.plates[day, default: 0]),linePlate=\(line.plates[day, default: 0]),handOre=\(line.handOre[day, default: 0]),lineOre=\(line.lineOre[day, default: 0]),hot=\(line.furnaceHotSeconds[day, default: 0]),charcoal=\(line.charcoalUsed[day, default: 0])"
                    }
                    let provisionTotal = line.provisioned.values.reduce(into: [ItemID: Int]()) { total, day in
                        for (item, quantity) in day { total[item, default: 0] += quantity }
                    }
                    print("W05|source=\(loaded.source.rawValue)|seed=0|path=\(path.rawValue)|table=\(table)|provisionTotal=\(provisionTotal)|shortfall=\(line.laborShortfall)|clamped=\(line.clamped)|holdRejections=\(line.holdRejections)/\(hand.holdRejections)|mineRejection=\(String(describing: line.mineRejection))/\(String(describing: hand.mineRejection))|handFavorable=woodYieldMin")
                }
            }
        }
        for path in [LineBotPath.A, .B] {
            let minimum = try XCTUnwrap(minima[path])
            print("W05|minRatioPermille=\(minimum.ratio)|seed=\(minimum.seed)|path=\(path.rawValue)")
        }
    }
}
