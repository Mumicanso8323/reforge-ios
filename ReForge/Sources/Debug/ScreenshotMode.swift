#if DEBUG
import SwiftUI
import UIKit
import ReForgeEngine

/// 画面の写真(CI のシミュレータで主な画面を言語ごとに撮る。docs/briefs/screen-snapshots.md)。
/// 起動引数 `-ReForgeScreenshot <画面>` のときだけ働く。公開の層の束で、固定の種の新しい世界を作り、
/// 画面の要素の解放を全部開き(撮るためだけの上書き。保存しない・世界の状態を変えない)、時計を止めて、指定の画面を開く。
/// 画面: 主な画面 8 つと、タイトル・ノート・決断の帯・読み込みの失敗(説明書 §8)。
/// 序(prologue)は、公開の層に序の場面が無いので、Debug/PrologueSample.swift の中立の見本(3 行 × 2 場面)を画面全体の場面で出す(PT-B6)。
/// 言語は `-AppleLanguages (xx)` と `-AppleLocale xx` で与える(端末側。アプリの言語は `-ReForgeLanguage` で与える。L-12)。
enum ScreenshotScreen: String, CaseIterable {
    case map, foot, design, base, crew, research, gameOver, settings
    case title, notes, decisionBand, bootFailure, prologue, stage, darkStart, darkMark
    /// 日没の締め(夜の帯の上の 3 行。長い名前の並び)。はみ出しの測り用(LayoutFitTests)。
    case dayWrap
    /// 日没の世界で、足元カードを点いた焚き火に向けた形(焚き火の見込みの行。LayoutFitTests)。
    case fireCard

    /// 最初に選ぶタブ。研究は拠点のタブ(研究の節までの巻き取りはアプリの側。BaseTab の DEBUG)。
    var tab: GameTab {
        switch self {
        case .map: .map
        case .foot: .map
        case .design: .design
        case .base: .base
        case .crew: .crew
        case .research: .base
        case .gameOver: .map
        case .settings: .map
        case .title: .map
        case .notes: .notes
        case .decisionBand: .map
        case .bootFailure: .map
        case .prologue: .map
        case .stage: .map
        case .darkStart: .map
        case .darkMark: .map
        case .dayWrap: .map
        case .fireCard: .map
        }
    }
}

/// 時刻の色の写真の 4 点(`-ReForgeScreenshotTime`。`-ReForgeScreenshot map` のときだけ)。
enum ScreenshotTime: String, CaseIterable {
    case dawn, noon, evening, night

    /// 夜明けからの分。夜は夜の作業の段(`darkMark` の世界と同じ、燃える焚き火とその外の柵)。
    var minutesSinceDawn: Int {
        switch self {
        case .dawn: 20
        case .noon: 240
        case .evening: 420
        case .night: 780
        }
    }
}

/// `-ReForgeScreenshotArt present|missing`(W-09): `stage` と `decisionBand` の画面にだけ効く。引数が無ければ何も変えない。
/// present は試験の中で作る単色の PNG(縦長 110×250・横長 200×120)を絵の提供元に入れ、missing は ID だけ付けて提供元を空にする。
enum ScreenshotArt: String {
    case present, missing

    static let tall: ArtID = "t01"
    static let wide: ArtID = "t02"

    static let current: ScreenshotArt? = {
        guard ScreenshotMode.screen == .stage || ScreenshotMode.screen == .decisionBand else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ReForgeScreenshotArt"), args.indices.contains(i + 1) else { return nil }
        return ScreenshotArt(rawValue: args[i + 1])
    }()

    /// 単色の PNG(絵のファイルは持たない。試験とこの見本が使う)。
    static func solidPNG(width: Int, height: Int, white: CGFloat = 0.6) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.pngData { ctx in
            UIColor(white: white, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 提供元を差し替える(missing は空)。
    @MainActor
    func install() {
        switch self {
        case .present:
            ArtProvider.install(ArtProvider(files: [Self.tall: Self.solidPNG(width: 110, height: 250),
                                                    Self.wide: Self.solidPNG(width: 200, height: 120)]))
            Self.logFirstDraw()
        case .missing:
            ArtProvider.install(ArtProvider(files: [:]))
        }
    }

    /// 3.4 の測り: 絵の最初の復号と描画に何 ms かかったか(画面の最初の描画の代わりの見積り。DEBUG のログ 1 行)。
    @MainActor
    private static func logFirstDraw() {
        let start = Date()
        guard let img = ArtProvider.shared.image(tall) else { return }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844))
        _ = renderer.image { _ in img.draw(in: CGRect(x: 0, y: 0, width: 390, height: 844)) }
        NSLog("[ReForge perf] art first draw %.1f ms", Date().timeIntervalSince(start) * 1000)
    }
}

enum ScreenshotMode {
    /// `-ReForgeOfferPseudo YES`: 擬似言語を設定の言語の節に出す(L-10b。表を持たない言語の確かめと節の UI テスト用)。無ければ false。
    static let offersPseudo: Bool = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ReForgeOfferPseudo"), args.indices.contains(i + 1) else { return false }
        return args[i + 1].uppercased() == "YES"
    }()

    /// `-ReForgeLanguage <言語の識別子>`: その実行だけ言語の選びを固定する(保存しない。offered に無い言語でも固定する。L-12・L-13 が使う)。
    static let pinnedLanguage: LanguageID? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ReForgeLanguage"), args.indices.contains(i + 1) else { return nil }
        return LanguageID(rawValue: args[i + 1])
    }()

    /// 時刻の指定(地図の写真だけ。無ければ nil)。
    static let time: ScreenshotTime? = {
        guard screen == .map else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ReForgeScreenshotTime"), args.indices.contains(i + 1) else { return nil }
        return ScreenshotTime(rawValue: args[i + 1])
    }()

    /// 撮る起動の画面(起動引数が無ければ nil)。
    static let screen: ScreenshotScreen? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ReForgeScreenshot"), args.indices.contains(i + 1) else { return nil }
        return ScreenshotScreen(rawValue: args[i + 1])
    }()

    static var isActive: Bool { screen != nil }
    static var firstTab: GameTab { screen?.tab ?? .map }

    /// 撮る起動なら、保存を読み書きしない置き場(使い捨ての場所)で、新しい世界を開いた AppModel を返す。
    @MainActor
    static func makeModel() -> AppModel {
        guard let screen else { return AppModel() }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reforge-screenshot-\(UUID().uuidString)", isDirectory: true)
        let saves = FileSaveStorage(directory: dir)
        GameStore.forceAllUIOpen = true
        GameStore.freezeClock = true
        ScreenshotArt.current?.install()
        switch screen {
        case .bootFailure:
            // 束を読まずに失敗の画面を出す(中身の無い束を渡す)。書体は本物の束から入れておく(失敗の画面も本物の書体で出る)
            FontBook.register()
            let empty = dir.appendingPathComponent("empty-bundle", isDirectory: true)
            try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            return AppModel(saves: saves, bundle: Bundle(url: empty) ?? Bundle())
        case .title:
            return AppModel(saves: saves)
        case .map, .foot, .design, .base, .crew, .research, .gameOver, .settings, .notes, .decisionBand, .prologue, .stage, .darkStart, .darkMark, .dayWrap, .fireCard:
            let model = AppModel(saves: saves)
            model.startScreenshotGame(failed: screen == .gameOver, decision: screen == .decisionBand,
                                      darkStart: screen == .darkStart, darkMark: screen == .darkMark,
                                      foot: screen == .foot, dusk: screen == .dayWrap || screen == .fireCard,
                                      focusFire: screen == .fireCard, time: time)
            // 設定は、角のボタンで開いた形で撮る(札は RootView。L-10a)
            if screen == .settings { model.settingsOpen = true }
            // 序は、見本の場面を画面全体で出した形(送りは UI テストのタップ)
            if screen == .prologue { model.debugPrologue = DebugPrologue() }
            if screen == .stage { model.debugPrologue = DebugPrologue(kind: .stage, art: ScreenshotArt.current == nil ? nil : ScreenshotArt.tall) }
            return model
        }
    }

    /// 公開の層だけであること(鍵が無く、束に封をした非公開の層も絵も無く、読んだ層が公開だけ)。
    /// artifact は誰でも見られるので、UI テストが撮る前にこれを assert する(説明書 §2)。
    @MainActor
    static func guardValue(_ app: AppModel) -> String {
        guard ContentKey.key == nil else { return "key-present" }
        guard let root = Bundle.main.url(forResource: "content", withExtension: nil) else { return "no-content" }
        let fm = FileManager.default
        for name in ["private.sealed", "art.sealed", "private"] where fm.fileExists(atPath: root.appendingPathComponent(name).path) {
            return "private-present"
        }
        // 束を読まない画面(読み込みの失敗)は content が nil。読んだなら層は公開だけ
        if let layers = app.content?.layers, !layers.allSatisfy({ $0.id == "public" }) { return "layer-present" }
        return "ok"
    }
}

extension View {
    /// 撮る起動のときだけ、UI テストが読む目に見えない印(公開の層の確かめ・はみ出しの一覧)を重ねる。
    func screenshotSupport(app: AppModel) -> some View {
        overlay(alignment: .topLeading) {
            if ScreenshotMode.isActive { ScreenshotProbes(app: app) }
        }
    }
}

/// 1pt の目に見えない要素 2 つ。UI テストは識別子で引いて accessibilityValue を読む。
private struct ScreenshotProbes: View {
    let app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            marker("screenshotGuard", ScreenshotMode.guardValue(app))
            marker("inkFitReport", InkFitLog.shared.report)
            if ScreenshotMode.screen == .darkMark {
                marker("darkMarkSample", app.game?.placements.contains(where: \.seenInDark) == true ? "1" : "0")
            }
        }
        .frame(width: 2, height: 2)
        .allowsHitTesting(false)
    }

    private func marker(_ id: String, _ value: String) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(id)
            .accessibilityValue(Text(verbatim: value))
    }
}
#endif
