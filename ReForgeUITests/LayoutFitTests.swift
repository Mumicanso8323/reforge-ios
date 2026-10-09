import XCTest
import UIKit

/// 上の帯の項目が設定の角(歯車)と重ならず切れないこと(D)と、足元カードの行為の名前が省略されないこと(E)。
/// 撮影の世界(公開の層の中立の試験用の中身)を、標準の文字と大きい文字で開いて測る。
@MainActor
final class LayoutFitTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ screen: String, category: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-ReForgeScreenshot", screen, "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if let category { args += ["-UIPreferredContentSizeCategoryName", category] }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func all(_ app: XCUIApplication, prefix: String) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
    }

    private func one(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func checkStatusBand(_ app: XCUIApplication, _ tag: String) {
        let band = one(app, "statusBand")
        XCTAssertTrue(band.waitForExistence(timeout: 60), "\(tag): 上の帯が出ない")
        let gear = one(app, "settingsButton")
        XCTAssertTrue(gear.waitForExistence(timeout: 30), "\(tag): 歯車が出ない")
        XCTAssertGreaterThanOrEqual(gear.frame.width, 44, "\(tag): 歯車が小さい")
        XCTAssertGreaterThanOrEqual(gear.frame.height, 44, "\(tag): 歯車が小さい")
        let screen = app.windows.firstMatch.frame
        let items = all(app, prefix: "status-item-")
        XCTAssertFalse(items.isEmpty, "\(tag): 帯の項目が無い")
        for item in items {
            let f = item.frame
            XCTAssertFalse(f.intersects(gear.frame), "\(tag): \(item.identifier) が歯車と重なる \(f)")
            XCTAssertLessThanOrEqual(f.maxX, screen.maxX + 0.5, "\(tag): \(item.identifier) の右端が画面の外")
            XCTAssertGreaterThanOrEqual(f.minX, screen.minX - 0.5, "\(tag): \(item.identifier) の左端が画面の外")
            XCTAssertLessThanOrEqual(f.maxX, gear.frame.minX + 0.5, "\(tag): \(item.identifier) が歯車の列に入る(右の余白を越えた)")
        }
    }

    /// 押せる物は縦も横も 44pt 以上(SL-32)。地図の画面と足元カードの画面にある全てのボタン。
    func testEveryButtonIsAtLeast44Points() {
        for screen in ["map", "foot"] {
            let app = launch(screen)
            defer { app.terminate() }
            XCTAssertTrue(one(app, "statusBand").waitForExistence(timeout: 60), "\(screen): 上の帯が出ない")
            let window = app.windows.firstMatch.frame
            for button in app.buttons.allElementsBoundByIndex where button.exists && button.isHittable {
                let f = button.frame
                guard f.intersects(window) else { continue }
                XCTAssertGreaterThanOrEqual(f.width, 43.5, "\(screen): \(button.identifier) の幅が 44pt 未満 \(f)")
                XCTAssertGreaterThanOrEqual(f.height, 43.5, "\(screen): \(button.identifier) の高さが 44pt 未満 \(f)")
            }
        }
    }

    func testStatusBandAvoidsGear() {
        let app = launch("map")
        defer { app.terminate() }
        checkStatusBand(app, "標準")
    }

    func testStatusBandAvoidsGearAtLargeText() {
        let app = launch("map", category: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        checkStatusBand(app, "大きい文字")
    }

    /// 行為のボタンが画面とカードの中にあり、名前が 2 行まで折り返して収まる幅(省略されない)を持つ。
    private func checkFootActions(_ app: XCUIApplication, _ tag: String) {
        let card = one(app, "footCard")
        XCTAssertTrue(card.waitForExistence(timeout: 60), "\(tag): 足元カードが出ない")
        let screen = app.windows.firstMatch.frame
        let buttons = app.descendants(matching: .any).matching(identifier: "holdRing").allElementsBoundByIndex
            + app.descendants(matching: .any).matching(identifier: "footAction").allElementsBoundByIndex
        XCTAssertFalse(buttons.isEmpty, "\(tag): 行為が無い")
        let font = UIFont.preferredFont(forTextStyle: .body)
        for b in buttons {
            let label = b.label
            XCTAssertFalse(label.isEmpty, "\(tag): 行為の名前が空")
            let f = b.frame
            XCTAssertTrue(screen.insetBy(dx: -0.5, dy: -0.5).contains(f), "\(tag): 行為のボタンが画面の外 \(f)")
            XCTAssertTrue(card.frame.insetBy(dx: -0.5, dy: -0.5).contains(f), "\(tag): 行為のボタンが足元カードの外 \(f)")
            XCTAssertGreaterThanOrEqual(f.height, 44, "\(tag): 行為のボタンが低い")
            // 余白と輪を除いた幅で 2 行に収まる(2 行ぶんの幅 >= 1 行の全長)。収まらなければ末尾が省略される
            let whole = (label as NSString).size(withAttributes: [.font: font]).width
            let avail = f.width - 28 - (b.identifier == "holdRing" ? 30 : 0)
            XCTAssertGreaterThanOrEqual(avail * 2 + 1, whole, "\(tag): 行為の名前が 2 行に収まらず省略される(幅 \(Int(f.width)))")
        }
        for i in buttons.indices {
            for j in buttons.indices where j > i {
                XCTAssertFalse(buttons[i].frame.intersects(buttons[j].frame), "\(tag): 行為のボタンが重なる")
            }
        }
    }

    func testFootActionNamesNotTruncated() {
        let app = launch("foot")
        defer { app.terminate() }
        checkFootActions(app, "標準")
    }

    func testFootActionNamesNotTruncatedAtLargeText() {
        let app = launch("foot", category: "UICTContentSizeCategoryAccessibilityL")
        defer { app.terminate() }
        checkFootActions(app, "大きい文字")
    }

    /// 日没の締めの各行が画面の中に収まり(左へはみ出して切れない)、地図の操作棒・足元カードと重ならない。
    private func checkDayWrap(_ app: XCUIApplication, _ tag: String) {
        let made = one(app, "dayWrapMade")
        XCTAssertTrue(made.waitForExistence(timeout: 60), "\(tag): 今日できた物の行が出ない")
        let screen = app.windows.firstMatch.frame
        let stick = one(app, "stickControl")
        let card = one(app, "footCard")
        XCTAssertTrue(card.waitForExistence(timeout: 30), "\(tag): 足元カードが出ない")
        for id in ["dayWrapMadeLabel", "dayWrapMade", "dayWrapRunning", "dayWrapOutlookLabel", "dayWrapOutlook"] {
            let e = one(app, id)
            guard e.exists else { continue }
            let f = e.frame
            XCTAssertGreaterThanOrEqual(f.minX, screen.minX - 0.5, "\(tag): \(id) の左端が画面の外 \(f)")
            XCTAssertLessThanOrEqual(f.maxX, screen.maxX + 0.5, "\(tag): \(id) の右端が画面の外 \(f)")
            XCTAssertFalse(f.intersects(card.frame), "\(tag): \(id) が足元カードと重なる \(f)")
            if stick.exists { XCTAssertFalse(f.intersects(stick.frame), "\(tag): \(id) が操作棒と重なる \(f)") }
        }
        let label = one(app, "dayWrapMadeLabel")
        XCTAssertTrue(label.exists, "\(tag): 見出しが出ない")
        XCTAssertLessThan(label.frame.maxX, made.frame.minX + 6.5, "\(tag): 見出しと名前の並びが重なる")
    }

    func testDayWrapFitsScreen() {
        let app = launch("dayWrap")
        defer { app.terminate() }
        checkDayWrap(app, "標準")
    }

    func testDayWrapFitsScreenAtLargeText() {
        let app = launch("dayWrap", category: "UICTContentSizeCategoryAccessibilityXXXL")
        defer { app.terminate() }
        checkDayWrap(app, "大きい文字")
    }
}
