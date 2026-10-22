import SwiftUI
import UIKit
import XCTest
import ReForgeEngine
@testable import ReForge

/// 絵の提供元と ArtView の出し方(W-09)。絵のファイルは持たない。試験の中で作る単色の PNG を使う。
@MainActor
final class ArtProviderTests: XCTestCase {
    private let tall: ArtID = "t01"
    private let wide: ArtID = "t02"
    private var original: ArtProvider!

    override func setUp() async throws {
        original = ArtProvider.shared
        ArtProvider.install(ArtProvider(files: [
            tall: ScreenshotArt.solidPNG(width: 110, height: 250),
            wide: ScreenshotArt.solidPNG(width: 200, height: 120),
            "t03": Data("not an image".utf8),
        ]))
    }

    override func tearDown() async throws {
        ArtProvider.install(original)
    }

    func testImageLookup() {
        XCTAssertNotNil(ArtProvider.shared.image(tall))
        XCTAssertNotNil(ArtProvider.shared.image(wide))
        XCTAssertNil(ArtProvider.shared.image("t99"), "無い ID は nil")
        XCTAssertNil(ArtProvider.shared.image("t03"), "壊れた Data は nil(落ちない)")
    }

    func testFailedFlagFollowsInit() {
        XCTAssertFalse(ArtProvider(files: [:]).failed)
        XCTAssertTrue(ArtProvider(files: [:], failed: true).failed)
    }

    /// 幅 100pt に置いたときの出力の高さ ÷ 幅。
    private func heightOverWidth(_ style: ArtStyle, _ id: ArtID) throws -> CGFloat {
        let renderer = ImageRenderer(content: ArtView(id: id, style: style).frame(width: 100))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        return image.size.height / image.size.width
    }

    func testSceneStyleCropsTallAndKeepsWide() throws {
        XCTAssertEqual(try heightOverWidth(.scene, tall), 0.45 * 250 / 110, accuracy: 0.03)
        XCTAssertEqual(try heightOverWidth(.scene, wide), 120.0 / 200.0, accuracy: 0.03)
    }

    func testFullStyleKeepsAspect() throws {
        XCTAssertEqual(try heightOverWidth(.full, tall), 250.0 / 110.0, accuracy: 0.03)
        XCTAssertEqual(try heightOverWidth(.full, wide), 120.0 / 200.0, accuracy: 0.03)
    }

    /// `.square` は縦長も横長も、置いた正方形の枠をそのまま埋める(余白を作らない)。
    func testSquareStyleFillsTheFrame() throws {
        for id in [tall, wide] {
            let renderer = ImageRenderer(content: ArtView(id: id, style: .square).frame(width: 56, height: 56))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 56, accuracy: 0.5)
            XCTAssertEqual(image.size.height, 56, accuracy: 0.5)
            let cg = try XCTUnwrap(image.cgImage)
            for (x, y) in [(1, 1), (54, 54)] {
                XCTAssertEqual(try alpha(cg, x: x, y: y), 255, "\(id) の (\(x), \(y)) が塗られていない")
            }
        }
    }

    /// 左上を原点とした 1 画素の不透明度。
    private func alpha(_ cg: CGImage, x: Int, y: Int) throws -> UInt8 {
        var px: [UInt8] = [0, 0, 0, 0]
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: -x, y: y - cg.height + 1, width: cg.width, height: cg.height))
        return px[3]
    }

    func testMissingArtDrawsNothing() {
        let renderer = ImageRenderer(content: ArtView(id: "t99", style: .scene).frame(width: 100))
        renderer.scale = 1
        XCTAssertNil(renderer.uiImage.flatMap { $0.size.height > 0 ? $0 : nil })
    }
}
