import SwiftUI
import ReForgeEngine

@main
struct ReForgeApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .preferredColorScheme(.dark)
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
        do {
            content = try AppModel.loadBundledContent(bundle: bundle)
        } catch {
            loadError = String(describing: error)
        }
        self.content = content
        self.loadError = loadError
        self.saves = saves
        self.storeService = storeService
        self.adProvider = adProvider
        self.adsRemoved = UserDefaults.standard.bool(forKey: Self.adsRemovedKey)
        self.hasResume = (try? saves.read(slot: .resume)) != nil
    }

    /// アプリの束に同梱した `content/`(公開の層と、あれば非公開の層)を読む。
    static func loadBundledContent(bundle: Bundle) throws -> ContentDB {
        guard let dir = bundle.url(forResource: "content", withExtension: nil) else {
            throw ContentLoader.LoadError.missingLayer("content")
        }
        return try GameBootstrap.loadContent(contentDirectory: dir)
    }

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
                .font(.headline)
            Text(verbatim: message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
