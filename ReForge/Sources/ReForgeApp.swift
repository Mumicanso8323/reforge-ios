import SwiftUI
import ReForgeEngine

@main
struct ReForgeApp: App {
    @State private var app: AppModel

    init() {
#if DEBUG
        // 撮る起動(-ReForgeScreenshot)なら、公開の層の新しい世界を開いた状態で始める(Debug/ScreenshotMode.swift)
        _app = State(initialValue: ScreenshotMode.makeModel())
#else
        _app = State(initialValue: AppModel())
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .preferredColorScheme(.dark)
#if DEBUG
                .screenshotSupport(app: app)
#endif
        }
    }
}

/// アプリ全体の状態: コンテンツ・保存・購入と、いまのプレイ(GameStore)。
@MainActor
@Observable
final class AppModel {
    /// 同梱のコンテンツ(読めなければ nil。画面は理由を出す)。
    let content: ContentDB?
    let loadError: String?
    /// 封をした非公開の層を開けず、公開の層だけで起動したとき true(画面の帯に 1 行出す。U13)。
    let sealedContentFailed: Bool
    let saves: FileSaveStorage
    let storeService: any StoreService
    let adProvider: any AdProvider
    /// 広告除去の権利(正は StoreService。UserDefaults はキャッシュ)。
    private(set) var adsRemoved: Bool
    private(set) var game: GameStore?
    /// 「つづきから」があるか。
    private(set) var hasResume: Bool
    /// 設定が開いているか(L-10a)。開いている間はゲームの時計を止める。開閉は右上の角のボタンだけが行う。
    /// 本体には何も送らない(ゲームのコマンドではない)。
    var settingsOpen = false {
        didSet { game?.isPaused = settingsOpen }
    }

    static let adsRemovedKey = "adsRemoved"

#if DEBUG
    /// 撮る起動の序(Debug/PrologueSample.swift)。公開の層には序の場面が無いので、見本の場面をここから出す。
    var debugPrologue: DebugPrologue?
#endif

    /// いま画面を覆っている序(無ければ nil)。本体の序、撮る起動なら見本の序。
    var activePrologue: PrologueView? {
#if DEBUG
        if let debugPrologue { return debugPrologue.view }
#endif
        return game?.prologue
    }

    /// 序の送り(タップだけ。時間では送らない)。
    func advancePrologue() {
#if DEBUG
        if let debugPrologue { debugPrologue.advance(); return }
#endif
        game?.send(.narrative(.advanceScene))
    }

    /// 右上の設定の角のボタンを出すか。序の間と、最初の行為の前の暗い場面の間は出さない(窓ごと隠す。PT-B6・DEC-F9:
    /// 「はじめから」から地図が出るまで、押せる物は暗い場面のボタン 1 つだけ)。
    var cornerButtonVisible: Bool { activePrologue == nil && game?.darkStart == nil }

    init(saves: FileSaveStorage = FileSaveStorage(),
         storeService: any StoreService = UnavailableStoreService(),
         adProvider: any AdProvider = NoopAdProvider(),
         bundle: Bundle = .main) {
        FontBook.register(bundle: bundle)
        var content: ContentDB?
        var loadError: String?
        var sealedFailed = false
        do {
            let r = try AppModel.loadBundledContentFallingBack(bundle: bundle)
            content = r.content
            sealedFailed = r.sealedFailed
        } catch {
            loadError = String(describing: error)
        }
        self.content = content
        self.loadError = loadError
        self.sealedContentFailed = sealedFailed
        self.saves = saves
        self.storeService = storeService
        self.adProvider = adProvider
        self.adsRemoved = UserDefaults.standard.bool(forKey: Self.adsRemovedKey)
        self.hasResume = (try? saves.read(slot: .resume)) != nil
    }

    /// アプリの束に同梱した `content/`(公開の層と、あれば封をした非公開の層)を読む。鍵は rf-seal が生成した ContentKey。
    static func loadBundledContent(bundle: Bundle) throws -> ContentDB {
        try GameBootstrap.loadContent(contentDirectory: contentDirectory(bundle), key: ContentKey.key)
    }

    /// 封を開けなければ公開の層だけで読む(アプリを落とさない)。
    static func loadBundledContentFallingBack(bundle: Bundle) throws -> (content: ContentDB, sealedFailed: Bool) {
        try GameBootstrap.loadContentFallingBack(contentDirectory: contentDirectory(bundle), key: ContentKey.key)
    }

    private static func contentDirectory(_ bundle: Bundle) throws -> URL {
        guard let dir = bundle.url(forResource: "content", withExtension: nil) else {
            throw ContentLoader.LoadError.missingLayer("content")
        }
        return dir
    }

#if DEBUG
    /// 撮る起動(Debug/ScreenshotMode.swift): 保存を読まず・書かない、固定の種の新しい世界を開く。
    /// failed なら走行が終わった形(ゲームオーバーの 4 択)にする。
    /// decision なら、公開の層の試験用の決断を 1 つ出した形にする(決断の帯)。
    func startScreenshotGame(failed: Bool, decision: Bool, darkStart: Bool = false) {
        guard let content else { return }
        var world = GameBootstrap.newWorld(content: content, seed: 1)
        if failed { world.run.outcome = .failed(cause: "text.screenshot.cause", record: nil) }
        if decision {
            world.narrative.pending = [PendingDecision(id: world.newEntityID(), event: "event.test.decision",
                                                       choices: ["choice.test.yes", "choice.test.no"], blocking: false,
                                                       since: world.clock.now, origin: nil)]
        }
        if darkStart { world.clock.held = true }
        game = GameStore(content: content, world: world, saves: saves)
        game?.isPaused = settingsOpen
    }
#endif

    func startNewGame() {
        guard let content else { return }
        let world = GameBootstrap.newWorld(content: content, seed: UInt64.random(in: .min ... .max))
        GameStore.forgetLastOperation()
        let g = GameStore(content: content, world: world, saves: saves)
        settingsOpen = false
        game = g
        hasResume = true
        Task { await g.saveResume() }
    }

    /// 「つづきから」。読めない保存なら始めない(理由は出さずにタイトルに残る)。
    func continueGame() {
        guard let content, let data = try? saves.read(slot: .resume),
              let env = try? SaveCodec.decode(data) else {
            hasResume = false
            return
        }
        settingsOpen = false
        game = GameStore(content: content, world: env.world, saves: saves)
    }

    func backToTitle() async {
        await game?.saveResume()
        settingsOpen = false
        game = nil
        hasResume = (try? saves.read(slot: .resume)) != nil
    }

    /// 記録を消す(取り返しがつかないので、画面は確認ダイアログを出してから呼ぶ)。
    func deleteSave() {
        settingsOpen = false
        game = nil
        try? saves.deleteAll()
        GameStore.forgetLastOperation()
        hasResume = false
    }

    /// 背面に回る・戻る。閉じている間は進まない(時計を止めて「つづきから」を書く)。
    func scenePhaseChanged(active: Bool) {
        game?.isActive = active
        if !active, let g = game { Task { await g.saveResume() } }
    }

    func refreshEntitlements() async {
        guard storeService.isAvailable else { return }
        setAdsRemoved(await storeService.adsRemovedEntitlement())
    }

    private func setAdsRemoved(_ v: Bool) {
        adsRemoved = v
        UserDefaults.standard.set(v, forKey: Self.adsRemovedKey)
    }

    func purchaseRemoveAds() async {
        if await storeService.purchase(ProductID.removeAds) { setAdsRemoved(true) }
    }

    func restorePurchases() async {
        if await storeService.restore() { setAdsRemoved(true) }
    }
}

/// 全画面の共通の土台。広告枠コンテナの内側に画面を置くので、どの画面でも下の枠は残る。
struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// 序が終わった直後の移り(文字が消え・黒の間・地図が灯る)を演じている間の、最後の行。nil なら移りは無い。
    @State private var dawnLines: [String]?

    var body: some View {
        ZStack {
            mainContent
            // 序は画面全体の場面。安全域の外まで覆い、地図・帯・タブ・角のボタンは序の間は作らない(PT-B6)
            if let prologue = app.activePrologue {
                PrologueScene(lines: prologue.lines, advance: { app.advancePrologue() })
                    .ignoresSafeArea()
            } else if let lines = dawnLines {
                PrologueScene(lines: lines, exiting: true, onExitDone: { dawnLines = nil })
                    .ignoresSafeArea()
            }
        }
        .onChange(of: app.activePrologue) { old, new in
            if let old, new == nil, app.game != nil {
                dawnLines = old.lines
            } else if new != nil {
                dawnLines = nil
            }
        }
        .background(Color.black)
        .background(SettingsCornerInstaller(app: app, visible: app.cornerButtonVisible && dawnLines == nil))
        .task { await app.refreshEntitlements() }
        .onChange(of: scenePhase) { _, phase in
            app.scenePhaseChanged(active: phase == .active)
        }
    }

    private var mainContent: some View {
        AdBannerContainer(adsRemoved: app.adsRemoved) {
            if let message = app.loadError {
                ContentErrorView(message: message)
            } else if let game = app.game {
                GameScreen(app: app, store: game)
            } else {
                TitleView(app: app)
            }
        }
        // 設定は地図の下半分に出す札。ボタンは別の窓(SettingsCorner)にあるので、どの画面・札・シートの上でも見える
        .inkCard(isPresented: $app.settingsOpen, title: Text("設定"), maxHeightRatio: 0.5) {
            SettingsView(app: app, close: { app.settingsOpen = false })
        }
    }
}

/// コンテンツが読めなかったとき(ビルドの不具合。出荷しない)。
struct ContentErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text("データを読み込めませんでした")
                .font(InkFont.heading)
            Text(verbatim: message)
                .font(InkFont.caption)
                .foregroundStyle(InkColor.textDim)
        }
        .foregroundStyle(InkColor.text)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InkColor.ground)
        .accessibilityIdentifier("contentError")
    }
}
