import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// 最初の「火を起こす」(効果 placeStructure)が、どの種でも残骸のそばに焚き火台を置けること(W-12 に足した保証)。
/// 置けるかは本体の規則 StructureSites で判定する(建てるコマンドと効果が使うものと同じ)。
/// 種の数は REFORGE_FIRSTFIRE_SEEDS(手元の既定 20。CI は多く)。非公開の層があれば本物の焚き火台の定義で確かめる。
final class FirstFireSiteTests: XCTestCase {
    func testCampfireFitsNearHomeWreckOnEverySeed() throws {
        let content = try TestContent.full()
        let kind = try XCTUnwrap(["campfire", "structure.campfire"].map { StructureKindID($0) }
            .first { content.structures[$0] != nil }, "焚き火台の定義が無い")
        let def = try XCTUnwrap(content.structures[kind])
        let n = ProcessInfo.processInfo.environment["REFORGE_FIRSTFIRE_SEEDS"].flatMap { Int($0) } ?? 20
        let factory = WorldFactory(content: content, mapGenerator: RFMapGenerator())
        var far = 0
        for seed in UInt64(0)..<UInt64(n) {
            let w = factory.newWorld(seed: seed)
            let home = try XCTUnwrap(w.map[.surface]?.placements[.homeWreck], "seed \(seed): 残骸が無い")
            let near = WorldPoint(.surface, home.anchor)
            switch StructureSites.spot(def, near: near, StepContext(world: w, content: content)) {
            case .success(let at): far = max(far, at.point.chebyshev(to: home.anchor))
            case .failure(let r): XCTFail("seed \(seed): 残骸のそばに焚き火台を置けない(\(r.reason))")
            }
        }
        print("最初の火の置き場所: 種 \(n)、残骸からいちばん遠い置き場所 \(far) マス")
    }
}
