import RFCrew
import RFContent
import RFKernel
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
}
