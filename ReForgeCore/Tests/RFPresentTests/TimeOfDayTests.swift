import Foundation
import RFContent
import RFKernel
import RFMap
import RFPresent
import RFRules
import RFSave
import RFTestSupport
import RFWorld
import XCTest

final class TimeOfDayTests: XCTestCase {
    private func publicDefinition() throws -> TimeTintDef {
        try XCTUnwrap(TestContent.publicOnly().timeTint)
    }

    private func markStart(_ minutes: Int, _ def: TimeTintDef) -> TimeTintKey {
        let stepped = TimeOfDay.step(minutes: minutes) * 15 / 2
        return try! XCTUnwrap(def.keys.last(where: { $0.at <= stepped }))
    }

    // TEST-O23 (1)
    func testDayStepsAreGentle() throws {
        let def = try publicDefinition()
        let values = (0..<64).map { TimeOfDay.tint(minutes: ($0 * 15 + 1) / 2, def) }
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(abs(a.brightness - b.brightness), 30)
            XCTAssertLessThanOrEqual(abs(a.strength - b.strength), 30)
        }
    }

    // TEST-O23 (2)
    func testTimeTintIsPureAndNeverSaved() throws {
        let def = try publicDefinition()
        XCTAssertEqual(TimeOfDay.tint(minutes: 333, def), TimeOfDay.tint(minutes: 333, def))
        let world = TestRig(content: try TestContent.publicOnly()).factory.newWorld(seed: 1)
        let data = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("timeTint"))
        XCTAssertFalse(json.contains("brightness"))
    }

    // TEST-O23 (3)
    func testMarkUsesTheSameSteppedIntervalAsTint() throws {
        let def = try publicDefinition()
        for step in 0...208 {
            let minutes = step * 15 / 2
            XCTAssertEqual(TimeOfDay.mark(minutes: minutes, def), markStart(minutes, def).mark)
        }
    }

    // TEST-O23 (4)
    func testNightBrightnessAndSpritesFollowHearthLight() throws {
        var content = try TestContent.publicOnly()
        let subject = Subject.poi("poi.test.wreck")
        var perception = try XCTUnwrap(content.perception[subject])
        perception.variants[perception.variants.count - 1].glow = true
        content.perception[subject] = perception
        let builder = FrameBuilder(content: content)
        var world = TestRig(content: content).factory.newWorld(seed: 1)
        let center = world.map.spawn.point
        let edge = center + GridPoint(5, 0)
        let inside = center + GridPoint(1, 0)
        let outside = center + GridPoint(7, 0)
        let glow = center + GridPoint(6, 0)
        var known = world.knowledge.mapKnown[.surface] ?? GridBitset(size: world.map[.surface]!.size)
        for point in [center, inside, edge, outside, glow, center + GridPoint(3, 0)] { known[point] = true }
        world.knowledge.mapKnown[.surface] = known
        world.clock.phase = .nightWork
        world.clock.now = GameTime(seconds: 480 * 60)

        let fire = world.newEntityID()
        var camp = Placement(id: fire, kind: .structure("structure.campfire"), at: WorldPoint(.surface, center), facing: .north,
                             origin: ProvenanceLedger.unknownOrigin, status: .running)
        var hearth = StructureRuntime()
        hearth.hearth = HearthState(fuel: 43_200_000, lit: true)
        camp.structure = hearth
        world.placements.items[fire] = camp

        let hiddenPlacement = world.newEntityID()
        world.placements.items[hiddenPlacement] = Placement(id: hiddenPlacement, kind: .structure("structure.test.shelter"),
                                                             at: WorldPoint(.surface, outside), facing: .north,
                                                             origin: ProvenanceLedger.unknownOrigin, status: .running)
        let person = PersonID("person.test_a")
        world.people[person]?.presence = .member(since: .zero)
        world.people[person]?.position = WorldPoint(.surface, outside)
        _ = world.map[.surface]!.placements.place(MapPlacement(id: "glow.test", kind: .wreck, templateID: "poi.test.wreck",
                                                                anchor: glow, footprint: .rect(width: 1, height: 1), entity: EntityID(9_001)))

        let frame = builder.build(world, revision: 1, previous: nil, report: nil)
        XCTAssertEqual(builder.tile(world, at: inside).brightness, frame.timeTint.brightness)
        XCTAssertEqual(builder.tile(world, at: edge).brightness, 500)
        XCTAssertEqual(builder.tile(world, at: outside).brightness, frame.timeTint.outside)
        XCTAssertNil(builder.tile(world, at: glow).brightness)
        XCTAssertFalse(frame.actors.contains { $0.id == person.rawValue })
        XCTAssertFalse(frame.placements.contains { $0.id == hiddenPlacement })

        world.placements.items[fire]?.structure?.hearth = HearthState(fuel: 3_600_000, lit: true)
        let smaller = builder.build(world, revision: 2, previous: frame, report: nil)
        XCTAssertEqual(smaller.placements.first { $0.id == fire }?.id, fire)
        XCTAssertEqual(builder.tile(world, at: center + GridPoint(3, 0)).brightness, smaller.timeTint.outside)
    }

    // TEST-O23 (5)
    func testPublicTintsPreserveTerrainHueOrder() throws {
        let content = try TestContent.publicOnly()
        let def = try XCTUnwrap(content.timeTint)
        let bases = ["grass", "forest", "water", "rock", "cleared"].map {
            TilePalette.style("terrain.\($0)", terrains: content.terrains).foreground(at: GridPoint(0, 0))
        }
        for key in def.keys {
            let treatment = TimeOfDay.tint(minutes: key.at, def)
            let tinted = bases.map { treatment.apply($0, brightness: treatment.brightness) }
            for (before, after) in zip(bases, tinted) {
                XCTAssertLessThanOrEqual(hueDistance(hue(before), hue(after)), 20)
            }
            let baseHues = bases.map(hue)
            let tintedHues = tinted.map(hue)
            for i in bases.indices { for j in bases.indices where baseHues[i] < baseHues[j] {
                XCTAssertLessThan(tintedHues[i], tintedHues[j])
            } }
        }
    }

    // TEST-O23 (6)
    func testDayActorAndPlacementPresentationDoNotUseTimeTint() throws {
        let content = try TestContent.publicOnly()
        let builder = FrameBuilder(content: content)
        var world = TestRig(content: content).factory.newWorld(seed: 1)
        let point = world.map.spawn.point
        let id = world.newEntityID()
        world.placements.items[id] = Placement(id: id, kind: .structure("structure.test.shelter"), at: WorldPoint(.surface, point),
                                               facing: .north, origin: ProvenanceLedger.unknownOrigin, status: .running)
        let morning = builder.build(world, revision: 1, previous: nil, report: nil)
        world.clock.now = GameTime(seconds: 240 * 60)
        let noon = builder.build(world, revision: 2, previous: morning, report: nil)
        XCTAssertEqual(morning.actors.first { $0.isNoah }?.tint, noon.actors.first { $0.isNoah }?.tint)
        XCTAssertEqual(morning.placements.first { $0.id == id }?.glyph, noon.placements.first { $0.id == id }?.glyph)
    }

    // TEST-O23 (7)
    func testCompatibilityDefinitionPreservesOldDayAndNightValues() {
        XCTAssertEqual(TimeOfDay.tint(minutes: 240, TimeOfDay.defaultDef).brightness, 1000)
        XCTAssertEqual(TimeOfDay.tint(minutes: 720, TimeOfDay.defaultDef).brightness, 750)
        XCTAssertEqual(TimeOfDay.tint(minutes: 720, TimeOfDay.defaultDef).outside, 420)
        XCTAssertTrue(TilePalette.isReservedRed(RGB(255, 0, 0)))
    }

    private func hue(_ rgb: RGB) -> Double {
        let r = Double(rgb.r) / 255, g = Double(rgb.g) / 255, b = Double(rgb.b) / 255
        let high = max(r, max(g, b)), low = min(r, min(g, b)), delta = high - low
        guard delta > 0 else { return 0 }
        let raw: Double
        if high == r { raw = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if high == g { raw = 60 * ((b - r) / delta + 2) }
        else { raw = 60 * ((r - g) / delta + 4) }
        return raw < 0 ? raw + 360 : raw
    }

    private func hueDistance(_ a: Double, _ b: Double) -> Double { min(abs(a - b), 360 - abs(a - b)) }
}
