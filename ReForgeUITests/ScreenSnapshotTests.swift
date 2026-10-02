import XCTest

/// 画面の写真(docs/briefs/screen-snapshots.md)。言語 5 × 画面 8 = 40 枚を、1 枚ごとにアプリを起動し直して撮る。
/// アプリの側は `-ReForgeScreenshot <画面>` で、公開の層の束・固定の種の新しい世界・解放は全部開く・時計は止める(DEBUG のみ)。
/// 撮るだけでは止めず、次の検査に当たれば失敗にする(PNG は失敗しても残す)。
///  1. 画面の外に出る(横。下に伸びるスクロールの中身は縦に出て当然なので、縦は見ない)
///  2. 切れる(アプリが測った overflow。Theme の inkFitCheck)
///  3. 重なり(下のタブの帯・上の状態の帯と、パネルの見出し)
/// 結果は添付 `report_<言語>_<画面>`(JSON)にも残す。CI が xcresult から PNG と report.json に出す。
@MainActor
final class ScreenSnapshotTests: XCTestCase {
    /// 言語の識別子と、組にする地域(-AppleLanguages / -AppleLocale)。
    private static let languages: [(code: String, locale: String)] = [
        ("ja", "ja_JP"), ("en", "en_US"), ("zh-Hans", "zh_CN"), ("zh-Hant", "zh_TW"), ("ko", "ko_KR"),
    ]
    private static let screens = ["map", "foot", "design", "base", "crew", "research", "gameOver", "settings"]

    /// 検査から外す要素(識別子 → 理由)。その要素と中身は「画面の外に出る」を見ない。ここ 1 か所に持つ。
    private static let offscreenExclusions: [String: String] = [
        "map": "地図は 1 マス 1 文字を固定の枠に描く。視点の外のマスは画面の外にあって当然",
        "statusBand": "状態の帯の数値は横に流れる(ScrollView(.horizontal))。見切れは仕様で、切れの検査はアプリの側が見る",
    ]

    /// 重なりを見る帯の識別子(下のタブ・上の状態)と、見出しの識別子(Theme の inkFitCheck の id)。
    private static let headingIDs: Set<String> = ["InkPanel.title", "InkCard.title", "InkPlate.title"]

    private struct Finding: Codable {
        let language: String
        let screen: String
        let id: String
        let kind: String   // "offscreen" / "overflow" / "overlap"
        let detail: String // 大きさ・文字の長さだけ(文字そのものは入れない)
    }

    private struct Report: Codable {
        let language: String
        let screen: String
        let findings: [Finding]
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testJa() throws { shootAll(Self.languages[0]) }
    func testEn() throws { shootAll(Self.languages[1]) }
    func testZhHans() throws { shootAll(Self.languages[2]) }
    func testZhHant() throws { shootAll(Self.languages[3]) }
    func testKo() throws { shootAll(Self.languages[4]) }

    private func shootAll(_ lang: (code: String, locale: String)) {
        for screen in Self.screens {
            XCTContext.runActivity(named: "\(lang.code)_\(screen)") { _ in
                shoot(lang: lang, screen: screen)
            }
        }
    }

    private func shoot(lang: (code: String, locale: String), screen: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-ReForgeScreenshot", screen, "-AppleLanguages", "(\(lang.code))", "-AppleLocale", lang.locale]
        app.launch()
        defer { app.terminate() }

        // 二重の守り(説明書 §2): 公開の層だけでないなら撮らずに失敗する。artifact は誰でも見られる。
        let guardElement = element(app, "screenshotGuard")
        guard guardElement.waitForExistence(timeout: 60) else {
            XCTFail("\(lang.code)_\(screen): screenshotGuard が出ない(撮る起動になっていない)")
            return
        }
        guard (guardElement.value as? String) == "ok" else {
            XCTFail("\(lang.code)_\(screen): 公開の層だけではない(\(guardElement.value as? String ?? "?"))。撮らない")
            return
        }

        prepare(app, screen: screen)
        Thread.sleep(forTimeInterval: 1.0)  // 組み直しと文字の測りが落ち着くのを待つ

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "\(lang.code)_\(screen)"
        shot.lifetime = .keepAlways
        add(shot)

        let findings = inspect(app, lang: lang.code, screen: screen)
        if let data = try? JSONEncoder().encode(Report(language: lang.code, screen: screen, findings: findings)) {
            let a = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            a.name = "report_\(lang.code)_\(screen)"
            a.lifetime = .keepAlways
            add(a)
        }
        for f in findings {
            XCTFail("\(f.language)_\(f.screen): \(f.kind) \(f.id) \(f.detail)")
        }
    }

    // MARK: - 画面を開く

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// アプリが開いた画面が出そろうのを待つ。研究は拠点のタブの研究の節までスクロールする。
    private func prepare(_ app: XCUIApplication, screen: String) {
        switch screen {
        case "map", "foot":
            _ = element(app, "footCard").waitForExistence(timeout: 30)
        case "design", "base", "crew":
            _ = element(app, "InkPanel.title").waitForExistence(timeout: 30)
        case "research":
            _ = element(app, "InkPanel.title").waitForExistence(timeout: 30)
            let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'research'")).firstMatch
            var swipes = 0
            while !(rows.exists && rows.isHittable) && swipes < 12 {
                app.swipeUp()
                swipes += 1
            }
        case "gameOver":
            _ = element(app, "recovery-restart").waitForExistence(timeout: 30)
        case "settings":
            _ = element(app, "cardClose").waitForExistence(timeout: 30)
        default:
            XCTFail("知らない画面: \(screen)")
        }
    }

    // MARK: - 検査

    private func inspect(_ app: XCUIApplication, lang: String, screen: String) -> [Finding] {
        var findings: [Finding] = []
        func add(_ id: String, _ kind: String, _ detail: String) {
            findings.append(Finding(language: lang, screen: screen, id: id, kind: kind, detail: detail))
        }

        let window = app.windows.firstMatch.frame
        guard !window.isEmpty, let root = try? app.snapshot() else {
            add("snapshot", "offscreen", "画面の寸法か要素の木を取れなかった")
            return findings
        }

        // 木を 1 回なめて、はみ出し・切れ・各帯の frame を集める
        var overflowIDs = Set<String>()
        var bands: [String: CGRect] = [:]   // "status" / "tabs" の frame(中身の和)
        var headings: [(id: String, frame: CGRect)] = []

        func visit(_ node: XCUIElementSnapshot, excluded: Bool) {
            let id = node.identifier
            let skip = excluded || Self.offscreenExclusions[id] != nil
            let f = node.frame
            let visible = !f.isEmpty && f.width > 1 && f.height > 1 && f.intersects(window)

            if (node.value as? String) == "overflow" {
                overflowIDs.insert(id)
                add(id, "overflow", "大きさ \(Int(f.width))x\(Int(f.height))")
            }
            if id == "statusBand", !f.isEmpty { bands["status"] = (bands["status"] ?? f).union(f) }
            if id.hasPrefix("tab-"), !f.isEmpty { bands["tabs"] = (bands["tabs"] ?? f).union(f) }
            if Self.headingIDs.contains(id), visible { headings.append((id, f)) }

            // 1. 画面の外に出る(横だけ。1pt の丸めは許す)
            if !skip, visible, node.elementType != .window, node.elementType != .application,
               f.minX < window.minX - 1 || f.maxX > window.maxX + 1 {
                add(id.isEmpty ? "(識別子なし \(node.elementType.rawValue))" : id, "offscreen",
                    "frame x \(Int(f.minX))...\(Int(f.maxX)) 画面 \(Int(window.minX))...\(Int(window.maxX)) 文字の長さ \(node.label.count)")
            }
            for c in node.children { visit(c, excluded: skip) }
        }
        visit(root, excluded: false)

        // 2. 切れる: アプリの印(inkFitReport)にもあるものを足す(木に出なかった要素の取りこぼし防止)
        if let report = element(app, "inkFitReport").value as? String, !report.isEmpty {
            for entry in report.split(separator: ";") {
                let id = String(entry.split(separator: " ").first ?? "")
                if !overflowIDs.contains(id) { add(id, "overflow", String(entry.dropFirst(id.count))) }
            }
        }

        // 3. 重なり: 見出しが、上の状態の帯・下のタブの帯と重ならない(接するのは許す)
        for h in headings {
            for (name, band) in bands where h.frame.insetBy(dx: 0, dy: 1).intersects(band.insetBy(dx: 0, dy: 1)) {
                add(h.id, "overlap", "\(name) の帯と重なる 見出し y \(Int(h.frame.minY))...\(Int(h.frame.maxY)) 帯 y \(Int(band.minY))...\(Int(band.maxY))")
            }
        }
        return findings
    }
}
