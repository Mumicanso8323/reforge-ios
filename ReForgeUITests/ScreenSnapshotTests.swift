import XCTest

/// 画面の写真(docs/briefs/screen-snapshots.md)。言語 5 × 画面 14 = 70 枚を、1 枚ごとにアプリを起動し直して撮る。
/// アプリの側は `-ReForgeScreenshot <画面>` で、公開の層の束・固定の種の新しい世界・解放は全部開く・時計は止める(DEBUG のみ)。
/// 撮るだけでは止めず、次の検査に当たれば失敗にする(PNG は失敗しても残す)。
///  1. 画面の外に出る(横。下に伸びるスクロールの中身は縦に出て当然なので、縦は見ない)
///  2. 切れる(アプリが測った overflow。Theme の inkFitCheck)
///  3. 重なり(下のタブの帯・上の状態の帯と、パネルの見出し)
///  4. TEST-L16: 設定のボタン(settingsButton)が、ある・押せる・右上の 52×52pt にある・ほかの要素と重ならない。
///     ボタンは L-10a で入った。無ければ失敗にする(画面ごとに「ある」を見る)。
/// 結果は添付 `report_<言語>_<画面>`(JSON)にも残す。CI が xcresult から PNG と report.json に出す。
@MainActor
final class ScreenSnapshotTests: XCTestCase {
    /// 言語の識別子と、組にする地域(-AppleLanguages / -AppleLocale)。
    private static let languages: [(code: String, locale: String)] = [
        ("ja", "ja_JP"), ("en", "en_US"), ("zh-Hans", "zh_CN"), ("zh-Hant", "zh_TW"), ("ko", "ko_KR"),
    ]
    /// 主な画面 8 つと、タイトル・ノート・決断の帯・読み込みの失敗(説明書 §8)。
    /// 序(prologue)は、公開の層の中立の見本(Debug/PrologueSample.swift)を画面全体の場面で撮る(PT-B6)。
    /// 暗い場面(darkStart)は、最初の行為の前の画面(PT-B8)。
    private static let screens = ["map", "foot", "design", "base", "crew", "research", "gameOver", "settings",
                                  "title", "notes", "decisionBand", "bootFailure", "prologue", "stage", "darkStart"]
    /// 序の地の色(InkColor.prologueGround #07080C)と、端の色の許す差(0...255 の各チャンネル)。
    private static let prologueGround: (r: Int, g: Int, b: Int) = (7, 8, 12)
    private static let prologueTolerance = 6
    /// アプリの一番上の透明の窓に置かれる設定のボタン(L-10)。右上のこの大きさの角に来る(TEST-L16)。
    private static let cornerSize: CGFloat = 52

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
        /// 幅か高さが 1pt 以下で文字の長さ 0 の要素を offscreen から外した数(増えたら気づくため)
        let ignoredZeroSize: Int
        /// 研究の写真だけ: "ok" / "empty"(研究の節が出ない)。ほかの画面は nil
        let research: String?
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
        if screen == "darkStart" { assertDarkStart(app, language: lang.code) }
        Thread.sleep(forTimeInterval: 1.0)
        if screen == "map" { mapFrames[lang.code] = element(app, "map").frame }
        if screen == "decisionBand" { assertDecisionBand(app, language: lang.code) }  // 組み直しと文字の測りが落ち着くのを待つ(研究の巻き取りの成否は下のポーリングで決める)
        let researchStatus = screen == "research" ? waitForResearchSection(app, language: lang.code, screen: screen) : nil

        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "\(lang.code)_\(screen)"
        shot.lifetime = .keepAlways
        add(shot)

        let inspected = inspect(app, lang: lang.code, screen: screen)
        var findings = inspected.findings
        if screen == "prologue" || screen == "stage" {
            findings += prologueFindings(app, lang: lang.code, screen: screen, screenshot: screenshot)
        }
        // 設定を開いた状態(settings)では、同じ所のボタンで閉じられる(TEST-L16)
        if screen == "settings" {
            let button = element(app, "settingsButton")
            if button.exists, button.isHittable {
                button.tap()
                let closed = NSPredicate(format: "exists == false")
                let wait = XCTNSPredicateExpectation(predicate: closed, object: element(app, "cardClose"))
                if XCTWaiter().wait(for: [wait], timeout: 5) != .completed {
                    findings.append(Finding(language: lang.code, screen: screen, id: "settingsButton", kind: "settings",
                                            detail: "開いた設定が同じボタンで閉じない"))
                }
            }
        }
        let ignoredZeroSize = inspected.ignoredZeroSize
        let research = researchStatus?.state
        if let researchStatus {
            if let finding = researchStatus.finding {
                findings.append(finding)
            }
            if researchStatus.state == "empty" {
                findings.append(Finding(language: lang.code, screen: screen, id: "researchSection", kind: "research",
                                        detail: "research: empty(研究の節が出ない。空の写真は緑にしない)"))
            }
        }
        if let data = try? JSONEncoder().encode(Report(language: lang.code, screen: screen, findings: findings,
                                                       ignoredZeroSize: ignoredZeroSize, research: research)) {
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

    /// アプリが開いた画面が出そろうのを待つ。研究の節への巻き取りはアプリの側(BaseTab の DEBUG。S-02)。
    private func prepare(_ app: XCUIApplication, screen: String) {
        switch screen {
        case "map", "foot":
            _ = element(app, "footCard").waitForExistence(timeout: 30)
        case "design", "base", "crew":
            _ = element(app, "InkPanel.title").waitForExistence(timeout: 30)
        case "research":
            _ = element(app, "InkPanel.title").waitForExistence(timeout: 30)
        case "gameOver":
            _ = element(app, "recovery-restart").waitForExistence(timeout: 30)
        case "settings":
            _ = element(app, "cardClose").waitForExistence(timeout: 30)
        case "title":
            _ = element(app, "newGameButton").waitForExistence(timeout: 30)
        case "notes":
            _ = element(app, "InkPanel.title").waitForExistence(timeout: 30)
        case "decisionBand":
            _ = element(app, "statusBand").waitForExistence(timeout: 30)
        case "bootFailure":
            _ = element(app, "contentError").waitForExistence(timeout: 30)
        case "prologue", "stage":
            _ = element(app, "prologueScene").waitForExistence(timeout: 30)
        case "darkStart":
            _ = element(app, "darkStartAct").waitForExistence(timeout: 30)
        default:
            XCTFail("知らない画面: \(screen)")
        }
    }

    /// 帯のない写真(map)での地図の枠(言語ごと)。決断の帯の写真と同じでなければならない(帯は重ねる。A-02)。
    private var mapFrames: [String: CGRect] = [:]

    /// A-02 決断の帯: 問いの文が見える・選ぶボタンが画面の下 1/3 にある・地図の枠が帯のない写真と同じ。
    private func assertDecisionBand(_ app: XCUIApplication, language: String) {
        let prompt = element(app, "decisionPrompt")
        XCTAssertTrue(prompt.exists, "\(language)_decisionBand: 問いの文が出ない")
        let band = element(app, "decisionBand")
        XCTAssertTrue(band.exists, "\(language)_decisionBand: 帯が出ない")
        let window = app.windows.firstMatch.frame
        let buttons = band.buttons.allElementsBoundByIndex
        XCTAssertFalse(buttons.isEmpty, "\(language)_decisionBand: 選ぶボタンが無い")
        for b in buttons {
            XCTAssertGreaterThan(b.frame.midY, window.height * 2 / 3, "\(language)_decisionBand: 選ぶボタンが下 1/3 にない")
            XCTAssertGreaterThanOrEqual(b.frame.height, 44, "\(language)_decisionBand: 選ぶボタンが小さい")
        }
        if prompt.exists, let first = buttons.first {
            XCTAssertLessThanOrEqual(prompt.frame.maxY, first.frame.minY + 1, "\(language)_decisionBand: 問いの文がボタンの上にない")
        }
        let map = element(app, "map").frame
        if let plain = mapFrames[language] {
            XCTAssertEqual(map.minX, plain.minX, accuracy: 1, "\(language)_decisionBand: 地図の枠が動いた")
            XCTAssertEqual(map.minY, plain.minY, accuracy: 1, "\(language)_decisionBand: 地図の枠が動いた")
            XCTAssertEqual(map.width, plain.width, accuracy: 1, "\(language)_decisionBand: 地図の枠が動いた")
            XCTAssertEqual(map.height, plain.height, accuracy: 1, "\(language)_decisionBand: 地図の枠が動いた")
        } else {
            XCTFail("\(language)_decisionBand: 帯のない地図の枠が測れていない")
        }
    }

    private func assertDarkStart(_ app: XCUIApplication, language: String) {
        // 暗い場面で押せる物は行為の 1 つだけ(DEC-F9。角の設定のボタンも隠れる)
        for id in ["map", "statusBand", "footCard", "tab-map", "tab-design", "tab-notes", "tab-base", "tab-crew", "settingsButton"] {
            XCTAssertFalse(element(app, id).exists, "\(language)_darkStart: \(id) が出ている")
        }
        let action = element(app, "darkStartAct")
        XCTAssertTrue(action.exists, "\(language)_darkStart: 行為が出ない")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(action.frame.height, 44, "\(language)_darkStart: 行為が小さい")
        XCTAssertGreaterThanOrEqual(action.frame.midY, window.midY, "\(language)_darkStart: 行為が下半分にない")
    }

    /// 研究の最初の行が上半分に来るまで待つ。写真はこの判定の後に撮る。
    private func waitForResearchSection(_ app: XCUIApplication, language: String, screen: String) -> (state: String, finding: Finding?) {
        let deadline = Date().addingTimeInterval(5)
        var found = false
        var lastFrame = CGRect.zero

        while Date() < deadline {
            let rows = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'research-'"))
            let firstRow = rows.firstMatch
            let section = firstRow.exists ? firstRow : element(app, "researchHidden")
            if section.exists {
                found = true
                let frame = section.frame
                lastFrame = frame
                let window = app.windows.firstMatch.frame
                if !window.isEmpty,
                   frame.minY < window.minY + window.height / 2,
                   frame.intersects(window),
                   section.isHittable {
                    return ("ok", nil)
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        guard found else { return ("empty", nil) }
        let detail = "research: notScrolled frame \(Int(lastFrame.minX)),\(Int(lastFrame.minY)),\(Int(lastFrame.width)),\(Int(lastFrame.height))"
        return ("notScrolled", Finding(language: language, screen: screen, id: "researchSection", kind: "research", detail: detail))
    }

    // MARK: - 検査

    private func inspect(_ app: XCUIApplication, lang: String, screen: String) -> (findings: [Finding], ignoredZeroSize: Int) {
        var findings: [Finding] = []
        var ignoredZeroSize = 0
        func add(_ id: String, _ kind: String, _ detail: String) {
            findings.append(Finding(language: lang, screen: screen, id: id, kind: kind, detail: detail))
        }

        let window = app.windows.firstMatch.frame
        guard !window.isEmpty, let root = try? app.snapshot() else {
            add("snapshot", "offscreen", "画面の寸法か要素の木を取れなかった")
            return (findings, ignoredZeroSize)
        }

        // 木を 1 回なめて、はみ出し・切れ・各帯の frame を集める
        var overflowIDs = Set<String>()
        var bands: [String: CGRect] = [:]   // "status" / "tabs" の frame(中身の和)
        var headings: [(id: String, frame: CGRect)] = []
        var settingsFrame: CGRect?
        // 右上の角に入りうる葉(入れ物・設定のボタンの中身・印の要素は除く)
        var leaves: [(id: String, frame: CGRect, length: Int)] = []

        // clip: 先祖のスクロールの見えている範囲(巻き取られて帯の下に隠れた行は、木に残っても画面に無い)
        func visit(_ node: XCUIElementSnapshot, excluded: Bool, insideSettings: Bool = false, clip: CGRect? = nil) {
            let id = node.identifier
            var clip = clip
            if [.scrollView, .table, .collectionView].contains(node.elementType), !node.frame.isEmpty { clip = clip.map { $0.intersection(node.frame) } ?? node.frame }
            let isSettings = id == "settingsButton"
            if isSettings, !node.frame.isEmpty { settingsFrame = node.frame }
            let probe = id == "screenshotGuard" || id == "inkFitReport" || id.hasPrefix("Ink")  // アプリの印(inkFitCheck の面)
            let containerTypes: Set<XCUIElement.ElementType> = [.other, .scrollView, .table, .collectionView, .group, .layoutArea, .layoutItem]
            let isContainer = containerTypes.contains(node.elementType)
                || node.frame.width * node.frame.height > window.width * window.height / 4
            if node.children.isEmpty, !insideSettings, !isSettings, !probe, !isContainer, node.elementType != .window,
               node.elementType != .application, node.frame.width > 1, node.frame.height > 1 {
                let shown = clip.map { node.frame.intersection($0) } ?? node.frame
                if !shown.isNull, shown.width > 1, shown.height > 1 { leaves.append((id, shown, node.label.count)) }
            }
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

            // 1. 画面の外に出る(横だけ。1pt の丸めは許す)。幅か高さが 1pt 以下で文字の長さ 0 の要素は数えて外す(子は見る)
            let zeroSize = (f.width <= 1 || f.height <= 1) && node.label.count == 0
            if zeroSize, !skip, node.elementType != .window, node.elementType != .application,
               !f.isEmpty ? (f.minX < window.minX - 1 || f.maxX > window.maxX + 1) : true {
                ignoredZeroSize += 1
            }
            if !skip, visible, !zeroSize, node.elementType != .window, node.elementType != .application,
               f.minX < window.minX - 1 || f.maxX > window.maxX + 1 {
                add(id.isEmpty ? "(識別子なし \(node.elementType.rawValue))" : id, "offscreen",
                    "frame x \(Int(f.minX))...\(Int(f.maxX)) 画面 \(Int(window.minX))...\(Int(window.maxX)) 文字の長さ \(node.label.count)")
            }
            for c in node.children { visit(c, excluded: skip, insideSettings: insideSettings || isSettings, clip: clip) }
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

        // 序は画面全体の場面。設定のボタンは窓ごと隠れている(PT-B6)ので、TEST-L16 の代わりに「無い」ことを見る(prologueFindings)
        // 暗い場面(PT-B8・DEC-F9)も、設定のボタンは窓ごと隠れている(assertDarkStart で「無い」ことを見る)
        if screen == "prologue" || screen == "stage" || screen == "darkStart" { return (findings, ignoredZeroSize) }

        // 4. TEST-L16: 設定のボタン。1. ある 2. 押せる 3. 右上の 52x52pt(安全な領域の内側)にある 4. ほかの要素と重ならない。
        if settingsFrame == nil { add("settingsButton", "settings", "無い") }
        if let sf = settingsFrame {
            // 角の上端は安全な領域の上端(ボタンの上の余白 4pt を引いて割り出す)。ノッチ・島の下に入る
            let topInset = sf.minY - (Self.cornerSize - 44) / 2
            if topInset < window.minY - 1 || topInset > window.minY + 90 {
                add("settingsButton", "settings", "上端の位置がおかしい frame y \(Int(sf.minY))")
            }
            if abs(sf.width - 44) > 1 || abs(sf.height - 44) > 1 {
                add("settingsButton", "settings", "押せる範囲が 44x44 でない \(Int(sf.width))x\(Int(sf.height))")
            }
            let corner = CGRect(x: window.maxX - Self.cornerSize, y: topInset, width: Self.cornerSize, height: Self.cornerSize)
            if !element(app, "settingsButton").isHittable { add("settingsButton", "settings", "押せない") }
            if sf.minX < corner.minX - 1 || sf.maxX > corner.maxX + 1 || sf.minY < corner.minY - 1 || sf.maxY > corner.maxY + 1 {
                add("settingsButton", "settings", "右上の \(Int(Self.cornerSize))x\(Int(Self.cornerSize)) の外 frame \(Int(sf.minX)),\(Int(sf.minY)) \(Int(sf.width))x\(Int(sf.height))")
            }
            for l in leaves where l.frame.intersection(corner).width > 1 && l.frame.intersection(corner).height > 1 {
                add(l.id.isEmpty ? "(識別子なし)" : l.id, "settings", "右上の角に入っている frame \(Int(l.frame.minX)),\(Int(l.frame.minY)) \(Int(l.frame.width))x\(Int(l.frame.height)) 文字の長さ \(l.length)")
            }
        }
        return (findings, ignoredZeroSize)
    }

    // MARK: - 序(PT-B6)

    /// 序の写真の検査: 序の間は、地図・帯・タブ・角のボタンの識別子が画面に無い。端(安全域の外を含む)が序の地の色で覆われている。
    private func prologueFindings(_ app: XCUIApplication, lang: String, screen: String, screenshot: XCUIScreenshot) -> [Finding] {
        var out: [Finding] = []
        func add(_ id: String, _ detail: String) {
            out.append(Finding(language: lang, screen: screen, id: id, kind: screen, detail: detail))
        }
        for id in ["settingsButton", "statusBand", "footCard", "map"] where element(app, id).exists {
            add(id, "序の間に画面にある")
        }
        if app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'")).firstMatch.exists {
            add("tab-*", "序の間にタブが画面にある")
        }
        guard let cg = screenshot.image.cgImage else {
            add("edge", "写真の画素を読めない")
            return out
        }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else {
            add("edge", "写真の画素を読めない")
            return out
        }
        // 四隅・各辺の中ほど(端から 2 画素内側)。上の中ほどはノッチ・島の下、下の中ほどはホームの線のまわり。
        let points: [(String, Int, Int)] = [
            ("topLeft", 2, 2), ("topCenter", w / 2, 2), ("topRight", w - 3, 2),
            ("left", 2, h / 2), ("right", w - 3, h / 2),
            ("bottomLeft", 2, h - 3), ("bottomCenter", w / 2, h - 3), ("bottomRight", w - 3, h - 3),
        ]
        for (name, x, y) in points {
            let i = (y * w + x) * 4
            let (r, g, b) = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
            let t = Self.prologueGround
            if abs(r - t.r) > Self.prologueTolerance || abs(g - t.g) > Self.prologueTolerance || abs(b - t.b) > Self.prologueTolerance {
                add("edge.\(name)", "端の色が序の地の色でない rgb \(r),\(g),\(b)")
            }
        }
        return out
    }
}
