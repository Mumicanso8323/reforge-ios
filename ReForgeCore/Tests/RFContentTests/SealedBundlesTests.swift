import Foundation
import RFContent
import RFKernel
import RFPresent
import RFTestSupport
import XCTest

final class SealedBundlesTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rf-sealed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func write(_ string: String, _ relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(string.utf8).write(to: url)
    }

    private func makeLayer(in root: URL) throws -> URL {
        let layer = root.appendingPathComponent("source-layer", isDirectory: true)
        try write(#"{"bundle":{"id":"private","visibility":"private","version":"test"}}"#, "bundle.json", in: layer)
        try write(#"{"facts":[{"id":"fact.sample"}]}"#, "world.json", in: layer)
        try write(#"{"texts":{"text.sample":"sample text"}}"#, "text/ja/a.json", in: layer)
        try write(#"{"language":"en","texts":{"text.sample":"sample translation"}}"#, "text/en/a.json", in: layer)
        return layer
    }

    private func sealSplit(_ layer: URL, into root: URL, key: Data) throws {
        let split = try ContentSeal.collectSplit(layer: layer)
        try ContentSeal.seal(split.base, key: key).write(to: root.appendingPathComponent(ContentSeal.fileName))
        for (language, files) in split.text {
            try ContentSeal.seal(files, key: key).write(to: root.appendingPathComponent(ContentSeal.textFileName(language)))
        }
    }

    private func publicLayer(in root: URL) throws {
        try write(#"{"texts":{"text.public":"public text"}}"#, "public/a.json", in: root)
    }

    func testCollectSplitKeepsUnknownAndPseudoDirectoriesInBase() throws {
        let root = try temporaryRoot()
        let layer = root.appendingPathComponent("layer")
        try write(#"{"facts":[{"id":"fact.sample"}]}"#, "world.json", in: layer)
        try write(#"{"texts":{"a":"one"}}"#, "text/ja/a.json", in: layer)
        try write(#"{"nameJoin":{"order":["shape"],"separator":""}}"#, "text/ja/_meta.json", in: layer)
        try write(#"{"language":"en","texts":{"a":"two"}}"#, "text/en/a.json", in: layer)
        try write(#"{}"#, "text/xx/a.json", in: layer)
        try write(#"{}"#, "text/x-pseudo/a.json", in: layer)

        let split = try ContentSeal.collectSplit(layer: layer)
        XCTAssertEqual(Set(split.base.keys), ["world.json", "text/xx/a.json", "text/x-pseudo/a.json"])
        XCTAssertEqual(Set(split.text[.ja]?.keys.map { $0 } ?? []), ["text/ja/a.json", "text/ja/_meta.json"])
        XCTAssertEqual(Set(split.text[.en]?.keys.map { $0 } ?? []), ["text/en/a.json"])
        XCTAssertEqual(ContentSeal.textFileName(.zhHans), "text-zh-Hans.sealed")
        XCTAssertEqual(ContentSeal.textLanguage(ofPath: "text/zh-Hans/a.json"), .zhHans)
        XCTAssertNil(ContentSeal.textLanguage(ofPath: "text/x-pseudo/a.json"))
        XCTAssertNil(ContentSeal.textLanguage(ofPath: "text/xx/a.json"))
    }

    func testSplitAndLegacyBundlesLoadTheSameContent() throws {
        let root = try temporaryRoot()
        try publicLayer(in: root)
        let layer = try makeLayer(in: root)
        let key = ContentSeal.newKey()
        let direct = try ContentLoader.load(layers: [root.appendingPathComponent("public"), layer])

        try sealSplit(layer, into: root, key: key)
        XCTAssertEqual(try ContentLoader.loadBundled(root: root, key: key), direct)

        try FileManager.default.removeItem(at: root.appendingPathComponent(ContentSeal.fileName))
        for language in [LanguageID.ja, .en] {
            try FileManager.default.removeItem(at: root.appendingPathComponent(ContentSeal.textFileName(language)))
        }
        try ContentSeal.seal(try ContentSeal.collect(layer: layer), key: key)
            .write(to: root.appendingPathComponent(ContentSeal.fileName))
        XCTAssertEqual(try ContentLoader.loadBundled(root: root, key: key), direct)
    }

    func testMissingAndBrokenSecondaryLanguageDoesNotStopJapanese() throws {
        let root = try temporaryRoot()
        try publicLayer(in: root)
        let layer = try makeLayer(in: root)
        let key = ContentSeal.newKey()
        try sealSplit(layer, into: root, key: key)
        let english = root.appendingPathComponent(ContentSeal.textFileName(.en))
        try FileManager.default.removeItem(at: english)

        var result = try ContentLoader.loadBundledReport(root: root, key: key, expecting: [.ja, .en])
        XCTAssertEqual(result.report.missing, [.en])
        XCTAssertEqual(result.db.textTables.lookup("text.sample", .en), .fallback("sample text"))
        XCTAssertTrue(result.report.opened.contains(.ja))
        XCTAssertEqual(try ContentLoader.loadBundledReport(root: root, key: key).report.missing, [])

        try ContentSeal.seal((try ContentSeal.collectSplit(layer: layer)).text[.en]!, key: ContentSeal.newKey()).write(to: english)
        result = try ContentLoader.loadBundledReport(root: root, key: key, expecting: [.ja, .en])
        XCTAssertEqual(result.report.failed, [.en])
        XCTAssertEqual(result.db.textTables.lookup("text.sample", .en), .fallback("sample text"))
    }

    func testJapaneseFailureAndBundleSwapFallBackToPublicContent() throws {
        let root = try temporaryRoot()
        try publicLayer(in: root)
        let layer = try makeLayer(in: root)
        let key = ContentSeal.newKey()
        try sealSplit(layer, into: root, key: key)
        let japanese = root.appendingPathComponent(ContentSeal.textFileName(.ja))
        var broken = try Data(contentsOf: japanese)
        broken[broken.startIndex] ^= 1
        try broken.write(to: japanese)
        XCTAssertThrowsError(try ContentLoader.loadBundled(root: root, key: key))
        let fallback = try GameBootstrap.loadContentFallingBack(contentDirectory: root, key: key)
        XCTAssertTrue(fallback.sealedFailed)
        XCTAssertEqual(fallback.content.texts["text.public"], "public text")

        try sealSplit(layer, into: root, key: key)
        try FileManager.default.removeItem(at: japanese)
        XCTAssertThrowsError(try ContentLoader.loadBundled(root: root, key: key))

        try sealSplit(layer, into: root, key: key)
        let english = root.appendingPathComponent(ContentSeal.textFileName(.en))
        try FileManager.default.removeItem(at: japanese)
        try FileManager.default.copyItem(at: english, to: japanese)
        let report = try ContentLoader.loadBundledReport(root: root, key: key, expecting: [.ja])
        XCTAssertEqual(report.report.failed, [.ja])
    }

    func testBundlesHidePlaintextAndUseDistinctNonces() throws {
        let root = try temporaryRoot()
        let layer = try makeLayer(in: root)
        let key = ContentSeal.newKey()
        try sealSplit(layer, into: root, key: key)
        let base = try Data(contentsOf: root.appendingPathComponent(ContentSeal.fileName))
        let japanese = try Data(contentsOf: root.appendingPathComponent(ContentSeal.textFileName(.ja)))
        let english = try Data(contentsOf: root.appendingPathComponent(ContentSeal.textFileName(.en)))
        let plain = Data("sample text".utf8)
        XCTAssertNil(base.range(of: plain))
        XCTAssertNil(japanese.range(of: plain))
        XCTAssertNil(english.range(of: plain))
        XCTAssertNotEqual(base[4..<16], japanese[4..<16])
        XCTAssertNotEqual(japanese[4..<16], english[4..<16])
    }

    func testWritingNewBundlesRemovesStaleLanguageBundles() throws {
        let root = try temporaryRoot()
        let stale = root.appendingPathComponent(ContentSeal.textFileName(.zhHant))
        try Data("stale".utf8).write(to: stale)
        ContentSeal.removeTextBundles(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: empty.appendingPathComponent(ContentSeal.textFileName(.en)))
        ContentSeal.removeTextBundles(in: empty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: empty.path), [])
    }

    func testReleasedLanguagesAreJapaneseAndAValidShippedSubset() {
        XCTAssertEqual(LanguageID.released, [.ja], "出す言語を変えるのは本人の決め")
        XCTAssertTrue(Set(LanguageID.released).isSubset(of: Set(LanguageID.shipped)))
        XCTAssertTrue(LanguageID.released.contains(.ja))
        XCTAssertFalse(LanguageID.released.contains(.pseudo))
    }

    func testActualPrivateLayerRoundTripsWhenAvailable() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開の層が無い")
        let root = try temporaryRoot()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("public"),
                                                   withDestinationURL: TestContent.publicLayer)
        let privateLayer = try XCTUnwrap(ContentLoader.privateLayer(publicLayer: TestContent.publicLayer,
                                                                     environment: ProcessInfo.processInfo.environment))
        let direct = try ContentLoader.load(layers: [TestContent.publicLayer, privateLayer])
        let key = ContentSeal.newKey()
        try sealSplit(privateLayer, into: root, key: key)
        XCTAssertEqual(try ContentLoader.loadBundled(root: root, key: key), direct)
    }
}
