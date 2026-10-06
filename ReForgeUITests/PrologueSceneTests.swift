import XCTest

/// 序の場面(PT-B6)の受け入れと、動画のための操作。
/// 序の見本(アプリの Debug/PrologueSample.swift の中立の 3 行 × 3 場面(3 場面目は折り返す長さの行))を `-ReForgeScreenshot prologue` で開く。
/// - 序の間は、地図・帯・タブ・角のボタンの識別子が画面に無い。
/// - タップで送り(時間では送らない)、最後の行の後のタップで地図の画面に移る。

private let sampleLineCount = 9

private func launchPrologue(style: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    // 「飛ばす」は 2 回目から。印は消して(-ReForgePrologueSeen NO)、1 回目の形で開く
    var args = ["-ReForgeScreenshot", "prologue", "-ReForgePrologueSeen", "NO", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    if let style { args += ["-ReForgePrologueStyle", style] }
    app.launchArguments = args
    app.launch()
    return app
}

private func exists(_ app: XCUIApplication, _ id: String) -> Bool {
    app.descendants(matching: .any).matching(identifier: id).firstMatch.exists
}

@MainActor
final class PrologueSceneTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCoversScreenAndAdvancesToMapByTapOnly() throws {
        let app = launchPrologue()
        defer { app.terminate() }
        let scene = app.descendants(matching: .any).matching(identifier: "prologueScene").firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 60), "序の場面が出ない")

        XCTAssertFalse(exists(app, "prologueSkip"), "1 回目の序に「飛ばす」がある")

        // 序の間: 地図・帯・足元・タブ・角のボタンが画面に無い
        for id in ["map", "statusBand", "footCard", "settingsButton"] {
            XCTAssertFalse(exists(app, id), "序の間に \(id) がある")
        }
        let tabs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'"))
        XCTAssertFalse(tabs.firstMatch.exists, "序の間にタブがある")

        // 時間では送らない: 見せ方の動きが終わる時間を待っても、場面は替わらない
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(scene.exists, "タップしていないのに序が進んだ")

        // タップで送る(画面のどこでもよい)。最後の行の後のタップで地図の画面に移る
        for _ in 0..<sampleLineCount {
            XCTAssertTrue(scene.exists, "送りの途中で序が終わった")
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        let reachedMap = app.descendants(matching: .any).matching(identifier: "footCard").firstMatch.waitForExistence(timeout: 15)
        // 落ちた時に、画面にある識別子の一覧を出す(原因を当て推量しない)
        let present = reachedMap ? "" : app.debugDescription.split(separator: "\n")
            .compactMap { line -> String? in
                guard let r = line.range(of: "identifier: '") else { return nil }
                return String(line[r.upperBound...].prefix { $0 != "'" })
            }.joined(separator: ",")
        XCTAssertTrue(reachedMap, "最後の行の後のタップで地図の画面に移らない。画面の識別子: \(present)")
        // 移りの演出(約 1.7 秒)が終わると、覆いが消え、角のボタンが戻る
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settingsButton").firstMatch.waitForExistence(timeout: 15),
                      "地図に移った後に角のボタンが戻らない")
        XCTAssertFalse(exists(app, "prologueScene"), "移った後も序が残っている")
    }

    /// 折り返す長さの行(見本の 3 場面目)を出しても、行どうしの frame が交差しない(次の行は前の行の下に積まれる)。
    func testWrappedLinesDoNotOverlap() throws {
        let app = launchPrologue()
        defer { app.terminate() }
        let scene = app.descendants(matching: .any).matching(identifier: "prologueScene").firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 60), "序の場面が出ない")
        func line(_ i: Int) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "prologueLine-\(i)").firstMatch
        }
        // 3 場面目の 3 行目まで送る(前の 2 場面で 6 回、同じ場面の 2 行目・3 行目で 2 回)
        for _ in 0..<8 {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        Thread.sleep(forTimeInterval: 1.5)
        let frames = (0..<3).map { i -> CGRect in
            XCTAssertTrue(line(i).waitForExistence(timeout: 10), "行 \(i) の識別子が無い")
            return line(i).frame
        }
        // 長い行は 1 段より高い(折り返している)ことを確かめて、試験が空振りしないようにする
        XCTAssertGreaterThan(frames[0].height, frames[1].height * 1.5, "長い行が折り返していない: \(frames)")
        for i in 1..<3 {
            XCTAssertGreaterThanOrEqual(frames[i].minY, frames[i - 1].maxY - 0.5,
                                        "行 \(i) が前の行と重なる: \(frames[i - 1]) / \(frames[i])")
        }
    }
}

/// 動画の操作(CI の screens ジョブが `simctl io recordVideo` を回している間に、起動から地図へ移るまで送る)。
/// 案ごとの出方の違い(1 行ずつ・1 字ずつ・段)を撮るので、送りの間は案の出終わりまで待つ。
@MainActor
final class PrologueVideoTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testStyleA() throws { play(style: "a", pause: 1.8) }
    func testStyleB() throws { play(style: "b", pause: 2.6) }
    func testStyleC() throws { play(style: "c", pause: 2.0) }

    private func play(style: String, pause: TimeInterval) {
        let app = launchPrologue(style: style)
        defer { app.terminate() }
        let scene = app.descendants(matching: .any).matching(identifier: "prologueScene").firstMatch
        guard scene.waitForExistence(timeout: 60) else {
            XCTFail("序の場面が出ない")
            return
        }
        Thread.sleep(forTimeInterval: pause)
        for _ in 0..<sampleLineCount where scene.exists {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
            Thread.sleep(forTimeInterval: pause)
        }
        _ = app.descendants(matching: .any).matching(identifier: "footCard").firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 1.5)
    }
}
