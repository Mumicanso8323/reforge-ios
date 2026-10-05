import SwiftUI
import ReForgeEngine

@main
struct ReForgeApp: App {
    @State private var app: AppModel

    init() {
#if DEBUG
        // 撮る起動(-ReForgeScreenshot)なら、公開の層の新しい世界を開いた状態で始める(Debug/ScreenshotMode.swift)
        // 通しの台本の流し込み(-ReForgeReplay)なら、台本の seed の新しい世界で始める(Debug/ReplayDriver.swift。A-07)
        if !ScreenshotMode.isActive, let script = ReplayMode.script {
            _app = State(initialValue: ReplayMode.makeModel(script: script))
        } else {
            _app = State(initialValue: ScreenshotMode.makeModel())
        }
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
                .replaySupport(app: app)
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
    let backgroundTasks: any BackgroundTaskManaging
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

    /// いま画面を覆っている全画面の場面(無ければ nil)。本体の序・場面、撮る起動なら見本。
    var activePrologue: PrologueView? {
#if DEBUG
        if let debugPrologue { return debugPrologue.view }
#endif
        return game?.prologue
    }

    /// 全画面の場面を送る(タップだけ。時間では送らない)。
    func advancePrologue() {
#if DEBUG
        if let debugPrologue { debugPrologue.advance(); return }
#endif
        game?.send(.narrative(.advanceScene))
    }

    /// 序を一度最後まで読んだ端末の印(保存には入れない。A-01)。
    let prologueSeen: PrologueSeen
    private var skippingPrologue = false

    /// 「飛ばす」を出すか: 序の間で、一度読み終えた端末の 2 回目から(1 回目は出さない)。
    var canSkipPrologue: Bool { activePrologue?.kind == .prologue && prologueSeen.isSet }

    /// 序が終わった(最後まで読んだ。ほかの全画面の場面では呼ばない)。見本の序(撮る起動)では印を立てない。
    func prologueFinished() {
#if DEBUG
        if debugPrologue != nil { return }
#endif
        prologueSeen.mark()
    }

    /// 「飛ばす」: 序の残りの行を、本体の今の送り(.narrative(.advanceScene))で最後まで送る。序の効果・then は今のまま起きる。
    func skipPrologue() {
        guard canSkipPrologue, !skippingPrologue else { return }
        skippingPrologue = true
        let target = game
        Task {
            var rounds = 0
            while activePrologue?.kind == .prologue, rounds < 300 {
                rounds += 1
#if DEBUG
                if let sample = debugPrologue {
                    sample.advance()
                    continue
                }
#endif
                guard let g = game, g === target else { break }
                // 本体が行を出している途中で断られたら、少し待って送り直す
                if await g.perform(.narrative(.advanceScene)) != nil {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            skippingPrologue = false
        }
    }

    /// 右上の設定の角のボタンを出すか。全画面の場面と、最初の行為の前の暗い場面の間は出さない(窓ごと隠す。PT-B6・DEC-F9:
    /// 「はじめから」から地図が出るまで、押せる物は暗い場面のボタン 1 つだけ)。
    var cornerButtonVisible: Bool { activePrologue == nil && game?.darkStart == nil }

    init(saves: FileSaveStorage = FileSaveStorage(),
         storeService: any StoreService = UnavailableStoreService(),
         adProvider: any AdProvider = NoopAdProvider(),
         backgroundTasks: any BackgroundTaskManaging = ApplicationBackgroundTasks(),
         bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.prologueSeen = PrologueSeen(defaults: defaults)
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
        self.backgroundTasks = backgroundTasks
        self.adsRemoved = UserDefaults.standard.bool(forKey: Self.adsRemovedKey)
        self.hasResume = Self.resumeIsReadable(saves)
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
    /// 通しの台本の流し込み(Debug/ReplayDriver.swift。A-07): 保存を読まず、台本の seed の新しい世界を開く。時計は止めない。
    func startReplayGame(seed: UInt64) {
        guard let content else { return }
        GameStore.forgetLastOperation()
        let world = GameBootstrap.newWorld(content: content, seed: seed)
        game = GameStore(content: content, world: world, saves: saves)
        game?.isPaused = settingsOpen
    }

    /// 撮る起動(Debug/ScreenshotMode.swift): 保存を読まず・書かない、固定の種の新しい世界を開く。
    /// failed なら走行が終わった形(ゲームオーバーの 4 択)にする。
    /// decision なら、公開の層の試験用の決断を 1 つ出した形にする(決断の帯)。
    func startScreenshotGame(failed: Bool, decision: Bool, darkStart: Bool = false, darkMark: Bool = false,
                             foot: Bool = false) {
        guard var content else { return }
        if darkMark, var mark = content.structures["structure.fence"] {
            mark.seenInDark = true
            content.structures[mark.id] = mark
        }
        var world = GameBootstrap.newWorld(content: content, seed: 1)
        if failed { world.run.outcome = .failed(cause: "text.screenshot.cause", record: nil) }
        if decision {
            world.narrative.pending = [PendingDecision(id: world.newEntityID(), event: "event.test.decision",
                                                       choices: ["choice.test.yes", "choice.test.no"], blocking: false,
                                                       since: world.clock.now, origin: nil)]
        }
        if darkStart { world.clock.held = true }
        if darkMark {
            world.clock.phase = .nightWork
            let origin = world.map.spawn
            let markPoint = GridPoint(origin.point.x + 7, origin.point.y + 7)
            world.map[origin.layer]?.setTerrain("grass", at: markPoint)
            var ctx = StepContext(world: world, content: content)
            EffectApplier.apply([
                .placeStructure(structure: "structure.campfire", at: .point(at: origin), built: true),
                .hearth(at: .point(at: origin), op: .ignite()),
                .placeStructure(structure: "structure.fence", at: .point(at: WorldPoint(origin.layer, markPoint)), built: true),
            ], &ctx, cause: nil)
            world = ctx.world
        }
        if foot {
            // 足元カードの写真: ノアの隣に、押すだけの行為(森で枝を拾う)と長押しの行為(鉱脈を手で掘る)が並ぶ形にする
            let origin = world.map.spawn
            let forest = GridPoint(origin.point.x + 1, origin.point.y)
            let vein = GridPoint(origin.point.x, origin.point.y - 1)
            world.map[origin.layer]?.setTerrain("forest", at: forest)
            var rng = SeededRandom(state: 1)
            world.map[origin.layer]?.deposits.add(
                DepositGenerator.make(id: DepositID("deposit.screenshot"), at: vein, category: .coal, rng: &rng))
        }
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

    /// 「つづきから」を出してよいか。読み出せて SaveCodec で読め(壊れ・未来の版でない)、世界を作れるときだけ true。
    /// 重いので毎フレームは呼ばない(題の画面を作る時・保存を書いた/消した時だけ)。読めない保存のファイルは消さない(復旧の余地)。
    static func resumeIsReadable(_ saves: FileSaveStorage) -> Bool {
        guard let data = try? saves.read(slot: .resume) else { return false }
        return (try? SaveCodec.decode(data)) != nil
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
        hasResume = Self.resumeIsReadable(saves)
    }

    /// 記録を消す(取り返しがつかない。確認のダイアログは出さず、題の画面の長押しだけが呼ぶ)。
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
        if !active, let g = game { saveInBackground(g) }
    }

    /// 背面へ移るとき、保存が終わるまでの時間を OS に確保してもらう。
    func saveInBackground(_ game: GameStore) {
        let task = BackgroundTaskBox()
        task.id = backgroundTasks.begin(name: "save") { [weak self] in
            // 時間切れ。OS はこの中で終了を呼ぶことを求める(呼ばないとアプリごと止められる)
            MainActor.assumeIsolated { self?.endBackgroundSave(task) }
        }
        Task {
            await game.saveResume()
            endBackgroundSave(task)
        }
    }

    /// 背面の保存の確保を 1 度だけ終える(完了と時間切れのどちらが先でも)。
    private func endBackgroundSave(_ task: BackgroundTaskBox) {
        guard !task.ended else { return }
        task.ended = true
        backgroundTasks.end(task.id)
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

/// 背面の保存の確保の識別と、終えたかの印(完了と時間切れで 2 度終えない)。
@MainActor
final class BackgroundTaskBox {
    var id: UIBackgroundTaskIdentifier = .invalid
    var ended = false
}

/// 全画面の共通の土台。広告枠コンテナの内側に画面を置くので、どの画面でも下の枠は残る。
struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// 全画面の場面が終わった直後の移りを演じている間の、最後の表示。nil なら移りは無い。
    @State private var exitingScene: PrologueView?

    var body: some View {
        ZStack {
            mainContent
            // 全画面の場面は安全域の外まで覆い、地図・帯・タブ・角のボタンは作らない。
            if let prologue = app.activePrologue {
                PrologueScene(kind: prologue.kind, lines: prologue.lines, speakers: prologue.speakers,
                              advance: { app.advancePrologue() })
                    .ignoresSafeArea()
                if app.canSkipPrologue {
                    PrologueSkipButton(skip: { app.skipPrologue() })
                }
            } else if let scene = exitingScene {
                PrologueScene(kind: scene.kind, lines: scene.lines, speakers: scene.speakers,
                              exiting: true, onExitDone: { exitingScene = nil })
                    .ignoresSafeArea()
            }
        }
        .onChange(of: app.activePrologue) { old, new in
            if let old, new == nil, app.game != nil {
                if old.kind == .prologue { app.prologueFinished() }
                exitingScene = old
            } else if new != nil {
                exitingScene = nil
            }
        }
        .background(InkColor.prologueGround)
        .background(SettingsCornerInstaller(app: app, visible: app.cornerButtonVisible && exitingScene == nil))
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
