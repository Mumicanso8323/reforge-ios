import RFCrew
import RFContent
import RFKernel
import RFRules
import RFSim
import RFTestSupport
import RFWorld
import XCTest

final class SteerTests: XCTestCase {
    private func point(_ world: WorldState, _ dx: Int, _ dy: Int) -> GridPoint {
        GridPoint(world.map.spawn.point.x + dx, world.map.spawn.point.y + dy)
    }

    private func command(_ rig: TestRig, _ world: inout WorldState, _ direction: StickDirection?) -> StepReport {
        rig.simulation.apply(.crew(.steer(direction: direction)), to: &world)
    }

    func testSteerMovesFourTilesInOneSecond() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        let start = world.people[.noah]!.position!.point
        XCTAssertNil(command(rig, &world, .east).rejection)
        _ = rig.simulation.advance(&world, realSeconds: 1)
        XCTAssertEqual(world.people[.noah]!.position!.point, GridPoint(start.x + 4, start.y))
    }

    func testNilStopsAtNextCellCenter() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        _ = command(rig, &world, .east)
        _ = rig.simulation.runSteps(2, &world)
        _ = command(rig, &world, nil)
        for _ in 0..<20 where world.people[.noah]?.motion != nil { _ = rig.simulation.runSteps(1, &world) }
        XCTAssertNil(world.people[.noah]?.motion)
        XCTAssertNil(world.people[.noah]?.steer)
    }

    func testDiagonalSlidesAlongOpenAxis() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        let start = world.map.spawn.point
        let diagonal = point(world, 1, -1)
        let vertical = point(world, 0, -1)
        world.map[.surface]?.setTerrain("water", at: diagonal)
        world.map[.surface]?.setTerrain("water", at: vertical)
        _ = rig.simulation.runSteps(1, &world)
        _ = command(rig, &world, .northEast)
        _ = rig.simulation.advance(&world, realSeconds: 0.3)
        XCTAssertGreaterThan(world.people[.noah]!.position!.point.x, start.x)
        XCTAssertEqual(world.people[.noah]!.position!.point.y, start.y)
    }

    func testBlockedDirectionEmitsOneEventUntilChanged() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        let wall = point(world, 1, 0)
        world.map[.surface]?.setTerrain("water", at: wall)
        _ = rig.simulation.runSteps(1, &world)
        _ = command(rig, &world, .east)
        let first = rig.simulation.runSteps(3, &world)
        let second = rig.simulation.runSteps(3, &world)
        XCTAssertEqual(first.events.filter { if case .steerBlocked = $0 { true } else { false } }.count, 1)
        XCTAssertFalse(second.events.contains { if case .steerBlocked = $0 { true } else { false } })
        _ = command(rig, &world, .north)
        _ = rig.simulation.runSteps(1, &world)
        XCTAssertNil(world.people[.noah]?.steerBlocked)
    }

    func testWalkClearsSteer() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        _ = command(rig, &world, .east)
        let destination = WorldPoint(.surface, point(world, 3, 0))
        _ = rig.simulation.apply(.crew(.walk(to: destination)), to: &world)
        XCTAssertNil(world.people[.noah]?.steer)
    }

    func testWalkOutsideRangeIsRejected() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        let far = WorldPoint(.surface, point(world, 12, 0))
        let report = rig.simulation.apply(.crew(.walk(to: far)), to: &world)
        XCTAssertEqual(report.rejection?.reason, "reason.crew.out_of_range")
        let near = WorldPoint(.surface, point(world, 3, 0))
        XCTAssertNil(rig.simulation.apply(.crew(.walk(to: near)), to: &world).rejection)
    }

    func testNightRangeIsNarrowerThanDay() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        world.clock.phase = .nightWork
        world.placements.items.removeAll()
        let outside = WorldPoint(.surface, point(world, 7, 0))
        XCTAssertEqual(rig.simulation.apply(.crew(.walk(to: outside)), to: &world).rejection?.reason, "reason.crew.out_of_range")
        let inside = WorldPoint(.surface, point(world, 4, 0))
        XCTAssertNil(rig.simulation.apply(.crew(.walk(to: inside)), to: &world).rejection)
    }

    func testSteerStopsAtTheLightEdgeButUsesNightVisionWithoutALight() throws {
        let rig = try TestRig.publicOnly()
        var lit = rig.factory.newWorld(seed: 1)
        let start = lit.people[.noah]!.position!.point
        lit.clock.phase = .nightWork
        let hearth = lit.newEntityID()
        var placement = Placement(id: hearth, kind: .structure("structure.campfire"), at: WorldPoint(.surface, start),
                                  facing: .north, origin: ProvenanceLedger.unknownOrigin, status: .running)
        var runtime = StructureRuntime()
        runtime.hearth = HearthState(fuel: 60_000, lit: true)
        placement.structure = runtime
        lit.placements.items[hearth] = placement
        _ = command(rig, &lit, .east)
        let litReport = rig.simulation.runSteps(12, &lit)
        XCTAssertTrue(litReport.events.contains(.steerBlocked(direction: .east, reason: .edge)))
        XCTAssertLessThanOrEqual(lit.people[.noah]!.position!.point.chebyshev(to: start), 4)

        var dark = rig.factory.newWorld(seed: 1)
        dark.clock.phase = .nightWork
        dark.placements.items.removeAll()
        _ = command(rig, &dark, .east)
        _ = rig.simulation.runSteps(12, &dark)
        XCTAssertLessThanOrEqual(dark.people[.noah]!.position!.point.chebyshev(to: start), 5)
        XCTAssertGreaterThan(dark.people[.noah]!.position!.point.chebyshev(to: start), lit.people[.noah]!.position!.point.chebyshev(to: start))
    }

    /// 灯りの円の外で日没を迎えても、棒が出ているのに全方向が詰まらない(ノア自身の夜目の円を足す)。
    func testSteerIsNotStuckOutsideEveryLightAtNight() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        let start = world.people[.noah]!.position!.point
        world.clock.phase = .nightWork
        world.placements.items.removeAll()
        let hearth = world.newEntityID()
        var placement = Placement(id: hearth, kind: .structure("structure.campfire"),
                                  at: WorldPoint(.surface, GridPoint(start.x - 14, start.y)),
                                  facing: .north, origin: ProvenanceLedger.unknownOrigin, status: .running)
        var runtime = StructureRuntime()
        runtime.hearth = HearthState(fuel: 60_000, lit: true)
        placement.structure = runtime
        world.placements.items[hearth] = placement
        let light = try XCTUnwrap(WalkRange.circles(world, content: rig.content, layer: .surface).first { $0.center != start },
                                  "焚き火の灯りの円がある")
        XCTAssertFalse(light.contains(start), "前提: ノアは灯りの円の外")
        _ = command(rig, &world, .east)
        let report = rig.simulation.runSteps(6, &world)
        XCTAssertFalse(report.events.contains { if case .steerBlocked = $0 { true } else { false } })
        XCTAssertGreaterThan(world.people[.noah]!.position!.point.x, start.x)
    }

    /// 眠る・時計の保留に入ったら、倒しっぱなしの向きは世界から落ちる(指を離せなくても歩き続けない)。
    func testSteerIsDroppedWhileSleepingOrHeld() throws {
        let rig = try TestRig.publicOnly()
        for suspend in [{ (w: inout WorldState) in w.clock.sleeping = true }, { (w: inout WorldState) in w.clock.held = true }] {
            var world = rig.factory.newWorld(seed: 1)
            world.clock.held = false
            _ = command(rig, &world, .east)
            XCTAssertNotNil(world.people[.noah]?.steer)
            suspend(&world)
            _ = rig.simulation.runSteps(1, &world)
            XCTAssertNil(world.people[.noah]?.steer)
            XCTAssertNil(world.people[.noah]?.steerBlocked)
        }
    }

    private func decision(blocking: Bool, _ world: WorldState) -> PendingDecision {
        PendingDecision(id: EntityID(9001), event: "event.test.decision", choices: [], blocking: blocking, since: world.clock.now, origin: nil)
    }

    /// 待機中のブロックする決断が開いたら、倒しっぱなしの向きは落ちる。決めた後も押し直すまで歩かない。
    func testBlockingDecisionDropsSteerAndDoesNotResume() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        world.clock.held = false
        _ = rig.simulation.runSteps(1, &world)
        _ = command(rig, &world, .east)
        world.narrative.pending.append(decision(blocking: true, world))
        let start = world.people[.noah]!.position!.point
        for _ in 0..<10 { _ = rig.simulation.runSteps(1, &world) }
        XCTAssertNil(world.people[.noah]?.steer)
        XCTAssertEqual(world.people[.noah]!.position!.point, start, "決断が開いている間は動かない")
        world.narrative.pending.removeAll()
        for _ in 0..<20 { _ = rig.simulation.runSteps(1, &world) }
        XCTAssertNil(world.people[.noah]?.steer, "決めても自動では再開しない")
        XCTAssertEqual(world.people[.noah]!.position!.point, start, "指を離して押し直すまで歩かない")
        _ = command(rig, &world, .east)
        _ = rig.simulation.advance(&world, realSeconds: 1)
        XCTAssertNotEqual(world.people[.noah]!.position!.point, start, "押し直せば歩く")
    }

    /// ブロックしない決断は操作棒を止めない。
    func testNonBlockingDecisionKeepsSteer() throws {
        let rig = try TestRig.publicOnly()
        var world = rig.factory.newWorld(seed: 1)
        world.clock.held = false
        _ = command(rig, &world, .east)
        world.narrative.pending.append(decision(blocking: false, world))
        _ = rig.simulation.runSteps(1, &world)
        XCTAssertNotNil(world.people[.noah]?.steer)
    }
}
