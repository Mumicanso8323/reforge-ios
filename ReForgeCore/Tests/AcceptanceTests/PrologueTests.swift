import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

final class PrologueTests: XCTestCase {
    private let first: SceneID = "scene.test.prologue.1"
    private let second: SceneID = "scene.test.prologue.2"

    private func rig() throws -> TestRig {
        var content = try TestContent.publicOnly()
        content.texts["text.test.prologue.first"] = "試験の一行目"
        content.texts["text.test.prologue.second"] = "試験の二行目"
        content.texts["text.test.prologue.third"] = "試験の三行目"
        content.texts["text.test.prologue.action"] = "試験の行為"
        try ContentLoader.apply(json: Data(#"""
        {
          "scenes": [
            { "id": "scene.test.prologue.1", "style": "prologue", "then": "scene.test.prologue.2",
              "lines": [ { "text": "text.test.prologue.first" }, { "text": "text.test.prologue.second" } ] },
            { "id": "scene.test.prologue.2", "style": "prologue",
              "lines": [ { "text": "text.test.prologue.third" } ] }
          ],
          "events": [
            { "id": "event.test.prologue", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.prologue.1" }
          ],
          "interactions": [
            { "id": "interaction.test.prologue", "target": { "terrain": { "tag": "ground" } },
              "seconds": 1, "hold": false, "yields": [] }
          ]
        }
        """#.utf8), to: &content)
        content.start.events = ["event.test.prologue"]
        content.start.clock = StartClockDef(held: true, firstAct: "interaction.test.prologue")
        return TestRig(content: content)
    }

    private func frame(_ rig: TestRig, _ world: WorldState) -> Frame {
        FrameBuilder(content: rig.content).build(world, revision: 0, previous: nil, report: nil)
    }

    private func fingerprint(_ world: WorldState) throws -> Data {
        try SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))
    }

    func testInitialFrameIsPrologueAndHidesGame() throws {
        let rig = try rig()
        let world = rig.factory.newWorld(seed: 1)
        let view = try XCTUnwrap(frame(rig, world).prologue)
        XCTAssertEqual(view.lines, ["試験の一行目"])
        XCTAssertTrue(view.waiting)
        XCTAssertNil(view.art)
        let result = frame(rig, world)
        XCTAssertEqual(result.status.count, 0)
        XCTAssertEqual(result.ui.open.count, 0)
        XCTAssertTrue(result.map.vision.isEmpty)
        XCTAssertTrue(FrameBuilder(content: rig.content).chunks(world, [0], map: result.map).allSatisfy { $0.tiles.allSatisfy { $0.fog == .unknown } })
        XCTAssertEqual(try XCTUnwrap(FrameBuilder(content: rig.content).footCard(world, at: world.map.spawn.point)).actions.count, 0)
    }

    func testRealTimeTickDoesNotAdvancePrologueOrClock() throws {
        let rig = try rig()
        var world = rig.factory.newWorld(seed: 2)
        let before = try fingerprint(world)
        for _ in 0..<600 { _ = rig.simulation.advance(&world, realSeconds: 1) }
        XCTAssertEqual(try fingerprint(world), before)
        XCTAssertEqual(frame(rig, world).prologue?.lines, ["試験の一行目"])
    }

    func testAdvancePagesThenReturnsTheFirstAction() throws {
        let rig = try rig()
        var world = rig.factory.newWorld(seed: 3)
        let start = world.clock.now
        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
        XCTAssertEqual(frame(rig, world).prologue?.lines, ["試験の一行目", "試験の二行目"])
        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
        XCTAssertEqual(frame(rig, world).prologue?.lines, ["試験の三行目"])
        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
        XCTAssertNil(frame(rig, world).prologue)
        XCTAssertTrue(world.clock.held)
        XCTAssertEqual(world.clock.now, start)
        XCTAssertEqual(try XCTUnwrap(FrameBuilder(content: rig.content).footCard(world, at: world.map.spawn.point)).actions.count, 1)
        XCTAssertEqual(frame(rig, world).darkStart?.action.id, "interaction.test.prologue")
    }

    func testPrologueRejectsWalkActionAndSleepWithoutChangingWorld() throws {
        let rig = try rig()
        let original = rig.factory.newWorld(seed: 4)
        let point = original.map.spawn
        let commands: [Command] = [
            .crew(.walk(to: point)),
            .exploration(.interact(interaction: "interaction.test.prologue", at: point, holding: true)),
            .time(.sleep),
        ]
        for command in commands {
            var world = original
            let before = try fingerprint(world)
            let report = rig.simulation.apply(command, to: &world)
            XCTAssertEqual(report.rejection?.reason, "reason.scene.prologue")
            XCTAssertEqual(try fingerprint(world), before)
        }
    }

    func testSaveRoundTripKeepsCurrentPrologueLine() throws {
        let rig = try rig()
        var world = rig.factory.newWorld(seed: 5)
        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
        let restored = try SaveCodec.decode(SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))).world
        XCTAssertEqual(restored.narrative.scene, world.narrative.scene)
        XCTAssertEqual(frame(rig, restored).prologue?.lines, ["試験の一行目", "試験の二行目"])
    }

    func testTicksBetweenAdvancesRemainDeterministic() throws {
        let rig = try rig()
        func finish(ticks: Bool) throws -> WorldState {
            var world = rig.factory.newWorld(seed: 6)
            for _ in 0..<3 {
                _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
                if ticks { for _ in 0..<10_000 { _ = rig.simulation.advance(&world, realSeconds: 1) } }
            }
            let point = world.map.spawn
            _ = rig.simulation.apply(.exploration(.interact(interaction: "interaction.test.prologue", at: point, holding: true)), to: &world)
            return world
        }
        XCTAssertEqual(try fingerprint(finish(ticks: false)), try fingerprint(finish(ticks: true)))
    }

    func testPrologueValidationRules() throws {
        XCTAssertEqual(ContentValidator.validate(try TestContent.publicOnly()).filter { $0.level == .error }, [])

        var cycle = try rig().content
        var secondScene = try XCTUnwrap(cycle.scenes[second])
        secondScene.then = first
        cycle.scenes[second] = secondScene
        XCTAssertTrue(ContentValidator.validate(cycle).contains { $0.rule == "scene.then" && $0.level == .error })

        var outsideStart = try rig().content
        outsideStart.events["event.test.prologue.outside"] = try JSONDecoder().decode(EventDef.self, from: Data(#"""
        { "id": "event.test.prologue.outside", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
          "scene": "scene.test.prologue.1" }
        """#.utf8))
        XCTAssertTrue(ContentValidator.validate(outsideStart).contains { $0.rule == "scene.prologue.start" && $0.level == .error })

        var conditional = try rig().content
        var firstScene = try XCTUnwrap(conditional.scenes[first])
        firstScene.lines[0].when = .always
        conditional.scenes[first] = firstScene
        XCTAssertTrue(ContentValidator.validate(conditional).contains { $0.rule == "scene.prologue.when" && $0.level == .error })

        var latin = try rig().content
        latin.texts["text.test.prologue.first"] = "試験Ａ"
        XCTAssertTrue(ContentValidator.validate(latin).contains { $0.rule == "scene.prologue.text" && $0.level == .error })
    }
}
