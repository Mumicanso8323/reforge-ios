import Foundation
import RFContent
import RFKernel
import RFMap
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// A-06: PlaceSelector.offset(指した点から (dx, dy) ずらした点)。
final class PlaceOffsetTests: XCTestCase {
    let campfire: StructureKindID = "structure.campfire"

    func setup() throws -> (ctx: StepContext, fire: GridPoint) {
        let rig = try TestRig.publicOnly()
        let w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        let at = w.map.spawn.point + GridPoint(-3, 0)
        EffectApplier.apply([.placeStructure(structure: campfire, at: .point(at: WorldPoint(.surface, at)), built: true)],
                            &ctx, cause: nil)
        XCTAssertTrue(ctx.warnings.isEmpty, "\(ctx.warnings)")
        return (ctx, at)
    }

    func testPlacesSixTilesEast() throws {
        var (ctx, fire) = try setup()
        let sel = PlaceSelector.offset(place: .placement(module: nil, structure: campfire), dx: 6, dy: 0)
        XCTAssertEqual(Places.resolve(sel, world: ctx.world, trigger: nil), WorldPoint(.surface, fire + GridPoint(6, 0)))
        EffectApplier.apply([.placeStructure(structure: campfire, at: sel, built: true)], &ctx, cause: nil)
        XCTAssertTrue(ctx.warnings.isEmpty, "\(ctx.warnings)")
        let points = Set(ctx.world.placements.items.values.map(\.at.point))
        XCTAssertEqual(points, [fire, fire + GridPoint(6, 0)])
    }

    func testOutsideTheMapOnlyWarns() throws {
        var (ctx, _) = try setup()
        let before = ctx.world.placements.items.count
        let sel = PlaceSelector.offset(place: .placement(module: nil, structure: campfire), dx: 100_000, dy: 0)
        XCTAssertNil(Places.resolve(sel, world: ctx.world, trigger: nil))
        EffectApplier.apply([.placeStructure(structure: campfire, at: sel, built: true)], &ctx, cause: nil)
        XCTAssertEqual(ctx.world.placements.items.count, before, "置かれない")
        XCTAssertFalse(ctx.warnings.isEmpty, "警告だけ")
    }

    func testCodableRoundTrip() throws {
        let p = PlaceSelector.offset(place: .near(place: .base, radius: 2), dx: -4, dy: 5)
        XCTAssertEqual(try JSONDecoder().decode(PlaceSelector.self, from: JSONEncoder().encode(p)), p)
    }
}
