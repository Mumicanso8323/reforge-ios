import XCTest
import UIKit

/// 日没に「寝る」を押して朝になった後(人の通り道。録画の台本の合わせ直しを通らない)も、地図に地形の画素が出ていること。
/// 撮影の世界(公開の層の中立の試験用の中身)の日没から始める。画面の写しの中ほど(地図の所)の明るい画素の割合で見る。
@MainActor
final class MapPixelsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func one(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 画面の中ほど(縦 30〜70%)で、明るい画素(最大の色が 48 を超える)の割合。
    private func litFraction() -> Double {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return -1 }
        var lit = 0, total = 0
        for y in stride(from: h * 3 / 10, to: h * 7 / 10, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let i = (y * w + x) * 4
                total += 1
                if max(pixels[i], pixels[i + 1], pixels[i + 2]) > 48 { lit += 1 }
            }
        }
        return total == 0 ? -1 : Double(lit) / Double(total)
    }

    func testMapKeepsTerrainPixelsAfterSleepingThroughTheNight() {
        let app = XCUIApplication()
        app.launchArguments = ["-ReForgeScreenshot", "dayWrap", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(one(app, "dayWrapMade").waitForExistence(timeout: 60), "日没の締めが出ない")
        Thread.sleep(forTimeInterval: 2)
        let before = litFraction()
        XCTAssertGreaterThan(before, 0.01, "日没の地図に地形の画素が無い(この試験の前提が成り立たない): \(before)")

        let sleep = app.buttons["寝る"].firstMatch
        XCTAssertTrue(sleep.waitForExistence(timeout: 30), "「寝る」が無い")
        sleep.tap()
        // 朝になる(日没の締めが消える)のを待ってから、2 秒後・以後 8 秒の間、毎秒測る
        let deadline = Date().addingTimeInterval(30)
        while one(app, "dayWrapMade").exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertFalse(one(app, "dayWrapMade").exists, "朝にならない")
        Thread.sleep(forTimeInterval: 2)
        var samples: [Double] = []
        for _ in 0..<8 {
            samples.append(litFraction())
            Thread.sleep(forTimeInterval: 1)
        }
        let low = samples.filter { $0 < 0.01 }
        XCTAssertTrue(low.isEmpty, "朝の地図に地形の画素が無い時がある(明るい画素の割合 \(samples.map { String(format: "%.3f", $0) }))")
    }
}
