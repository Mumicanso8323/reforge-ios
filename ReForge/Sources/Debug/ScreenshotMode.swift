#if DEBUG
import SwiftUI
import ReForgeEngine

/// 画面の写真(CI のシミュレータで主な画面を言語ごとに撮る。docs/briefs/screen-snapshots.md)。
/// 起動引数 `-ReForgeScreenshot <画面>` のときだけ働く。公開の層の束で、固定の種の新しい世界を作り、
/// 画面の要素の解放を全部開き(撮るためだけの上書き。保存しない・世界の状態を変えない)、時計を止めて、指定の画面を開く。
/// 画面: 主な画面 8 つと、タイトル・ノート・決断の帯・読み込みの失敗(説明書 §8)。
/// 序(prologue)は、公開の層に序の場面が無いので、Debug/PrologueSample.swift の中立の見本(3 行 × 2 場面)を画面全体の場面で出す(PT-B6)。
/// 言語は `-AppleLanguages (xx)` と `-AppleLocale xx` で与える(InkFont.language の初期値が拾う)。
enum ScreenshotScreen: String, CaseIterable {
    case map, foot, design, base, crew, research, gameOver, settings
    case title, notes, decisionBand, bootFailure, prologue, stage, darkStart, darkMark
    /// 日没の締め(夜の帯の上の 3 行。長い名前の並び)。はみ出しの測り用(LayoutFitTests)。
    case dayWrap

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
        }
    }
}

enum ScreenshotMode {
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
        switch screen {
        case .bootFailure:
            // 束を読まずに失敗の画面を出す(中身の無い束を渡す)。書体は本物の束から入れておく(失敗の画面も本物の書体で出る)
            FontBook.register()
            let empty = dir.appendingPathComponent("empty-bundle", isDirectory: true)
            try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            return AppModel(saves: saves, bundle: Bundle(url: empty) ?? Bundle())
        case .title:
            return AppModel(saves: saves)
        case .map, .foot, .design, .base, .crew, .research, .gameOver, .settings, .notes, .decisionBand, .prologue, .stage, .darkStart, .darkMark, .dayWrap:
            let model = AppModel(saves: saves)
            model.startScreenshotGame(failed: screen == .gameOver, decision: screen == .decisionBand,
                                      darkStart: screen == .darkStart, darkMark: screen == .darkMark,
                                      foot: screen == .foot, dusk: screen == .dayWrap)
            // 設定は、角のボタンで開いた形で撮る(札は RootView。L-10a)
            if screen == .settings { model.settingsOpen = true }
            // 序は、見本の場面を画面全体で出した形(送りは UI テストのタップ)
            if screen == .prologue { model.debugPrologue = DebugPrologue() }
            if screen == .stage { model.debugPrologue = DebugPrologue(kind: .stage) }
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
