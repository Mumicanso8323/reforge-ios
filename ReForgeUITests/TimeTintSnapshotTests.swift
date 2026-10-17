import XCTest
import UIKit
import CryptoKit

/// 時刻の色の写真(W-19・TEST-O24・TEST-O22 の (2))。`-ReForgeScreenshot map` を、時刻 4 点(夜明け・昼・夕方・夜)で撮る。
/// 外観(ダーク/ライト)は環境変数 `REFORGE_APPEARANCE` で名前を決めるだけ。切り替えは CI が `xcrun simctl ui <udid> appearance` でする
/// (`XCUIDevice.appearance` に頼らない)。部品は暗い地のまま固定(INV-O16)なので、地図の外は外観によらず同じ画素になるはず。
/// 1 枚ごとに、添付 `time_<点>_<外観>`(PNG)と `timehash_<点>_<外観>`(JSON)を残す。判定は tools/check-time-tint-shots.py(CI)。
@MainActor
final class TimeTintSnapshotTests: XCTestCase {
    private static let points = ["dawn", "noon", "evening", "night"]
    /// 設定のボタンの上の余白(角は 52pt・ボタンは 44pt。ScreenSnapshotTests と同じ割り出し)。
    private static let cornerPad: CGFloat = 4

    private struct Hashes: Codable {
        let point: String
        let appearance: String
        /// 地図の枠の外のすべての画素(上の安全領域の帯は除く)
        let outside: String
        /// タブの帯(`tab-*` の要素の和の枠)
        let tabs: String
        /// 地図の枠の中
        let map: String
        /// 地図の枠の中の、予約の赤の画素の割合(0...1)
        let redFraction: Double
        let dayBar: Bool
        /// dayBar のラベルに数字が無い(dayBar が無いときは true)
        let dayBarLabelHasNoDigits: Bool
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testTimePoints() {
        let appearance = ProcessInfo.processInfo.environment["REFORGE_APPEARANCE"] ?? "dark"
        for point in Self.points {
            XCTContext.runActivity(named: "time_\(point)_\(appearance)") { _ in shoot(point: point, appearance: appearance) }
        }
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func shoot(point: String, appearance: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-ReForgeScreenshot", "map", "-ReForgeScreenshotTime", point,
                               "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        defer { app.terminate() }

        let guardElement = element(app, "screenshotGuard")
        guard guardElement.waitForExistence(timeout: 60), (guardElement.value as? String) == "ok" else {
            XCTFail("\(point)_\(appearance): 公開の層だけの撮る起動になっていない")
            return
        }
        _ = element(app, "footCard").waitForExistence(timeout: 30)
        // 地図の絵が出そろうのを待つ(最初の絵は予算に数えず、その場で描く)
        Thread.sleep(forTimeInterval: 2.0)

        let window = app.windows.firstMatch.frame
        let mapFrame = element(app, "map").frame
        guard !window.isEmpty, !mapFrame.isEmpty else {
            XCTFail("\(point)_\(appearance): 画面か地図の枠を測れない")
            return
        }
        var tabs = CGRect.null
        for tab in app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'")).allElementsBoundByIndex {
            let f = tab.frame
            if !f.isEmpty { tabs = tabs.union(f) }
        }
        let settings = element(app, "settingsButton")
        let safeTop = settings.exists ? settings.frame.minY - Self.cornerPad : 0
        let dayBar = element(app, "dayBar")
        let dayBarExists = dayBar.exists
        let labelOK = !dayBarExists || dayBar.label.rangeOfCharacter(from: .decimalDigits) == nil

        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "time_\(point)_\(appearance)"
        shot.lifetime = .keepAlways
        add(shot)

        guard !tabs.isNull, let cg = screenshot.image.cgImage else {
            XCTFail("\(point)_\(appearance): タブの帯か写真の画素を読めない")
            return
        }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else {
            XCTFail("\(point)_\(appearance): 写真の画素を読めない")
            return
        }
        let scale = Double(w) / Double(window.width)
        func pixelRect(_ r: CGRect) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
            (max(0, Int((Double(r.minX) * scale).rounded(.down))), max(0, Int((Double(r.minY) * scale).rounded(.down))),
             min(w, Int((Double(r.maxX) * scale).rounded(.up))), min(h, Int((Double(r.maxY) * scale).rounded(.up))))
        }
        let map = pixelRect(mapFrame)
        let tab = pixelRect(tabs)
        let top = min(h, Int((Double(safeTop) * scale).rounded(.up)))

        func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
        func hashRect(_ r: (x0: Int, y0: Int, x1: Int, y1: Int)) -> String {
            var sha = SHA256()
            pixels.withUnsafeBytes { raw in
                for y in r.y0..<max(r.y0, r.y1) where r.x1 > r.x0 {
                    sha.update(bufferPointer: UnsafeRawBufferPointer(rebasing: raw[(y * w + r.x0) * 4 ..< (y * w + r.x1) * 4]))
                }
            }
            return hex(sha.finalize())
        }
        // 地図の枠の外: 上の安全領域の帯より下の全画素から、地図の枠を除いたもの
        var outside = SHA256()
        pixels.withUnsafeBytes { raw in
            func feed(_ y: Int, _ a: Int, _ b: Int) {
                if b > a { outside.update(bufferPointer: UnsafeRawBufferPointer(rebasing: raw[(y * w + a) * 4 ..< (y * w + b) * 4])) }
            }
            for y in top..<h {
                if y >= map.y0, y < map.y1 {
                    feed(y, 0, map.x0)
                    feed(y, map.x1, w)
                } else {
                    feed(y, 0, w)
                }
            }
        }
        // 予約の赤(TimeTintPalette.isReservedRed と同じ整数の式。本体は import せずここに写す)
        func isReservedRed(_ r: Int, _ g: Int, _ b: Int) -> Bool {
            let high = max(r, max(g, b)), low = min(r, min(g, b))
            let delta = high - low
            guard delta > 0, r == high else { return false }
            let hueNearRed = 10 * abs(g - b) <= 3 * delta
            let lightSpan = 255 - abs(high + low - 255)
            return hueNearRed && 2 * delta >= lightSpan
        }
        var red = 0, total = 0
        for y in map.y0..<max(map.y0, map.y1) {
            for x in map.x0..<max(map.x0, map.x1) {
                let i = (y * w + x) * 4
                total += 1
                if isReservedRed(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])) { red += 1 }
            }
        }
        let record = Hashes(point: point, appearance: appearance, outside: hex(outside.finalize()), tabs: hashRect(tab),
                            map: hashRect(map), redFraction: total == 0 ? 1 : Double(red) / Double(total),
                            dayBar: dayBarExists, dayBarLabelHasNoDigits: labelOK)
        if let data = try? JSONEncoder().encode(record) {
            let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            a.name = "timehash_\(point)_\(appearance)"
            a.lifetime = .keepAlways
            add(a)
        } else {
            XCTFail("\(point)_\(appearance): 画素の要約を JSON にできない")
        }
    }
}
