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

    // MARK: 封をした非公開の層(E §4.5)

    private func makeSealTestLayer() throws -> (root: URL, priv: URL) {
        let root = try makeTempDir()
        let pub = root.appendingPathComponent("public")
        try FileManager.default.createSymbolicLink(at: pub, withDestinationURL: TestContent.publicLayer)
        let priv = root.appendingPathComponent("private-src")
        try write(#"{"bundle": {"id": "private", "visibility": "private", "version": "t", "canary": "zqcanary0123456789"}}"#,
                  "bundle.json", in: priv)
        try write(#"{"texts": {"text.name.test_a": "封の中の名前"}, "facts": [{"id": "fact.sealed"}]}"#, "text/ja/a.json", in: priv)
        try write(#"{"evnets": []}"#, "materials/not-content.json", in: priv)
        try write(#"{"evnets": []}"#, "tools/out.json", in: priv)
        try write("資料", "materials/note.md", in: priv)
        return (root, priv)
    }

    /// 封じて開くと同じ束。読み込みと同じファイル(*.json。materials/・tools/ は除く)だけが入る。
    func testSealRoundTrip() throws {
        let (_, priv) = try makeSealTestLayer()
        let files = try ContentSeal.collect(layer: priv)
        XCTAssertEqual(files.keys.sorted(), ["bundle.json", "text/ja/a.json"])
        let key = ContentSeal.newKey()
        let sealed = try ContentSeal.seal(files, key: key)
        XCTAssertEqual(sealed.prefix(4), Data("RFS1".utf8))
        XCTAssertNil(sealed.range(of: Data("zqcanary0123456789".utf8)), "見張りの文字列が平文で見えない")
        XCTAssertNil(sealed.range(of: Data("封の中の名前".utf8)))
        XCTAssertEqual(try ContentSeal.open(sealed, key: key), files)
        XCTAssertNotEqual(try ContentSeal.seal(files, key: key), sealed, "nonce は毎回変わる")
    }

    /// 絵の封: art/ の png・jpg だけを ArtID(拡張子を除いた名前)で集め、同じ鍵で封じて開くと同じ中身。
    /// 本文の封とは合図が違うので取り違えない。平文の層があればそれを、無ければ封を読む。
    func testArtSealRoundTripAndBundledArt() throws {
        let (root, priv) = try makeSealTestLayer()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array("zqartcanary".utf8))
        let art = priv.appendingPathComponent("art")
        try FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
        try png.write(to: art.appendingPathComponent("portrait.k01.png"))
        try Data([0xFF, 0xD8, 0xFF]).write(to: art.appendingPathComponent("beat.02.jpg"))
        try Data("x".utf8).write(to: art.appendingPathComponent("notes.txt"))
        let collected = try ArtSeal.collect(layer: priv)
        XCTAssertEqual(collected.keys.map(\.rawValue).sorted(), ["beat.02", "portrait.k01"])
        XCTAssertEqual(try ContentSeal.collect(layer: priv).keys.sorted(), ["bundle.json", "text/ja/a.json"],
                       "絵は本文の封に入らない")

        let key = ContentSeal.newKey()
        let sealed = try ArtSeal.seal(collected, key: key)
        XCTAssertEqual(sealed.prefix(4), Data("RFA1".utf8))
        XCTAssertNil(sealed.range(of: Data("zqartcanary".utf8)), "絵の中身が平文で見えない")
        XCTAssertEqual(try ArtSeal.open(sealed, key: key), collected)
        XCTAssertThrowsError(try ArtSeal.open(sealed, key: ContentSeal.newKey()))
        XCTAssertThrowsError(try ContentSeal.open(sealed, key: key), "本文の封としては開けない")
        let textSealed = try ContentSeal.seal(try ContentSeal.collect(layer: priv), key: key)
        XCTAssertThrowsError(try ArtSeal.open(textSealed, key: key), "絵の封としては開けない")

        // アプリの束: 封だけがある → 開く。鍵が無い・封が無い → 空。平文の private があればそれを読む
        let bundle = root.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try sealed.write(to: bundle.appendingPathComponent(ArtSeal.fileName))
        XCTAssertEqual(try ContentLoader.loadBundledArt(root: bundle, key: key), collected)
        XCTAssertEqual(try ContentLoader.loadBundledArt(root: bundle), [:])
        XCTAssertThrowsError(try ContentLoader.loadBundledArt(root: bundle, key: ContentSeal.newKey()))
        try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent("private"), withDestinationURL: priv)
        XCTAssertEqual(try ContentLoader.loadBundledArt(root: bundle), collected)
        XCTAssertEqual(try ContentLoader.loadBundledArt(root: root), [:], "絵の無い束は空")
    }

    /// 1 バイト変える・鍵違い・合図違い・短すぎるは、すべてエラー。
    func testSealRejectsTamperingAndWrongKey() throws {
        let (_, priv) = try makeSealTestLayer()
        let key = ContentSeal.newKey()
        let sealed = try ContentSeal.seal(try ContentSeal.collect(layer: priv), key: key)
        for i in [0, 5, 20, sealed.count - 1] {
            var bad = sealed
            bad[bad.startIndex + i] ^= 0x01
            XCTAssertThrowsError(try ContentSeal.open(bad, key: key), "位置 \(i)")
        }
        XCTAssertThrowsError(try ContentSeal.open(sealed, key: ContentSeal.newKey()))
        XCTAssertThrowsError(try ContentSeal.open(sealed.prefix(20), key: key))
        XCTAssertThrowsError(try ContentSeal.open(sealed, key: key.prefix(16)))
    }

    /// ディレクトリから読んだ層と、封から開いた層が同じ ContentDB になる。鍵が無ければ公開だけ、鍵違いはエラー。
    func testBundledSealedLayerEqualsDirectoryLayer() throws {
        let (root, priv) = try makeSealTestLayer()
        let key = ContentSeal.newKey()
        try ContentSeal.seal(try ContentSeal.collect(layer: priv), key: key)
            .write(to: root.appendingPathComponent(ContentSeal.fileName))
        let fromDir = try ContentLoader.load(sources: [.directory(TestContent.publicLayer),
                                                       .memory(name: "private", files: try ContentSeal.collect(layer: priv))])
        let direct = try ContentLoader.load(layers: [TestContent.publicLayer, priv])
        let bundled = try ContentLoader.loadBundled(root: root, key: key)
        XCTAssertEqual(bundled, direct)
        XCTAssertEqual(bundled, fromDir)
        XCTAssertEqual(bundled.texts["text.name.test_a"], "封の中の名前")
        XCTAssertEqual(bundled.layers.last?.canary, "zqcanary0123456789")
        XCTAssertEqual(try ContentLoader.loadBundled(root: root, key: nil), try TestContent.publicOnly())
        XCTAssertThrowsError(try ContentLoader.loadBundled(root: root, key: ContentSeal.newKey())) { e in
            guard case .sealed? = e as? ContentLoader.LoadError else { return XCTFail("\(e)") }
        }
    }

    /// アプリに埋める鍵のファイルは、鍵の並びをそのまま書かず、2 つの配列の XOR で鍵に戻る。
    func testKeySourceSplitsKey() throws {
        let key = ContentSeal.newKey()
        let src = ContentSeal.keySource(key)
        let hex = key.map { String(format: "0x%02x", $0) }.joined(separator: ", ")
        XCTAssertFalse(src.contains(hex))
        let arrays = try NSRegularExpression(pattern: #"\[UInt8\] = \[([^\]]*)\]"#)
            .matches(in: src, range: NSRange(src.startIndex..., in: src))
            .map { m in (src as NSString).substring(with: m.range(at: 1)).split(separator: ",")
                .map { UInt8($0.trimmingCharacters(in: .whitespaces).dropFirst(2), radix: 16)! } }
        XCTAssertEqual(arrays.count, 2)
        XCTAssertEqual(Data(zip(arrays[0], arrays[1]).map { $0 ^ $1 }), key)
        XCTAssertTrue(ContentSeal.keySource(nil).contains("static let key: Data? = nil"))
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
