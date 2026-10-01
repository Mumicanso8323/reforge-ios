import SwiftUI
import ReForgeCore
import ReForgeContent

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

/// アプリ全体の状態: 規則・保存・購入と、いまのプレイ。
@MainActor
@Observable
final class AppModel {
    let game: Game
    let store: SaveStore
    let storeService: any StoreService
    let adProvider: any AdProvider
    /// 広告除去の権利(正は StoreService。保存ファイルはキャッシュ)。
    var adsRemoved: Bool
    var session: GameSession? = nil
    /// 保存の有無(タイトルの「つづきから」)。
    private(set) var hasSave: Bool

    init(store: SaveStore = SaveStore(),
         storeService: any StoreService = UnavailableStoreService(),
         adProvider: any AdProvider = NoopAdProvider()) {
        let content: ContentDB
        do {
            content = try ContentLoader.bundled()
        } catch {
            fatalError("bundled content failed to load: \(error)")
        }
        self.game = Game(content: content)
        self.store = store
        self.storeService = storeService
        self.adProvider = adProvider
        let cached = store.loadResume()
        self.adsRemoved = cached?.purchases.adsRemoved ?? false
        self.hasSave = cached != nil
    }

    private var purchases: () -> Purchases {
        { [weak self] in Purchases(adsRemoved: self?.adsRemoved ?? false) }
    }

    func startNewGame() {
        session = GameSession.newGame(game: game, store: store, purchases: purchases)
        hasSave = true
    }

    func continueGame() {
        session = GameSession.resume(game: game, store: store, purchases: purchases)
        hasSave = session != nil
    }

    func backToTitle() {
        session?.pause()
        session = nil
        hasSave = store.hasResume
    }

    func deleteSave() {
        session = nil
        store.deleteAll()
        hasSave = false
    }

    /// 起動時に権利を確かめる(P1 では常に false が返る)。
    func refreshEntitlements() async {
        guard storeService.isAvailable else { return }
        adsRemoved = await storeService.adsRemovedEntitlement()
    }

    func purchaseRemoveAds() async {
        if await storeService.purchase(ProductID.removeAds) { adsRemoved = true }
        session?.persist()
    }

    func restorePurchases() async {
        if await storeService.restore() { adsRemoved = true }
        session?.persist()
    }
}

/// 全画面の共通の土台。広告枠コンテナの内側に画面を置くので、どの画面でも上下の枠は残る。
/// ゲームオーバー・勝利は全画面で出し、広告枠を見せない(§8.2)。
struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AdBannerContainer(adsRemoved: app.adsRemoved) {
            if let session = app.session {
                BaseView(session: session, app: app)
            } else {
                TitleView(app: app)
            }
        }
        .background(Color.black)
        .task { await app.refreshEntitlements() }
        .onChange(of: scenePhase) { _, phase in
            // 離れたら自動で ⏸ にして保存し、戻ったら自動で再開する(手で止めた時計は止めたまま)
            if phase == .active { app.session?.didBecomeActive() } else { app.session?.didBecomeInactive() }
        }
    }
}

#Preview {
    RootView(app: AppModel())
        .preferredColorScheme(.dark)
}
