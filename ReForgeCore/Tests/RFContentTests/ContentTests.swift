import Foundation
import RFContent
import RFKernel
import RFTestSupport
import XCTest

final class ContentTests: XCTestCase {
    /// 公開の層だけでも読めて、検証にエラーが無い(公開版だけでビルドとテストが通る)。
    func testPublicLayerLoadsAndValidates() throws {
        let db = try TestContent.publicOnly()
        XCTAssertEqual(db.layers.map(\.id), ["public"])
        XCTAssertEqual(db.start.members.first, "person.noah")
        XCTAssertNotNil(db.events["event.test.chain"])
        let errors = ContentValidator.validate(db).filter { $0.level == .error }
        XCTAssertEqual(errors, [], "\(errors)")
    }

    /// 非公開の層は同じ ID を丸ごと置き換え、remove で消せる。
    func testPrivateLayerOverridesAndRemoves() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rf-\(UUID().uuidString)")
        let priv = tmp.appendingPathComponent("private")
        try FileManager.default.createDirectory(at: priv, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(#"""
        { "bundle": {"id": "private", "visibility": "private", "version": "t"},
          "texts": {"text.name.test_a": "置き換えた名前"},
          "remove": {"events": ["event.test.decision"]} }
        """#.utf8).write(to: priv.appendingPathComponent("a.json"))
        let db = try ContentLoader.load(layers: [TestContent.publicLayer, priv])
        XCTAssertEqual(db.layers.map(\.id), ["public", "private"])
        XCTAssertEqual(db.texts["text.name.test_a"], "置き換えた名前")
        XCTAssertNil(db.events["event.test.decision"])
        XCTAssertNotNil(db.events["event.test.chain"])
    }

    /// 環境変数 REFORGE_PRIVATE_CONTENT が非公開の層の場所になる。
    func testPrivateLayerFromEnvironment() {
        let url = ContentLoader.privateLayer(publicLayer: TestContent.publicLayer,
                                             environment: ["REFORGE_PRIVATE_CONTENT": "/x/y"])
        XCTAssertEqual(url?.path, "/x/y")
    }

    /// 公開 + 非公開(あれば)を重ねても検証エラー 0(非公開が無ければ公開だけ)。
    func testFullContentValidates() throws {
        let errors = ContentValidator.validate(try TestContent.full()).filter { $0.level == .error }
        XCTAssertEqual(errors.count, 0, "\(errors.prefix(20))")
    }

    // MARK: 層の重ね方

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        return tmp
    }

    private func write(_ json: String, _ path: String, in dir: URL) throws {
        let url = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    /// 同じ層の中で同じ ID を 2 回書く(別のファイルでも)のはエラー。層をまたぐ置き換えは正しい。
    func testDuplicateIDWithinOneLayerIsAnError() throws {
        let dir = try makeTempDir()
        try write(#"{"facts": [{"id": "fact.x"}]}"#, "a.json", in: dir)
        try write(#"{"facts": [{"id": "fact.x"}], "texts": {"t": "1"}}"#, "b/c.json", in: dir)
        XCTAssertThrowsError(try ContentLoader.load(layers: [dir])) { e in
            guard case .duplicate(let file, let keys)? = e as? ContentLoader.LoadError else { return XCTFail("\(e)") }
            XCTAssertTrue(file.hasSuffix("b/c.json"), file)
            XCTAssertEqual(keys, ["facts: fact.x"])
        }
    }

    /// remove の集まりの名前の誤記はエラー(黙って何も消さない、にしない)。名札つきの禁止語の規則は消せる。
    func testRemoveUnknownCollectionIsAnErrorAndRulesCanBeRemoved() throws {
        var db = try TestContent.publicOnly()
        XCTAssertThrowsError(try ContentLoader.apply(json: Data(#"{"remove": {"evnets": ["x"]}}"#.utf8), to: &db)) { e in
            XCTAssertEqual(e as? ContentLoader.LoadError, .unknownCollection(file: "<memory>", name: "evnets"))
        }
        try ContentLoader.apply(json: Data(#"{"remove": {"forbidden": ["rule.test.a"], "glyphs": ["item:wood"]}}"#.utf8), to: &db)
        XCTAssertTrue(db.forbidden.isEmpty)
        XCTAssertNil(db.glyphs["item:wood"])
    }

    /// 定義の中の項目名の誤記もエラー(JSONDecoder は黙って読み飛ばすので、書き出し直して比べる)。
    func testUnknownNestedKeyIsAnError() throws {
        var db = ContentDB()
        let json = #"{"perception": [{"subject": "item:x", "variants": [{"when": true, "naem": "text.x"}]}]}"#
        XCTAssertThrowsError(try ContentLoader.apply(json: Data(json.utf8), to: &db)) { e in
            XCTAssertEqual(e as? ContentLoader.LoadError, .unknownKeys(file: "<memory>", keys: ["perception[0].variants[0].naem"]))
        }
        // null と注記は誤記でない
        try ContentLoader.apply(json: Data(#"{"//": "x", "facts": [{"id": "fact.y", "scope": null}]}"#.utf8), to: &db)
        XCTAssertNotNil(db.facts["fact.y"])
    }

    /// 隠しディレクトリ(非公開リポジトリの .git など)の JSON は読まない。シンボリックリンクの層も読める。
    func testHiddenFilesSkippedAndSymlinkedLayerLoads() throws {
        let dir = try makeTempDir()
        let real = dir.appendingPathComponent("real")
        try write(#"{"bundle": {"id": "private", "visibility": "private", "version": "t"}, "texts": {"text.p": "非公開"}}"#,
                  "bundle.json", in: real)
        try write(#"{"evnets": []}"#, ".git/x.json", in: real)
        try write(#"{"evnets": []}"#, ".hidden.json", in: real)
        let link = dir.appendingPathComponent("private")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let db = try ContentLoader.load(layers: [TestContent.publicLayer, link])
        XCTAssertEqual(db.layers.map(\.id), ["public", "private"])
        XCTAssertEqual(db.texts["text.p"], "非公開")
    }

    /// 環境変数が指す非公開の層が無いのはエラー(指定の誤記で黙って公開だけにしない)。指定が無ければ公開だけで動く。
    func testMissingPrivateLayerFromEnvironmentIsAnError() throws {
        let dir = try makeTempDir()
        try write("{}", "public/a.json", in: dir)
        let pub = dir.appendingPathComponent("public")
        XCTAssertThrowsError(try ContentLoader.loadDefault(publicLayer: pub, environment: [ContentLoader.privateLayerEnv: "/no/such/dir"]))
        XCTAssertNoThrow(try ContentLoader.loadDefault(publicLayer: pub, environment: [:]))
        XCTAssertNil(ContentLoader.privateLayer(publicLayer: pub, environment: [:]))
    }

    /// アプリの束(<root>/public と、あれば <root>/private)から読む。
    func testLoadBundled() throws {
        let dir = try makeTempDir()
        try write(#"{"texts": {"text.a": "公開"}}"#, "public/a.json", in: dir)
        XCTAssertEqual(try ContentLoader.loadBundled(root: dir).texts["text.a"], "公開")
        try write(#"{"texts": {"text.a": "非公開"}}"#, "private/a.json", in: dir)
        XCTAssertEqual(try ContentLoader.loadBundled(root: dir).texts["text.a"], "非公開")
    }

    // MARK: 検証(認識の層)

    func testValidatorCatchesPerceptionMistakes() throws {
        var db = try TestContent.publicOnly()
        db.modules["module.test.new"] = db.modules["furnace"].map { var m = $0; m.id = "module.test.new"; return m }
        db.perception["stat:stat.test.air"]?.variants[1].display = .bands(thresholds: [900, 100], labels: ["text.stat.air.low"])
        db.perception["item:wood"]?.variants.insert(Variant(when: .fact("fact.test.typo"), name: "text.item.wood"), at: 0)
        db.perception["terrain:grass"]?.variants[0].glyph = "草地"
        db.textGates["text.nope"] = TextGate(text: "text.nope", gate: .always)
        let rules = Set(ContentValidator.validate(db).filter { $0.level == .error }.map(\.rule))
        XCTAssertEqual(rules, ["perception.missing", "perception.bands", "perception.fact", "perception.glyph", "textGate.text"])
    }

    func testUnknownTopLevelKeyIsAnError() {
        var db = ContentDB()
        XCTAssertThrowsError(try ContentLoader.apply(json: Data(#"{"evnets": []}"#.utf8), to: &db)) { e in
            XCTAssertEqual(e as? ContentLoader.LoadError, .unknownKeys(file: "<memory>", keys: ["evnets"]))
        }
    }

    /// 文を出すだけの出来事は警告になる。
    func testSceneOnlyEventIsWarned() throws {
        var db = ContentDB()
        try ContentLoader.apply(json: Data(#"""
        {"events": [{"id": "e", "trigger": {"when": {"always": {}}}, "effects": [{"startScene": {"scene": "s"}}]}]}
        """#.utf8), to: &db)
        XCTAssertTrue(ContentValidator.validate(db).contains { $0.rule == "event.changes-world" })
    }
}
