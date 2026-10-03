import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

final class StageSceneTests: XCTestCase {
    private let stage: SceneID = "scene.test.stage"
    private let namedStage: SceneID = "scene.test.named_stage"
    private let onEndThen: SceneID = "scene.test.on_end.then"

    private func rig() throws -> TestRig {
        var content = try TestContent.publicOnly()
        content.texts["text.test.stage.line"] = "test line"
        content.texts["text.test.person"] = "test person"
        content.perception[Subject.person("person.test_c")] = SubjectDef(
            subject: Subject.person("person.test_c"),
            variants: [
                Variant(when: .fact("fact.test.stage"), name: "text.test.person"),
                Variant(when: .always, name: "text.unknown"),
            ])
        try ContentLoader.apply(json: Data(#"""
        {
          "facts": [ { "id": "fact.test.stage" } ],
          "scenes": [
            { "id": "scene.test.stage", "style": "stage",
              "lines": [
                { "text": "text.test.stage.line", "when": { "known": { "expr": "fact.test.stage" } } },
                { "text": "text.test.stage.line", "learns": ["fact.test.stage"] }
              ] },
            { "id": "scene.test.named_stage", "style": "stage",
              "lines": [
                { "speaker": "person.test_c", "text": "text.test.stage.line" },
                { "speaker": "person.test_c", "text": "text.test.stage.line", "learns": ["fact.test.stage"] }
              ] },
            { "id": "scene.test.bubble", "then": "scene.test.stage",
              "lines": [ { "text": "text.test.stage.line" } ] },
            { "id": "scene.test.on_end.bubble", "then": "scene.test.on_end.then",
              "onEnd": [ { "join": { "person": "person.test_c" } } ],
              "lines": [ { "text": "text.test.stage.line" }, { "text": "text.test.stage.line" } ] },
            { "id": "scene.test.on_end.stage", "style": "stage", "then": "scene.test.on_end.then",
              "onEnd": [ { "join": { "person": "person.test_c" } } ],
              "lines": [ { "text": "text.test.stage.line" }, { "text": "text.test.stage.line" } ] },
            { "id": "scene.test.on_end.prologue", "style": "prologue", "then": "scene.test.on_end.then",
              "onEnd": [ { "join": { "person": "person.test_c" } } ],
              "lines": [ { "text": "text.test.stage.line" }, { "text": "text.test.stage.line" } ] },
            { "id": "scene.test.on_end.then",
              "lines": [ { "text": "text.test.stage.line" } ] }
          ],
          "events": [
            { "id": "event.test.stage_scene", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.stage" },
            { "id": "event.test.stage_effect", "trigger": { "on": [], "when": { "always": {} } },
              "effects": [ { "startScene": { "scene": "scene.test.stage" } } ] },
            { "id": "event.test.named_stage", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.named_stage" },
            { "id": "event.test.stage_bubble", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.bubble" },
            { "id": "event.test.stage_join", "trigger": { "on": [], "when": { "always": {} } },
              "effects": [ { "join": { "person": "person.test_c" } } ] }
          ]
        }
        """#.utf8), to: &content)
        return TestRig(content: content)
    }

    private func frame(_ rig: TestRig, _ world: WorldState) -> Frame {
        FrameBuilder(content: rig.content).build(world, revision: 0, previous: nil, report: nil)
    }

    private func fire(_ id: EventID, _ rig: TestRig, _ world: inout WorldState) {
        _ = rig.simulation.apply(.narrative(.fireFromEffect(event: id, cause: nil)), to: &world)
    }

    private func fingerprint(_ world: WorldState) throws -> Data {
        try SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))
    }

    func testStageStartsFromSceneEventEffectAndThen() throws {
        let rig = try rig()
        for event: EventID in ["event.test.stage_scene", "event.test.stage_effect"] {
            var world = rig.factory.newWorld(seed: 1)
            fire(event, rig, &world)
            XCTAssertEqual(world.narrative.scene?.scene, stage)
        }
        var world = rig.factory.newWorld(seed: 2)
        fire("event.test.stage_bubble", rig, &world)
        XCTAssertEqual(world.narrative.scene?.scene, "scene.test.bubble")
        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
        XCTAssertEqual(world.narrative.scene?.scene, stage)
    }

    func testStageSkipsUnavailableLinesAndUsesTapInsteadOfClock() throws {
        let rig = try rig()
        var world = rig.factory.newWorld(seed: 3)
        fire("event.test.stage_scene", rig, &world)
        let before = world.clock.now
        _ = rig.simulation.advance(&world, realSeconds: 1)
        XCTAssertEqual(world.clock.now, before)
        XCTAssertEqual(world.narrative.scene?.line, 1)
        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
        XCTAssertNil(world.narrative.scene)
        _ = rig.simulation.advance(&world, realSeconds: 1)
        XCTAssertGreaterThan(world.clock.now, before)
    }

    func testStageBlocksOtherCommandsButAllowsEffectFires() throws {
        let rig = try rig()
        var world = rig.factory.newWorld(seed: 4)
        fire("event.test.stage_scene", rig, &world)
        let rejected = rig.simulation.apply(.crew(.stop), to: &world)
        XCTAssertEqual(rejected.rejection?.reason, "reason.scene.reading")
        let accepted = rig.simulation.apply(.narrative(.fireFromEffect(event: "event.test.stage_effect", cause: nil)), to: &world)
        XCTAssertNil(accepted.rejection)
    }

    func testStageLearnsWhenEachLineIsShownAndNamesFollowFactsOnly() throws {
        let rig = try rig()
        var firstLine = rig.factory.newWorld(seed: 5)
        fire("event.test.stage_scene", rig, &firstLine)
        XCTAssertNotNil(firstLine.knowledge.facts["fact.test.stage"])

        var world = rig.factory.newWorld(seed: 6)
        fire("event.test.stage_join", rig, &world)
        fire("event.test.named_stage", rig, &world)
        let before = try XCTUnwrap(frame(rig, world).prologue)
        XCTAssertEqual(before.kind, .stage)
        XCTAssertEqual(before.speakers, [try XCTUnwrap(rig.content.texts["text.unknown"])])
        XCTAssertFalse(FrameText.allStrings(frame(rig, world)).contains("test person"))

        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
        XCTAssertNotNil(world.knowledge.facts["fact.test.stage"])
        let after = try XCTUnwrap(frame(rig, world).prologue)
        XCTAssertEqual(after.speakers, ["test person", "test person"])
        XCTAssertTrue(FrameText.allStrings(frame(rig, world)).contains("test person"))
    }

    func testStageLearnFactsAreValidated() throws {
        var content = try rig().content
        var definition = try XCTUnwrap(content.scenes[stage])
        definition.lines[0].learns = ["fact.test.missing"]
        content.scenes[stage] = definition
        XCTAssertTrue(ContentValidator.validate(content).contains { $0.rule == "fact.defined" && $0.level == .error })
    }

    func testOnEndRunsAfterTheLastLineForEveryStyleAndSurvivesReload() throws {
        let rig = try rig()
        for scene: SceneID in ["scene.test.on_end.bubble", "scene.test.on_end.prologue", "scene.test.on_end.stage"] {
            var world = rig.factory.newWorld(seed: 7)
            world.narrative.scene = SceneProgress(scene: scene, lineSince: world.clock.now)
            XCTAssertFalse(world.people["person.test_c"]?.presence.isMember == true)

            _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
            XCTAssertEqual(world.narrative.scene?.scene, scene)
            XCTAssertEqual(world.narrative.scene?.line, 1)
            XCTAssertFalse(world.people["person.test_c"]?.presence.isMember == true)

            var restored = try SaveCodec.decode(SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: []))).world
            _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
            _ = rig.simulation.apply(.narrative(.advanceScene), to: &restored)

            XCTAssertTrue(world.people["person.test_c"]?.presence.isMember == true)
            XCTAssertEqual(world.narrative.scene?.scene, onEndThen)
            XCTAssertEqual(try fingerprint(restored), try fingerprint(world))
        }
    }

    func testOnEndEffectsAreValidatedLikeEventEffects() throws {
        var content = try rig().content
        var definition = try XCTUnwrap(content.scenes[stage])
        definition.onEnd = [
            .learn(fact: "fact.test.missing"),
            .startScene(scene: "scene.test.missing"),
            .destroyPlacements(near: .base, radius: -1),
        ]
        content.scenes[stage] = definition
        let rules = Set(ContentValidator.validate(content).filter { $0.level == .error }.map(\.rule))
        XCTAssertTrue(rules.isSuperset(of: ["fact.defined", "narrative.ref", "effect.destroy"]), "\(rules)")
    }
}
