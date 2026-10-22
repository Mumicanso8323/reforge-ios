import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

/// W-09: 場面と決断が ArtID をデータから受けて Frame に載せる。絵が無いときは今と同じ出力。
final class ArtWiringTests: XCTestCase {
    private func content(art: Bool = true) throws -> ContentDB {
        var content = try TestContent.publicOnly()
        content.texts["text.test.art.line"] = "test line"
        content.texts["text.test.art.name"] = "test person"
        content.texts["text.test.art.prompt"] = "test prompt"
        content.texts["text.test.art.yes"] = "test yes"
        let sceneArt: (String) -> String = { art ? #", "art": "\#($0)""# : "" }
        content.perception[Subject.person("person.test_c")] = SubjectDef(
            subject: Subject.person("person.test_c"),
            variants: [
                Variant(when: .fact("fact.test.stage"), name: "text.test.art.name", art: art ? "t_revealed" : nil),
                Variant(when: .always, name: "text.unknown"),
            ])
        try ContentLoader.apply(json: Data(#"""
        {
          "facts": [ { "id": "fact.test.stage" } ],
          "scenes": [
            { "id": "scene.test.art.page1", "style": "stage", "then": "scene.test.art.page2"\#(sceneArt("t01")),
              "lines": [ { "text": "text.test.art.line" }, { "text": "text.test.art.line" } ] },
            { "id": "scene.test.art.page2", "style": "stage",
              "lines": [ { "text": "text.test.art.line" } ] },
            { "id": "scene.test.art.speaker", "style": "stage",
              "lines": [
                { "speaker": "person.test_c", "text": "text.test.art.line" },
                { "speaker": "person.test_c", "text": "text.test.art.line", "learns": ["fact.test.stage"] },
                { "text": "text.test.art.line" }
              ] },
            { "id": "scene.test.art.override", "style": "stage"\#(sceneArt("t02")),
              "lines": [
                { "speaker": "person.test_c", "text": "text.test.art.line", "learns": ["fact.test.stage"] }
              ] },
            { "id": "scene.test.art.bubble"\#(sceneArt("t03")),
              "lines": [ { "text": "text.test.art.line" } ] }
          ],
          "events": [
            { "id": "event.test.art.page", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.art.page1" },
            { "id": "event.test.art.speaker", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.art.speaker" },
            { "id": "event.test.art.override", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.art.override" },
            { "id": "event.test.art.bubble", "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "scene": "scene.test.art.bubble" },
            { "id": "event.test.art.ask", "prompt": "text.test.art.prompt"\#(sceneArt("t04")),
              "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "choices": [ { "id": "choice.test.art.yes", "label": "text.test.art.yes", "effects": [] } ] },
            { "id": "event.test.art.plain", "prompt": "text.test.art.prompt",
              "trigger": { "on": [], "when": { "always": {} } }, "effects": [],
              "choices": [ { "id": "choice.test.art.yes", "label": "text.test.art.yes", "effects": [] } ] }
          ]
        }
        """#.utf8), to: &content)
        return content
    }

    private func frame(_ db: ContentDB, _ world: WorldState) -> Frame {
        FrameBuilder(content: db).build(world, revision: 0, previous: nil, report: nil)
    }

    private func fire(_ id: EventID, _ rig: TestRig, _ world: inout WorldState) {
        _ = rig.simulation.apply(.narrative(.fireFromEffect(event: id, cause: nil)), to: &world)
    }

    private func next(_ rig: TestRig, _ world: inout WorldState) {
        _ = rig.simulation.apply(.narrative(.advanceScene), to: &world)
    }

    // 1
    func testSceneArtShowsPerPageAndDoesNotLinger() throws {
        let db = try content()
        let rig = TestRig(content: db)
        var world = rig.factory.newWorld(seed: 1)
        fire("event.test.art.page", rig, &world)
        XCTAssertEqual(frame(db, world).prologue?.art, "t01")
        next(rig, &world)
        XCTAssertEqual(frame(db, world).prologue?.art, "t01", "同じページの次の行")
        next(rig, &world)
        XCTAssertEqual(world.narrative.scene?.scene, "scene.test.art.page2")
        XCTAssertNil(frame(db, world).prologue?.art, "ページが替わったら前の絵は残らない")
        XCTAssertNotNil(frame(db, world).prologue)
    }

    // 2
    func testSpeakerPortraitFollowsPerceptionAndSceneArtWins() throws {
        let db = try content()
        let rig = TestRig(content: db)
        var world = rig.factory.newWorld(seed: 2)
        fire("event.test.art.speaker", rig, &world)
        XCTAssertNil(frame(db, world).prologue?.art, "開示の前は絵なし")
        next(rig, &world)
        XCTAssertNotNil(world.knowledge.facts["fact.test.stage"])
        XCTAssertEqual(frame(db, world).prologue?.art, "t_revealed", "learns で知った行から出る")
        next(rig, &world)
        XCTAssertNil(frame(db, world).prologue?.art, "話し手が替わる(いない)行で替わる")

        var other = rig.factory.newWorld(seed: 3)
        fire("event.test.art.override", rig, &other)
        XCTAssertEqual(frame(db, other).prologue?.art, "t02", "scene.art が勝つ")
    }

    // 3
    func testBubbleIgnoresArt() throws {
        let db = try content()
        let rig = TestRig(content: db)
        var world = rig.factory.newWorld(seed: 4)
        fire("event.test.art.bubble", rig, &world)
        let f = frame(db, world)
        XCTAssertNil(f.prologue)
        XCTAssertEqual(f.sceneLines, ["test line"])
        XCTAssertNil(f.decision?.art)

        let plain = try content(art: false)
        var world2 = TestRig(content: plain).factory.newWorld(seed: 4)
        fire("event.test.art.bubble", TestRig(content: plain), &world2)
        let g = frame(plain, world2)
        XCTAssertEqual(f, g, "絵の有無で bubble のフレームは変わらない")
    }

    // 4
    func testDecisionArtAndEquality() throws {
        let db = try content()
        let rig = TestRig(content: db)
        var world = rig.factory.newWorld(seed: 5)
        fire("event.test.art.ask", rig, &world)
        let view = try XCTUnwrap(frame(db, world).decision)
        XCTAssertEqual(view.art, "t04")
        var other = view
        other.art = "t05"
        XCTAssertNotEqual(view, other)
        other.art = nil
        XCTAssertNotEqual(view, other)
        other.art = view.art
        XCTAssertEqual(view, other)

        var plainWorld = rig.factory.newWorld(seed: 6)
        fire("event.test.art.plain", rig, &plainWorld)
        XCTAssertNil(frame(db, plainWorld).decision?.art)
    }

    // 5
    func testArtDoesNotChangePlay() throws {
        let withArt = try content()
        var bare = withArt
        for k in Array(bare.scenes.keys) { bare.scenes[k]?.art = nil }
        for k in Array(bare.events.keys) { bare.events[k]?.art = nil }
        for (k, def) in bare.perception {
            var d = def
            d.variants = d.variants.map { var v = $0; v.art = nil; return v }
            bare.perception[k] = d
        }
        XCTAssertNotEqual(withArt.scenes["scene.test.art.page1"]?.art, bare.scenes["scene.test.art.page1"]?.art)

        let a = TestRig(content: withArt), b = TestRig(content: bare)
        var wa = a.factory.newWorld(seed: 9), wb = b.factory.newWorld(seed: 9)

        func strip(_ f: Frame) -> Frame {
            var f = f
            f.prologue?.art = nil
            f.decision?.art = nil
            return f
        }
        var sawSceneArt = false, sawDecisionArt = false
        func same(_ step: String) throws {
            let shown = frame(withArt, wa)
            sawSceneArt = sawSceneArt || shown.prologue?.art != nil
            sawDecisionArt = sawDecisionArt || shown.decision?.art != nil
            let ea = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: wa, content: []))
            let eb = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: wb, content: []))
            XCTAssertEqual(ea, eb, step)
            XCTAssertEqual(strip(frame(withArt, wa)), strip(frame(bare, wb)), step)
        }
        func both(_ body: (TestRig, inout WorldState) -> Void) {
            body(a, &wa)
            body(b, &wb)
        }
        for event: EventID in ["event.test.art.page", "event.test.art.speaker"] {
            both { fire(event, $0, &$1) }
            try same("fire \(event)")
            for i in 0..<4 {
                both { next($0, &$1) }
                try same("advance \(i)")
            }
        }
        both { fire("event.test.art.ask", $0, &$1) }
        try same("ask")
        let ask = try XCTUnwrap(wa.narrative.pending.first)
        both { r, w in _ = r.simulation.apply(.narrative(.decide(decision: ask.id, choice: "choice.test.art.yes")), to: &w) }
        try same("decide")
        for i in 0..<300 {
            both { r, w in _ = r.simulation.advance(&w, realSeconds: 0.1) }
            try same("tick \(i)")
        }
        XCTAssertTrue(sawSceneArt, "絵のあるフレームが実際に場面の絵を持った")
        XCTAssertTrue(sawDecisionArt, "絵のあるフレームが実際に決断の絵を持った")
    }

    // 6
    func testPublicContentSerializesWithoutArt() throws {
        let db = try TestContent.publicOnly()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let scenes = String(decoding: try encoder.encode(db.scenes), as: UTF8.self)
        let events = String(decoding: try encoder.encode(db.events), as: UTF8.self)
        XCTAssertFalse(scenes.contains("\"art\""))
        XCTAssertFalse(events.contains("\"art\""))
        XCTAssertFalse(scenes.isEmpty)
        XCTAssertFalse(events.isEmpty)
    }

    // 7
    func testValidatorArtRules() throws {
        let db = try content()
        func rules(_ art: Set<ArtID>?) -> [String: Int] {
            var out: [String: Int] = [:]
            for i in ContentValidator.validate(db, art: art) where i.rule.hasPrefix("art.") { out[i.rule, default: 0] += 1 }
            return out
        }
        XCTAssertEqual(rules(nil)["art.exists"], nil, "nil は実在を調べない")
        XCTAssertEqual(rules(nil)["art.bubble"], 1)
        XCTAssertEqual(rules(nil)["art.form"], nil)
        let all: Set<ArtID> = ["t01", "t02", "t03", "t04", "t_revealed"]
        XCTAssertEqual(rules(all)["art.exists"], nil)
        XCTAssertEqual(rules(all.subtracting(["t01"]))["art.exists"], 1)
        XCTAssertGreaterThanOrEqual(rules([])["art.exists"] ?? 0, 5)

        var bad = db
        bad.scenes["scene.test.art.page2"]?.art = "T_Upper"
        XCTAssertTrue(ContentValidator.validate(bad).contains { $0.rule == "art.form" && $0.level == .error })

        var badVariant = db
        badVariant.perception[Subject.person("person.test_c")]?.variants[0].art = "T_Upper"
        let formIssues = ContentValidator.validate(badVariant).filter { $0.rule == "perception.art" || $0.rule == "art.form" }
        XCTAssertEqual(formIssues.count, 1, "Variant.art の形の誤りは 1 回だけ出る")
        XCTAssertEqual(formIssues.first?.level, .error)

        var nochoices = db
        nochoices.events["event.test.art.page"]?.art = "t01"
        XCTAssertTrue(ContentValidator.validate(nochoices).contains { $0.rule == "art.event.nochoices" && $0.level == .warning })

        let pub = try TestContent.publicOnly()
        for set in [nil, Set<ArtID>()] {
            XCTAssertTrue(ContentValidator.validate(pub, art: set).filter { $0.rule.hasPrefix("art.") }.isEmpty)
        }
    }

    // 8
    func testSealedArtFeedsValidator() throws {
        let layer = FileManager.default.temporaryDirectory.appendingPathComponent("rf-art-wiring-\(UUID().uuidString)")
        let art = layer.appendingPathComponent("art")
        try FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: layer) }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
        try png.write(to: art.appendingPathComponent("t01.png"))
        let collected = try ArtSeal.collect(layer: layer)
        XCTAssertEqual(collected.keys.map(\.rawValue), ["t01"])
        let key = ContentSeal.newKey()
        XCTAssertEqual(try ArtSeal.open(ArtSeal.seal(collected, key: key), key: key), collected)

        var db = try TestContent.publicOnly()
        db.texts["text.test.art.line"] = "test line"
        try ContentLoader.apply(json: Data(#"""
        { "scenes": [
            { "id": "scene.test.art.ok", "style": "stage", "art": "t01", "lines": [ { "text": "text.test.art.line" } ] },
            { "id": "scene.test.art.missing", "style": "stage", "art": "t02", "lines": [ { "text": "text.test.art.line" } ] }
        ] }
        """#.utf8), to: &db)
        let found = ContentValidator.validate(db, art: Set(collected.keys)).filter { $0.rule == "art.exists" }
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(found[0].message.contains("scene.test.art.missing"))
    }
}
