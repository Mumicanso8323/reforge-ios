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
