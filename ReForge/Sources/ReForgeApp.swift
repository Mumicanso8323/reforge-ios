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

    static let adsRemovedKey = "adsRemoved"

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
    func startScreenshotGame(failed: Bool, decision: Bool) {
        guard let content else { return }
        var world = GameBootstrap.newWorld(content: content, seed: 1)
        if failed { world.run.outcome = .failed(cause: "text.screenshot.cause", record: nil) }
        if decision {
            world.narrative.pending = [PendingDecision(id: world.newEntityID(), event: "event.test.decision",
                                                       choices: ["choice.test.yes", "choice.test.no"], blocking: false,
                                                       since: world.clock.now, origin: nil)]
        }
        game = GameStore(content: content, world: world, saves: saves)
    }
#endif

    func startNewGame() {
        guard let content else { return }
        let world = GameBootstrap.newWorld(content: content, seed: UInt64.random(in: .min ... .max))
        let g = GameStore(content: content, world: world, saves: saves)
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
        game = GameStore(content: content, world: env.world, saves: saves)
    }

    func backToTitle() async {
        await game?.saveResume()
        game = nil
        hasResume = (try? saves.read(slot: .resume)) != nil
    }

    /// 記録を消す(取り返しがつかないので、画面は確認ダイアログを出してから呼ぶ)。
    func deleteSave() {
        game = nil
        try? saves.deleteAll()
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

/// 全画面の共通の土台。広告枠コンテナの内側に画面を置くので、どの画面でも上下の枠は残る。
struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AdBannerContainer(adsRemoved: app.adsRemoved) {
            if let message = app.loadError {
                ContentErrorView(message: message)
            } else if let game = app.game {
                GameScreen(app: app, store: game)
            } else {
                TitleView(app: app)
            }
        }
        .background(Color.black)
        .task { await app.refreshEntitlements() }
        .onChange(of: scenePhase) { _, phase in
            app.scenePhaseChanged(active: phase == .active)
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
