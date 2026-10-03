import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// W-23: placeStructure(at: .openingSite(.firstFire)) は層の firstFireSite に置く。塞ぐと今の探し方で近くに置く。
final class OpeningSiteEffectTests: XCTestCase {
    private func setup(seed: UInt64) throws -> (WorldState, ContentDB, StructureKindID, GridPoint) {
        let content = try TestContent.full()
        let kind = try XCTUnwrap(["campfire", "structure.campfire"].map { StructureKindID($0) }
            .first { content.structures[$0] != nil })
        let w = WorldFactory(content: content, mapGenerator: RFMapGenerator()).newWorld(seed: seed)
        let site = try XCTUnwrap(w.map[.surface]?.firstFireSite, "seed \(seed)")
        return (w, content, kind, site)
    }

    func testPlacesAtFirstFireSite() throws {
        for seed in UInt64(0)..<30 {
            let (w, content, kind, site) = try setup(seed: seed)
            var ctx = StepContext(world: w, content: content)
            EffectApplier.apply([.placeStructure(structure: kind, at: .openingSite(kind: .firstFire), built: true)],
                                &ctx, cause: nil)
            XCTAssertTrue(ctx.warnings.isEmpty, "seed \(seed): \(ctx.warnings)")
            let fire = try XCTUnwrap(ctx.world.placements.items.values.first { $0.kind == .structure(kind) })
            XCTAssertEqual(fire.at.point, site, "seed \(seed)")
        }
    }

    func testBlockedSiteFallsBackNearby() throws {
        for seed in UInt64(0)..<30 {
            let (w, content, kind, site) = try setup(seed: seed)
            var ctx = StepContext(world: w, content: content)
            // 同じ場所を先に塞ぐ
            EffectApplier.apply([.placeStructure(structure: kind, at: .point(at: WorldPoint(.surface, site)), built: true)],
                                &ctx, cause: nil)
            EffectApplier.apply([.placeStructure(structure: kind, at: .openingSite(kind: .firstFire), built: true)],
                                &ctx, cause: nil)
            let fires = ctx.world.placements.items.values.filter { $0.kind == .structure(kind) }
            XCTAssertEqual(fires.count, 2, "seed \(seed): \(ctx.warnings)")
            let other = try XCTUnwrap(fires.first { $0.at.point != site }, "seed \(seed)")
            XCTAssertLessThanOrEqual(other.at.point.chebyshev(to: site), 3)
        }
    }

    func testSelectorCodableRoundTrip() throws {
        for k in [OpeningSiteKind.firstFire, .dawnFind] {
            let p = PlaceSelector.openingSite(kind: k)
            XCTAssertEqual(try JSONDecoder().decode(PlaceSelector.self, from: JSONEncoder().encode(p)), p)
        }
    }
}
