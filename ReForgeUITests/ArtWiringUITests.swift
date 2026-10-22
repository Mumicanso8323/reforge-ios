import XCTest

/// 絵の受け口(W-09)。`-ReForgeScreenshotArt present|missing` で、単色の見本の絵(アプリの DEBUG が作る)を場面と決断の帯に出す。
/// 絵が無い・開かないときは、引数なしと同じ並び(frame が同じ)であることを確かめる。ScreenSnapshotTests の 80 枚には入れない。
private func launch(_ screen: String, art: String?, language: String = "ja", reduceMotion: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    var args = ["-ReForgeScreenshot", screen, "-ReForgePrologueSeen", "NO", "-AppleLanguages", "(\(language))", "-AppleLocale", language]
    if let art { args += ["-ReForgeScreenshotArt", art] }
    if reduceMotion { args += ["-UIAccessibilityReduceMotion", "YES"] }
    app.launchArguments = args
    app.launch()
    return app
}

private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
}

private func tapAnywhere(_ app: XCUIApplication, dy: CGFloat = 0.8) {
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).tap()
}

@MainActor
final class ArtWiringUITests: XCTestCase {
    private static let locales: [(String, String)] = [("ja", "ja_JP"), ("en", "en_US"), ("zh-Hans", "zh_CN"), ("zh-Hant", "zh_TW"), ("ko", "ko_KR")]

    override func setUpWithError() throws { continueAfterFailure = true }

    private func checkStageWithArt(language: String, reduceMotion: Bool) {
        let app = launch("stage", art: "present", language: language, reduceMotion: reduceMotion)
        defer { app.terminate() }
        XCTAssertTrue(element(app, "prologueScene").waitForExistence(timeout: 60), "場面が出ない")
        let art = element(app, "sceneArt")
        XCTAssertTrue(art.waitForExistence(timeout: 15), "sceneArt が無い (\(language))")
        let screen = app.windows.firstMatch.frame
        let line0 = element(app, "prologueLine-0")
        XCTAssertTrue(line0.waitForExistence(timeout: 15))
        XCTAssertTrue(screen.contains(art.frame), "絵が画面の外 (\(language))")
        XCTAssertFalse(art.frame.intersects(line0.frame), "絵が最初の行と重なる (\(language))")
        let before = art.frame
        tapAnywhere(app, dy: 0.15)  // 絵の上でも送れる
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(element(app, "prologueLine-1").exists, "絵の上のタップで送れない (\(language))")
        XCTAssertEqual(art.frame.minY, before.minY, accuracy: 0.5, "次の行で絵が動いた")
        XCTAssertEqual(art.frame.height, before.height, accuracy: 0.5)
    }

    private func checkDecisionWithArt(language: String, reduceMotion: Bool) {
        let app = launch("decisionBand", art: "present", language: language, reduceMotion: reduceMotion)
        defer { app.terminate() }
        let band = element(app, "decisionBand")
        XCTAssertTrue(band.waitForExistence(timeout: 60), "決断の帯が出ない")
        let art = element(app, "decisionArt")
        XCTAssertTrue(art.waitForExistence(timeout: 15), "decisionArt が無い (\(language))")
        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(art.frame.width, 56, accuracy: 0.5)
        XCTAssertEqual(art.frame.height, 56, accuracy: 0.5)
        XCTAssertTrue(screen.contains(art.frame), "絵が画面の外 (\(language))")
        XCTAssertTrue(screen.contains(element(app, "decisionPrompt").frame), "問いの文が画面の外 (\(language))")
        let buttons = band.buttons
        XCTAssertGreaterThan(buttons.count, 0)
        for i in 0..<buttons.count {
            XCTAssertTrue(screen.contains(buttons.element(boundBy: i).frame), "選ぶボタンが画面の外 (\(language))")
        }
    }

    func testStageArtDoesNotOverlapAndDoesNotMove() { checkStageWithArt(language: "ja", reduceMotion: false) }
    func testDecisionArtLayout() { checkDecisionWithArt(language: "ja", reduceMotion: false) }
    func testStageArtWithReduceMotion() { checkStageWithArt(language: "ja", reduceMotion: true) }
    func testDecisionArtWithReduceMotion() { checkDecisionWithArt(language: "ja", reduceMotion: true) }

    /// 文が長い言語でも、絵と文が重ならず、帯が画面に収まる。
    func testMultipleLanguages() {
        for (code, _) in Self.locales.prefix(3) {
            checkStageWithArt(language: code, reduceMotion: false)
            checkDecisionWithArt(language: code, reduceMotion: false)
        }
    }

    /// 絵が無い・開かないときは、引数なしと行の位置が同じ(1 ピクセルも動かない)。
    func testMissingArtLeavesStageLayoutUntouched() {
        func lineFrames(_ art: String?) -> [CGRect] {
            let app = launch("stage", art: art)
            defer { app.terminate() }
            XCTAssertTrue(element(app, "prologueScene").waitForExistence(timeout: 60))
            XCTAssertFalse(element(app, "sceneArt").exists, "絵が無いのに sceneArt がある")
            tapAnywhere(app)
            Thread.sleep(forTimeInterval: 1.0)
            tapAnywhere(app)
            Thread.sleep(forTimeInterval: 1.0)
            return (0...2).map { element(app, "prologueLine-\($0)").frame }
        }
        let plain = lineFrames(nil)
        let missing = lineFrames("missing")
        XCTAssertEqual(plain.count, missing.count)
        for (a, b) in zip(plain, missing) {
            XCTAssertEqual(a.minX, b.minX, accuracy: 0.5)
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.5)
            XCTAssertEqual(a.width, b.width, accuracy: 0.5)
            XCTAssertEqual(a.height, b.height, accuracy: 0.5)
        }
    }

    func testMissingArtLeavesDecisionBandUntouched() {
        func bandHeight(_ art: String?) -> CGFloat {
            let app = launch("decisionBand", art: art)
            defer { app.terminate() }
            let band = element(app, "decisionBand")
            XCTAssertTrue(band.waitForExistence(timeout: 60))
            XCTAssertFalse(element(app, "decisionArt").exists, "絵が無いのに decisionArt がある")
            return band.frame.height
        }
        XCTAssertEqual(bandHeight("missing"), bandHeight(nil), accuracy: 0.5)
    }
}
