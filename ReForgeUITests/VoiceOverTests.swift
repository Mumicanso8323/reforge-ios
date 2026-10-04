import XCTest

/// 読み上げの名前と読む順(A-04c)。撮る起動(`-ReForgeScreenshot <画面>`)で開く。
/// - 暗い場面の最初の行為・操作棒・足元カードの行為・全画面の場面の送りが、読み上げの要素で、名前が空でない。
/// - 地図の画面の要素の縦の並びが、上の帯 < 地図 < 足元カード < タブの棒。
@MainActor
final class VoiceOverTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ReForgeScreenshot", screen, "-ReForgePrologueSeen", "NO",
                               "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func assertSpoken(_ app: XCUIApplication, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 60), "\(id) が出ない", file: file, line: line)
        XCTAssertFalse(e.label.isEmpty, "\(id) の名前が空", file: file, line: line)
    }

    func testDarkStartActionIsSpoken() {
        let app = launch("darkStart")
        defer { app.terminate() }
        assertSpoken(app, "darkStartAct")
    }

    func testMapStickAndFootActionAreSpokenInReadingOrder() {
        let app = launch("foot")
        defer { app.terminate() }
        assertSpoken(app, "stickControl")
        XCTAssertTrue(element(app, "footCard").waitForExistence(timeout: 30))
        // 足元カードの行為(押すだけは Button、長押しは holdRing)。名前のある行為が 1 つ以上ある
        let card = element(app, "footCard")
        let actions = app.descendants(matching: .any).matching(identifier: "holdRing").allElementsBoundByIndex
            + app.descendants(matching: .any).matching(identifier: "footAction").allElementsBoundByIndex
        XCTAssertFalse(actions.isEmpty, "足元カードに行為が無い")
        XCTAssertTrue(actions.contains { !$0.label.isEmpty }, "足元カードの行為に名前が無い")

        let status = element(app, "statusBand").frame
        let map = element(app, "map").frame
        let foot = card.frame
        let tab = element(app, "tab-map").frame
        XCTAssertLessThan(status.minY, map.minY, "上の帯が地図より下にある")
        XCTAssertLessThan(map.minY, foot.minY, "地図が足元カードより下にある")
        XCTAssertLessThan(foot.minY, tab.minY, "足元カードがタブの棒より下にある")
    }

    func testPrologueSceneIsSpoken() {
        let app = launch("prologue")
        defer { app.terminate() }
        assertSpoken(app, "prologueScene")
    }
}
