import Foundation
import RFKernel
import RFPresent
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 試験用の世界: 集合(Set)・文字列でないキーの辞書・来歴・記憶・地図の既知・在庫の来歴が、どれも 2 つ以上の要素を持つ。
enum Fixture {
    static let stamp = [ContentStamp(layer: "public", version: "fixture-1")]

    static func world(_ rig: TestRig, seed: UInt64 = 11, reversed: Bool = false) -> WorldState {
        var ctx = StepContext(world: rig.factory.newWorld(seed: seed), content: rig.content)
        let ids = (1...24).map { $0 }
        let order = reversed ? ids.reversed() : ids
        var origins: [ProvenanceID] = []
        for i in order {
            ctx.world.knowledge.seen.insert(SubjectID("subject.test.\(i)"))
            ctx.world.knowledge.discovered.insert(EntityID(1000 + i))
        }
        for i in ids {
            origins.append(ctx.record(.gathered, .item("wood"), actor: .noah, tags: [ProvenanceTag("tag.test.\(i % 5)"),
                                                                                    "tag.test.memorable"]))
        }
        for o in reversed ? origins.reversed() : origins { ctx.addStock(.item("wood"), 1, to: .base, origin: o) }
        ctx.learn("fact.test.revealed")
        ctx.learn("fact.test.beta")
        ctx.world.people["person.test_a"]?.memories.append(
            MemoryRecord(kind: "memory.test.saw", at: .zero, run: 1, about: origins.first, persistsAcrossRewind: true))
        ctx.world.people["person.test_a"]?.relation.points = 12
        var known = GridBitset(size: GridSize(width: 32, height: 32))
        for x in 0..<20 { known[GridPoint(x, x % 7)] = true }
        ctx.world.knowledge.mapKnown[.surface] = known
        return ctx.world
    }

    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func url(version: Int) -> URL { directory.appendingPathComponent("save-v\(version).json") }

    static var updating: Bool { ProcessInfo.processInfo.environment["REFORGE_UPDATE_SAVE_FIXTURES"] == "1" }
}

final class SaveTests: XCTestCase {
    func testGameHostSaveDataMatchesSaveCodecBytes() async throws {
        let rig = try TestRig.publicOnly()
        let world = Fixture.world(rig)
        let host = GameBootstrap.host(content: rig.content, world: world)
        let expected = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: world, content: Fixture.stamp))
        let actual = try await host.saveData(slot: .resume, stamps: Fixture.stamp)
        XCTAssertEqual(actual, expected)
    }

    func testEnvelopeRoundTrip() throws {
        let rig = try TestRig.publicOnly()
        let e = SaveEnvelope(slot: .dawn(day: 1), world: Fixture.world(rig), content: Fixture.stamp)
        let data = try SaveCodec.encode(e)
        let back = try SaveCodec.decode(data)
        XCTAssertEqual(back, e)
        XCTAssertEqual(try SaveCodec.encode(back), data, "読んで書き直してもバイト列が同じ")
        XCTAssertEqual(back.summary.day, 1)
        XCTAssertEqual(back.summary.seed, 11)
    }

    func testPreMigrationSaveNamesDecodeAndWriteCurrentNames() throws {
        let rig = try TestRig.publicOnly()
        var world = Fixture.world(rig)
        world.narrative.updateSheet("sheet.test.compat") { $0.granted["person.test_a"] = ["skill.test.kindling"] }
        let envelope = SaveEnvelope(slot: .resume, world: world, content: Fixture.stamp)
        let previous = LegacyNames.legacy(try CanonicalJSON.tree(envelope))
        let decoded = try SaveCodec.decode(Data(CanonicalJSON.bytes(previous)))
        XCTAssertEqual(decoded, envelope)
        let rewritten = String(decoding: try SaveCodec.encode(decoded), as: UTF8.self)
        XCTAssertTrue(rewritten.contains("\"granted\""))
    }

    /// 同じ値なら、集合と辞書に入れた順が違っても同じバイト列(標準の JSONEncoder ではハッシュの順で揺れる)。
    func testCanonicalBytesIgnoreInsertionOrder() throws {
        let rig = try TestRig.publicOnly()
        let a = Fixture.world(rig)
        let b = Fixture.world(rig, reversed: true)
        XCTAssertEqual(a, b)
        let ea = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: a, content: []))
        let eb = try SaveCodec.encode(SaveEnvelope(slot: .resume, world: b, content: []))
        XCTAssertEqual(ea, eb)
        // 文字列でないキーの辞書([ProvenanceID: Int])はキーの順の配列になる
        let tree = try CanonicalJSON.tree([ProvenanceID(3): 1, ProvenanceID(1): 2, ProvenanceID(2): 3])
        XCTAssertEqual(tree, .array([.int(1), .int(2), .int(2), .int(3), .int(3), .int(1)]))
        XCTAssertEqual(String(decoding: try CanonicalJSON.encode(Set(["b", "a", "c"])), as: UTF8.self), #"["a","b","c"]"#)
        XCTAssertEqual(String(decoding: CanonicalJSON.bytes(.object(["b": .int(1), "a": .string("x\"\n")])), as: UTF8.self),
                       #"{"a":"x\"\n","b":1}"#)
    }

    func testFloatsAreRejected() {
        struct HasFloat: Encodable { var x = 0.5 }
        XCTAssertThrowsError(try CanonicalJSON.encode(HasFloat()))
    }

    /// 固定の JSON との突き合わせ(退行検出)。保存してあった版の JSON が読め、書き直すと同じバイト列になる。
    /// リリース前(compatibilityFrozen = false)は、世界の形が変わったら作り直しを促して skip する
    /// (REFORGE_UPDATE_SAVE_FIXTURES=1 で swift test すると書き直す)。リリース後は失敗にする(移行を足すこと)。
    func testFixtureStillReadsAndEncodesIdentically() throws {
        let rig = try TestRig.publicOnly()
        let url = Fixture.url(version: SaveCodec.schemaVersion)
        if Fixture.updating {
            try FileManager.default.createDirectory(at: Fixture.directory, withIntermediateDirectories: true)
            var w = Fixture.world(rig)
            _ = rig.playDay(&w, dt: 0.37)
            try SaveCodec.encode(SaveEnvelope(slot: .dawn(day: 1), world: w, content: Fixture.stamp)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let regenerate = "保存の形が変わった。版 \(SaveCodec.schemaVersion) のまま形を変えてよいのはリリース前だけ。" +
            "REFORGE_UPDATE_SAVE_FIXTURES=1 swift test で \(url.lastPathComponent) を作り直す(リリース後は版を上げて移行を足す)"
        let decoded: SaveEnvelope
        do { decoded = try SaveCodec.decode(data) } catch {
            if SaveCodec.compatibilityFrozen { return XCTFail("\(regenerate): \(error)") }
            throw XCTSkip("\(regenerate): \(error)")
        }
        let again = try SaveCodec.encode(decoded)
        XCTAssertEqual(try SaveCodec.encode(SaveCodec.decode(again)), again, "書き直しは冪等")
        if again != data {
            if SaveCodec.compatibilityFrozen { return XCTFail(regenerate) }
            throw XCTSkip(regenerate)
        }
    }

    /// dev ビルドで配った保存の形(凍らせた見本。作り直さない)。オーナーの端末の保存を読めること。
    /// 7ea0791(09:03 の dev)・8697631(10:02 の dev)・397dea8 の save-v1.json はバイト単位で同じなので、この 1 つで 3 つを兼ねる。
    /// 版を上げたら(W-10)、移行を通して今の版で読めること・書き直しが冪等なことをここで確かめる。
    func testFrozenDevSavesStillRead() throws {
        for name in ["save-v1-dev-7ea0791.json"] {
            let data = try Data(contentsOf: Fixture.directory.appendingPathComponent(name))
            let decoded = try SaveCodec.decode(data)
            XCTAssertEqual(decoded.schemaVersion, SaveCodec.schemaVersion, name)
            let again = try SaveCodec.encode(decoded)
            XCTAssertEqual(try SaveCodec.encode(SaveCodec.decode(again)), again, "\(name): 書き直しは冪等")
        }
    }

    /// 古い版は移行を 1 つずつ通して読む。移行が無ければ読まない(壊れた状態で始めない)。
    func testMigrationChain() throws {
        let rig = try TestRig.publicOnly()
        let e = SaveEnvelope(slot: .resume, world: Fixture.world(rig), content: Fixture.stamp)
        var tree = try CanonicalJSON.tree(e)
        // 版 0 の形を作る: 版 -1 では summary が "meta"、版 0 で世界の run が "loop" という名前だった、とする
        tree.setKey("schemaVersion", .int(-1))
        let summary = tree["summary"]
        tree.setKey("summary", nil)
        tree.setKey("meta", summary)
        tree.modify("world") { w in
            let run = w["run"]
            w.setKey("run", nil)
            w.setKey("loop", run)
        }
        let old = Data(CanonicalJSON.bytes(tree))
        XCTAssertThrowsError(try SaveCodec.decode(old)) { XCTAssertEqual($0 as? SaveCodecError, .missingMigration(from: -1)) }
        let m1 = SaveMigration(from: -1) { t in
            let meta = t["meta"]
            t.setKey("meta", nil)
            t.setKey("summary", meta)
        }
        let m0 = SaveMigration(from: 0) { t in
            t.modify("world") { w in
                let loop = w["loop"]
                w.setKey("loop", nil)
                w.setKey("run", loop)
            }
        }
        XCTAssertThrowsError(try SaveCodec.decode(old, migrations: [m1])) {
            XCTAssertEqual($0 as? SaveCodecError, .missingMigration(from: 0))
        }
        let back = try SaveCodec.decode(old, migrations: [m0, m1])
        XCTAssertEqual(back, e)
        XCTAssertEqual(back.schemaVersion, SaveCodec.schemaVersion)
        let failing = SaveMigration(from: 0) { _ in throw SaveCodecError.notASave }
        XCTAssertThrowsError(try SaveCodec.decode(old, migrations: [m1, failing])) {
            guard case .migrationFailed(from: 0, _)? = $0 as? SaveCodecError else { return XCTFail("\($0)") }
        }
    }

    func testRejectsNewerSchemaAndNonSaves() throws {
        XCTAssertThrowsError(try SaveCodec.decode(Data(#"{"format":"reforge.save","schemaVersion":999}"#.utf8))) {
            XCTAssertEqual($0 as? SaveCodecError, .tooNew(999))
        }
        XCTAssertThrowsError(try SaveCodec.decode(Data(#"{"x":1}"#.utf8))) { XCTAssertEqual($0 as? SaveCodecError, .notASave) }
        XCTAssertThrowsError(try SaveCodec.decode(Data("not json".utf8))) { XCTAssertEqual($0 as? SaveCodecError, .notASave) }
    }

    func testSlotFileNames() {
        for s in [SaveSlot.resume, .screen, .dawn(day: 12), .manual(index: 2)] {
            XCTAssertEqual(SaveSlot(fileStem: s.fileStem), s)
        }
        XCTAssertNil(SaveSlot(fileStem: "dawn-x"))
    }
}
