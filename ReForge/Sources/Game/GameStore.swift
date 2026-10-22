import Foundation
import Observation
import os
import ReForgeEngine

/// 主スレッド側のプレイ 1 回分(C-engine-ui.md §4)。本体(GameHost actor)から Frame を受け取り、
/// 項目ごとのプロパティに写す(変わった項目だけ差し替える: SwiftUI はそれを読むビューだけ描き直す)。
/// 画面は意図(Command)を送るだけで、世界状態を直接触らない。
///
/// - 昼の時計: 画面が前に出ている間だけ、約 20 回/秒 host.tick(realSeconds:) を呼ぶ。閉じている間は進まない。
/// - 地図: 区画の版が変わった区画だけ host.chunks で引き直してキャッシュする。
/// - 動く物: Frame を受け取った時刻(frameTime)からの経過で、描画側が 60fps で補間する。
@MainActor
@Observable
final class GameStore {
    let content: ContentDB
    let host: GameHost
    let saves: FileSaveStorage
    let saveWriter: any SaveWriting
    let log = Logger(subsystem: "com.yusukedoi.reforge", category: "game")
    @ObservationIgnored private let performanceNow: () -> ContinuousClock.Instant
    @ObservationIgnored private let perfSink: any PerfSink
    @ObservationIgnored private let perfSignpost = OSLog(subsystem: "reforge", category: "perf")
    @ObservationIgnored var playLog = PlayLog()
    @ObservationIgnored let playRecorder = PlayRecorder()

    private(set) var clock: ClockView
    /// 帯の目印の言葉の材料(W-19)。値が替わったときだけ写す。
    private(set) var timeMark: TimeMark
    private(set) var timeWord: String?
    /// 帯の日の棒の点(‰。内容から 1 回だけ作る)。
    let dayBarDots: [Int]
    private(set) var status: [StatusItem]
    private(set) var objective: String?
    private(set) var mapView: MapView
    private(set) var actors: [ActorSprite]
    private(set) var placements: [PlacementSprite]
    private(set) var route: [GridPoint]
    private(set) var focus: GridPoint?
    private(set) var decision: DecisionView?
    struct DecisionUndo: Equatable {
        var choice: ChoiceID
        var label: String
        var seconds: Int
    }
    private(set) var decisionUndo: DecisionUndo?
    /// 実行済みの操作を短時間だけ戻せる帯。世界の写しを持つので、取り消しは本体にも同じ形で戻る。
    struct TimedUndo {
        var label: String
        var seconds: Int
        fileprivate let world: WorldState
        fileprivate let wasPaused: Bool
    }
    private(set) var timedUndo: TimedUndo?
    private(set) var sceneLines: [String]
    private(set) var prologue: PrologueView?
    private(set) var darkStart: DarkStartView?
    private(set) var runEnded: Bool
    /// 設計・ノートのタブが引き直す印(Frame.benchRevision。U17)。
    private(set) var benchRevision = 0
    /// 画面の要素の解放(U18)。
    private(set) var ui: UIUnlocks
    /// 進行中の戦闘(帯と地図に出す)。
    private(set) var battles: [BattleBand]
    /// 戦闘が始まったときの方針(寝ている間も)。
    private(set) var defaultStance: BattleState.Stance
    /// 取り込んだ Frame の番号(パネルが引き直す合図)。
    private(set) var revision = 0
    /// 置くモード: 拠点のタブで選んだ建物(地図のタップがそのマスに建てるになる。U18)。
    var placing: StructureKindID?
    /// 置くモードの照準(地図に、置けるかどうかを色で描く)。
    var preview: PlacementPreview?
    /// 地図の上に開いた残骸のパネル(段階つきの資料など。U18)。
    var panel: DocumentPage?
    /// パネルから地図へ移りたいとき(置くモード)。GameScreen がタブを切り替えて nil に戻す。
    var requestedTab: GameTab?
    /// 区画の中身(番号 → 中身)。
    private(set) var chunks: [Int: MapChunk] = [:]
    /// 最後に Frame を受け取った時刻(ProcessInfo.systemUptime)。補間の起点。
    private(set) var frameTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    /// 開発の設定に出す直近 20 件の遅い歩み。製品のビルドでは常に空。
    private(set) var slowSteps: [SlowStep] = []

    /// 足元カードが注目しているマス(nil ならノアの足元)。
    private(set) var selected: GridPoint?
    private(set) var footCard: FootCard?
    /// 足元カードのいまのページ(行為が 4 つ以上のとき。選びが変わると 0 に戻る)。
    private(set) var footCardPage = 0
    /// 操作棒を出してよいか・歩ける範囲(本体が Frame で渡す)。
    private(set) var canSteer = false
    private(set) var walkable: [WalkSpan] = []
    /// 操作棒が通れない場所に当たった合図。
    private(set) var lastSteerBlocked = false
    /// 長押しで調べたマス(ふきだし)。
    private(set) var inspection: TileInspection?
    /// 断られた理由の参照。画面には出さず、数秒で捨てる。
    private(set) var noticeRef: TextRef?
    /// 夜の締めの 3 行(Frame.dayWrap。日没の間だけ。PT-B2)。
    private(set) var dayWrap: DayWrapView?
    /// 帯の火のゲージ(Frame.fireGauge。最初の火が点いてから)。
    private(set) var fireGauge: FireGaugeView?
    /// 日没の帯の申し出(Frame.offers。状態は持たず、毎回世界から導かれる)。
    private(set) var offers: [PendingOffer] = []
    private(set) var trial: TrialFrame?
    /// 再開の 1 行(前回の操作から実時間で resumeAfterMinutes 分以上たって戻ったとき。最初の命令かその日の終わりで消える。PT-B2)。
    var resumeBanner: ResumeLine?

    /// 設計・ノートの画面側の状態(タブを切り替えても下書きを保つ。C-engine-ui.md §6。U17)。
    @ObservationIgnored let workbench = WorkbenchModel()

#if DEBUG
    /// 撮る起動だけの上書き(Debug/ScreenshotMode.swift)。保存せず、世界の状態も変えない。
    /// 画面の要素の解放を全部開く / 時計を止める(止めている間は保存も書かない)。
    static var forceAllUIOpen = false
    static var freezeClock = false
#endif

    /// 画面が前に出ているか(false の間は時計を進めない)。前に戻ったとき、再開の 1 行を出すか決める(PT-B2)。
    @ObservationIgnored var isActive = true {
        didSet { if isActive, !oldValue { Task { await evaluateResume() } } }
    }
    /// 設定が開いている間 true(時計を進めない。L-10a)。閉じたら、止めていた間の実時間は進めず、再開した時点から数える。
    @ObservationIgnored var isPaused = false
    @ObservationIgnored private var lastRevision = -1
    /// 足元カードを引き直した回数。await から戻った時に番号が違えば、古い問い合わせの答えは捨てる(世界の差し替え・注目の移動)。
    @ObservationIgnored private var cardGeneration = 0
    /// 押したが受け付けられなかった回数。画面は文を出さず、押したボタンの短い揺れ(と弱い触覚)で応える。
    private(set) var refusals = 0
    /// 世界を差し替えた回数。地図の View はこれを識別にして作り直し、前の世界の画のキャッシュ・視点を残さない。
    private(set) var worldGeneration = 0
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    /// 断りを出した実時刻(systemUptime。ゲームの時計が止まっていても進む)と、出しておく長さ(秒。テストで短くする)。
    @ObservationIgnored private var noticeShownAt: TimeInterval = 0
    @ObservationIgnored private var lastSteerDirection: StickDirection?
    @ObservationIgnored var noticeLifetime: TimeInterval = 4
    @ObservationIgnored private var decisionUndoTask: Task<Void, Never>?
    @ObservationIgnored private var timedUndoTask: Task<Void, Never>?
    /// 帯の「戻す」で走り出した世界の差し替え。後から来た操作・差し替えはこれを待ってから本体へ送る(古い写しが後の操作を消さない)。
    @ObservationIgnored private var undoReplacement: Task<Void, Never>?
#if DEBUG
    /// 試験の継ぎ目: 「戻す」の差し替えを本体に送る直前に待つ(後の操作が先に届く形を作る)。
    @ObservationIgnored var undoInstallHook: (@MainActor () async -> Void)?
    /// 試験用: 後の操作が走っている「戻す」の差し替えを待ち始める所で、待った関数の名前を付けて呼ぶ。
    @ObservationIgnored var undoSettleHook: (@MainActor (String) async -> Void)?
#endif
    @ObservationIgnored private var lastPhase: DayPhase = .day
    @ObservationIgnored private var lastDay = 0
    /// 前回の操作の実時刻の置き場(保存の外。PT-B2)と、実時刻の読み方(テストで差し替える)。
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let now: () -> Date
    /// 設計かノートを開いている間 true(GameScreen が書く)。開発の設定が入のときだけ時計を止める(PT-B2)。
    @ObservationIgnored var benchOpen = false
    /// 振動の口と、出来事から合図を決める判定(A-01。保存には入れない)。
    @ObservationIgnored let haptics: any HapticFiring
    @ObservationIgnored private var hapticJudge = HapticJudge()
    @ObservationIgnored private var hapticRamp = HapticRamp()
    /// 音・触覚・浮かぶ文字の手応え(PT-B3。Frame.pulses を鳴らす)。
    let pulsePlayer: PulsePlayer

    init(content: ContentDB, world: WorldState, saves: FileSaveStorage,
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         performanceNow: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now },
         perfSink: any PerfSink = LoggerPerfSink(), saveWriter: (any SaveWriting)? = nil,
         haptics: (any HapticFiring)? = nil, pulsePlayer: PulsePlayer? = nil,
         language: LanguageID = .ja, markFallback: Bool = false, entitlements: Entitlements = Entitlements()) {
        let haptics = haptics ?? SystemHaptics()
        self.haptics = haptics
        // 試験の store は wav を読まない(実機は共有の 1 つを使う)
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.pulsePlayer = pulsePlayer ?? PulsePlayer(sounds: underTest ? SilentSounds() : SystemSounds.shared, haptics: haptics)
        self.content = content
        self.saves = saves
        self.saveWriter = saveWriter ?? SaveWriter(storage: saves)
        self.defaults = defaults
        self.now = now
        self.performanceNow = performanceNow
        self.perfSink = perfSink
        let host = GameHost(simulation: Simulation(content: content, entitlements: entitlements), world: world, language: language, markFallback: markFallback)
        self.host = host
        var builder = FrameBuilder(content: content)
        builder.entitlements = entitlements
        builder.language = language
        builder.markFallback = markFallback
        let f = builder.build(world, revision: 0, previous: nil, report: nil)
        clock = f.clock
        timeMark = f.timeMark
        timeWord = f.timeWord
        dayBarDots = TimeOfDay.dayBarDots(TimeOfDay.resolved(content.timeTint, clock: content.clock), clock: content.clock)
        status = f.status
        objective = f.objective
        mapView = f.map
        actors = f.actors
        placements = f.placements
        route = f.route
        focus = f.focus
        decision = f.decision
        sceneLines = f.sceneLines
        prologue = f.prologue
        darkStart = f.darkStart
        runEnded = f.runEnded
        ui = Self.shownUI(f)
        battles = f.battles
        defaultStance = f.defaultStance
        lastPhase = f.clock.phase
        lastDay = f.clock.day
        dayWrap = f.dayWrap
        fireGauge = f.fireGauge
        offers = f.offers
        trial = f.trial
        logPlay(kind: "build", fields: [
            "hand": MapTouchSettings.hand(defaults).rawValue,
            "directions": "\(MapTouchSettings.directions(defaults))",
            "neutral": "\(MapTouchSettings.neutralRadius(defaults))",
            "zoomPlan": MapTouchSettings.zoomPlan(defaults).rawValue,
            "tapWalk": "\(defaults.bool(forKey: MapTouchSettings.tapWalkKey))",
            "autoReturn": "\(defaults.object(forKey: MapTouchSettings.autoReturnKey) as? Bool ?? true)",
        ].merging(DeviceSnapshot.settings()) { $1 })
        InkHoldButton.logConfirm = { [weak self] id, phase in self?.logConfirm(id: id, phase: phase) }
    }

    func setEntitlements(_ entitlements: Entitlements) async {
        // 権利が替わると待たせていた出来事が動くので、開いている帯は確定する
        commitTimedUndo()
        await settleUndo()
        await refresh(await host.setEntitlements(entitlements))
    }

    /// 画面に出す解放(撮る起動の DEBUG のときだけ、Frame の値を全部開いた形に上書きする)。
    private static func shownUI(_ f: Frame) -> UIUnlocks {
#if DEBUG
        if forceAllUIOpen { return UIUnlocks(gated: f.ui.gated, open: f.ui.gated) }
#endif
        return f.ui
    }

    /// 地図に注目しているマス(足元カードの対象)。
    var cardTarget: GridPoint? { selected ?? focus }

    // MARK: - 時計

    /// 画面が出ている間ずっと回す(.task から。画面が消えると取り消される)。
    func run() async {
        await load()
        await evaluateResume()
        var last = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let now = ProcessInfo.processInfo.systemUptime
            // 引っかかり(重い処理・背面からの復帰)で一度に大きく進めない。
            let dt = min(now - last, 0.25)
            last = now
            await clockStep(realSeconds: dt)
        }
    }

    /// 時計を 1 回ぶん進める(止める条件を見てから)。回し方(実時間の待ち)と切り離し、テストからも直に呼べる。
    func clockStep(realSeconds dt: TimeInterval) async {
#if DEBUG
        if Self.freezeClock { return }
#endif
        // 保留の間(最初の行為の前)も呼ぶ。本体は、最初の行為を押していなければ何もしない(PT-B8)
        guard isActive, !isPaused, !benchHoldsClock, clock.running || clock.held else { return }
        await settleUndo()  // 「戻す」の差し替えより先に時計を進めない(差し替えで進めた分が消える)
        let start = performanceNow()
        os_signpost(.begin, log: perfSignpost, name: "clockStep")
        let (f, report) = await host.tick(realSeconds: dt)
        os_signpost(.end, log: perfSignpost, name: "clockStep")
        fireHaptics(for: report.events)
        let milliseconds = Self.milliseconds(from: start.duration(to: performanceNow()))
        if milliseconds > 50 {
            let rebuilt = f.revision != revision
            perfSink.recordStep(milliseconds: milliseconds, steps: report.steps, rebuilt: rebuilt)
#if DEBUG || REFORGE_DEV
            slowSteps.append(SlowStep(milliseconds: milliseconds, steps: report.steps, rebuilt: rebuilt))
            if slowSteps.count > 20 { slowSteps.removeFirst(slowSteps.count - 20) }
#endif
        }
        consume(report)
        await refresh(f)
    }

    /// いまの Frame と全区画を取り込む(最初の 1 回・テスト)。
    func load() async {
        await refresh(await host.frame)
    }

    /// 世界を進めずに、今持っている画面向けの文を指定した言語で引き直す。
    func setLanguage(_ lang: LanguageID) async {
        let f = await host.setLanguage(lang)
        await refresh(f)
        // 間に別の更新が入って切り替えの Frame が古い版として捨てられても、本体の最新(切り替え後に組んだ=新しい言語)を取り込む
        await refresh(await host.frame)
        // 待っている間に閉じた吹き出し・資料を生き返らせない(同じ物のままのときだけ置き換える)
        if let point = inspection?.point {
            let fresh = await host.peek(at: point)
            if inspection?.point == point { inspection = fresh }
        }
        if let id = panel?.id {
            let fresh = await host.document(id)
            if panel?.id == id { panel = fresh }
        }
        if let undo = decisionUndo, let label = decision?.choices.first(where: { $0.id == undo.choice })?.label {
            decisionUndo?.label = label
        }
        if resumeBanner != nil { resumeBanner = await host.resumeLine() }
    }

    /// 世界を丸ごと差し替える唯一の入口(つづきから・巻き戻し・ロード・台本の合わせ直し)。
    /// 本体の世界を替えたら、画面が持つ前の世界の写し(区画の中身・注目したマスと足元カード・調べた吹き出し・置くモードの照準・
    /// 断りの参照)を捨て、差し替え後の Frame を必ず取り込む(前の世界の区画や足元カードが居残らない)。
    @discardableResult
    func replaceWorld(_ world: WorldState) async -> Frame {
        commitTimedUndo()
        await settleUndo()
        return await installWorld(world)
    }

    /// 走り出した「戻す」の差し替えが本体に届くまで待つ。差し替えの中(取り込みが呼ぶ保存など)からは待たない(自分を待って止まらない)。
    func settleUndo(site: String = #function) async {
        guard !UndoChain.inside, let t = undoReplacement else { return }
#if DEBUG
        await undoSettleHook?(site)
#endif
        await t.value
    }

    private func installWorld(_ world: WorldState) async -> Frame {
        let f = await host.replace(world: world)
#if DEBUG
        ReplayStats.replaces += 1
        ReplayStats.replaceTimes.append(ProcessInfo.processInfo.systemUptime)
#endif
        worldGeneration += 1
        chunks = [:]
        selected = nil
        footCardPage = 0
        footCard = nil
        inspection = nil
        preview = nil
        placing = nil
        panel = nil
        noticeTask?.cancel()
        noticeRef = nil
        cardGeneration += 1
        // 取り込み中だった前の世界の Frame は、ここから先で捨てられる(refresh の門)。差し替えの Frame は必ず通す。
        lastRevision = min(lastRevision, f.revision - 1)
        await refresh(f)
        return f
    }

    // MARK: - 操作(すべて意図を送るだけ。確認ダイアログは出さない)

    /// マスを選び、足元カードをその場所へ替える。選んだだけでは歩かない。
    func select(_ cell: GridPoint) {
        clearNotice()
        if selected == cell, placing == nil {
            walkToSelection()
            return
        }
        if selected != cell { footCardPage = 0 }
        selected = cell
        inspection = nil
        if let kind = placing {
            // 置くモードのタップは照準を動かすだけ。建てるのは帯のボタンだけ。
            Task { preview = await host.placementPreview(kind, at: cell) }
            return
        }
        // 調べたことは世界に残るので、開いている帯は確定する(戻すで調べた事を消さない)
        commitTimedUndo()
        Task {
            await settleUndo()
            inspection = await host.inspect(at: cell)
            await refresh(await host.frame)
            await refreshCard()
        }
    }

    /// 選んだマスへ歩く。カードのボタンだけがこの命令を送る。
    func walkToSelection() {
        guard let cell = selected else { return }
        clearNotice()
        logPlay(kind: "walkSel", fields: ["x": "\(cell.x)", "y": "\(cell.y)", "zone": "bottom"])
        send(.crew(.walk(to: WorldPoint(mapView.layer, cell))))
    }

    /// ノアの足元へ選びを戻す。
    func clearSelection() { selected = nil; footCardPage = 0; inspection = nil; Task { await refreshCard() } }

    /// マスを長押し: 調べる(ふきだし)。
    func inspect(_ cell: GridPoint) {
        select(cell)
    }

    /// 足元カードの次のページへ(最後の次は最初に戻る)。
    func nextFootCardPage() {
        guard let card = footCard, card.pageCount > 1 else { return }
        footCardPage = (card.page + 1) % card.pageCount
        Task { await refreshCard() }
    }

    func dismissInspection() { inspection = nil }

    /// 上の帯の時間の選択(夜作業 / 寝る)。
    func choose(_ a: BandAction) { clearNotice(); send(a.command) }

    /// 決断を選ぶ(上の帯)。
    func decide(_ choice: ChoiceID) {
        guard let d = decision else { return }
        guard decisionUndo == nil, let label = d.choices.first(where: { $0.id == choice })?.label else { return }
        isPaused = true
        decisionUndo = DecisionUndo(choice: choice, label: label, seconds: 4)
        decisionUndoTask?.cancel()
        decisionUndoTask = Task { @MainActor in
            for remaining in stride(from: 3, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                decisionUndo?.seconds = remaining
            }
            guard !Task.isCancelled, let pending = decisionUndo, let decision else { return }
            decisionUndo = nil
            isPaused = false
            send(.narrative(.decide(decision: decision.id, choice: pending.choice)))
        }
    }

    func undoDecision() {
        logPlay(kind: "undo", fields: ["source": "decision"])
        decisionUndoTask?.cancel()
        decisionUndoTask = nil
        decisionUndo = nil
        isPaused = false
    }

    /// 本体へ送る操作を先に実行し、受け付けられた時だけ直前の世界へ戻す帯を出す。
    /// 取り消し中にも時計を進めるかは操作ごとに決める。
    @discardableResult
    func performUndoable(_ command: Command, label: String, seconds: Int = 4, pausesClock: Bool = false) async -> String? {
        noteOperation()  // 前の帯は確定して閉じる(押した物は必ず効く)
        await settleUndo()
        let before = await host.world
        let (f, rejection, rejectionRef) = await perform(throughHost: command)
        show(notice: rejectionRef)
        await refresh(f)
        if rejection == nil { beginTimedUndo(world: before, label: label, seconds: seconds, pausesClock: pausesClock) }
        return rejection
    }

    /// 世界を直接差し替える操作(ゲームオーバーからの復帰)にも同じ帯を付ける。
    func beginTimedUndo(world: WorldState, label: String, seconds: Int = 4, pausesClock: Bool = false) {
        timedUndoTask?.cancel()
        let wasPaused = isPaused
        if pausesClock { isPaused = true }
        timedUndo = TimedUndo(label: label, seconds: seconds, world: world, wasPaused: wasPaused)
        timedUndoTask = Task { @MainActor in
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                timedUndo?.seconds = remaining
            }
            commitTimedUndo()
        }
    }

    /// 帯の「戻す」。世界の差し替えは後から走るので、待ちたい呼び手(試験)には差し替えの Task を返す。
    @discardableResult
    func undoTimed() -> Task<Void, Never>? {
        guard let pending = timedUndo else { return nil }
        logPlay(kind: "undo", fields: ["source": "timed"])
        timedUndoTask?.cancel()
        timedUndoTask = nil
        timedUndo = nil
        isPaused = pending.wasPaused
        let previous = undoReplacement
        let task = Task { @MainActor in
            await previous?.value
            await UndoChain.$inside.withValue(true) {
#if DEBUG
                await undoInstallHook?()
#endif
                _ = await installWorld(pending.world)
            }
        }
        undoReplacement = task
        return task
    }

    /// 帯を確定して閉じる(時間切れ・次の操作・世界の差し替え)。古い写しで後の操作や別の走行を消さない。
    func commitTimedUndo() {
        guard let pending = timedUndo else { return }
        timedUndoTask?.cancel()
        timedUndoTask = nil
        timedUndo = nil
        isPaused = pending.wasPaused
    }

    /// 足元カードの行為。押し続ける行為は押し始め(pressing = true)と離した時(false)の 2 回。
    func act(_ a: FootCard.Action, pressing: Bool) {
        if pressing { clearNotice() }
        if a.hold {
            send(pressing ? a.start : a.end)
        } else if pressing {
            send(a.start)
        }
    }

    /// 意図を送り、断られた理由(認識の層を通した 1 行)を診断用に返す。
    @discardableResult
    func perform(_ command: Command) async -> String? {
        noteOperation()
        let (f, rejection, rejectionRef) = await perform(throughHost: command)
        show(notice: rejectionRef)
        await refresh(f)
        return rejection
    }

    func send(_ command: Command) {
        noteOperation()
        Task {
            let start = performanceNow()
            let (f, _, rejectionRef) = await perform(throughHost: command)
            let milliseconds = Self.milliseconds(from: start.duration(to: performanceNow()))
            if milliseconds > 100 { perfSink.recordApply(milliseconds: milliseconds) }
            show(notice: rejectionRef)
            await refresh(f)
        }
    }

    /// 操作棒は他の命令と同じく本体へ送る。理由は端末内の記録のために呼び出し側で渡す。
    func steer(_ direction: StickDirection?, reason: String) {
        if direction != lastSteerDirection { clearNotice() }  // 向きが変わった時だけ(押し続けて同じ断りを何度も出さない)
        lastSteerDirection = direction
        logPlay(kind: "steer", fields: ["direction": direction?.rawValue ?? "none", "reason": reason, "zone": "bottom"])
        send(.crew(.steer(direction: direction)))
    }

    func logPlay(kind: String, fields: [String: String]) {
        playLog?.append(PlayLogEvent(t: Date(), kind: kind, day: clock.day,
                                     minute: Int(clock.dayRemainingPermille), fields: fields))
    }

    /// host.perform と同じ(Frame と断った理由)。出来事も見て、振動を鳴らす。
    private func perform(throughHost command: Command) async -> (frame: Frame, rejection: String?, rejectionRef: TextRef?) {
        await settleUndo()
        let (f, report) = await host.send(command)
        consume(report)
        fireHaptics(for: report.events)
        guard let r = report.rejection else {
            recordCommand(command, rejection: nil, accepted: true)
            await recordMarks()
            return (f, nil, nil)
        }
        let ref = await host.rejectionRef(r)
        recordCommand(command, rejection: ref, accepted: false)
        return (f, await host.describe(r), ref)
    }

    /// 本体の出来事から振動の合図を決めて鳴らす(画面の推測では鳴らさない)。
    func fireHaptics(for events: [DomainEvent]) {
        guard !events.isEmpty else { return }
        for cue in hapticJudge.cues(for: events) { haptics.fire(cue) }
    }

    /// 暗い場面の長押しの進み(押している間だけ値。離したら nil)。進みに合わせて 0.25 秒おきに軽い振動を強める。
    func rampHaptic(permille: Int?) {
        let t = ProcessInfo.processInfo.systemUptime
        if let intensity = hapticRamp.intensity(permille: permille, at: t) { haptics.ramp(intensity: intensity) }
    }

    private static func milliseconds(from duration: Duration) -> Int {
        let parts = duration.components
        return Int((Double(parts.seconds) * 1_000) + (Double(parts.attoseconds) / 1_000_000_000_000_000))
    }

    // MARK: - Frame の取り込み

    func refresh(_ f: Frame) async {
        guard f.revision > lastRevision else { return }
        lastRevision = f.revision
        pulsePlayer.play(f.pulses)
        frameTime = ProcessInfo.processInfo.systemUptime
        expireNoticeIfStale()
        recordFrame(f)
        if clock != f.clock { clock = f.clock }
        if timeMark != f.timeMark { timeMark = f.timeMark }
        if timeWord != f.timeWord { timeWord = f.timeWord }
        if status != f.status { status = f.status }
        if objective != f.objective { objective = f.objective }
        if mapView != f.map { mapView = f.map }
        if actors != f.actors { actors = f.actors }
        if placements != f.placements { placements = f.placements }
        if route != f.route { route = f.route }
        if focus != f.focus { focus = f.focus }
        if decision != f.decision { decision = f.decision }
        if sceneLines != f.sceneLines { sceneLines = f.sceneLines }
        if runEnded != f.runEnded { runEnded = f.runEnded }
        if benchRevision != f.benchRevision { benchRevision = f.benchRevision }
        if ui != Self.shownUI(f) { ui = Self.shownUI(f) }
        if battles != f.battles { battles = f.battles }
        if defaultStance != f.defaultStance { defaultStance = f.defaultStance }
        if dayWrap != f.dayWrap { dayWrap = f.dayWrap }
        if fireGauge != f.fireGauge { fireGauge = f.fireGauge }
        if offers != f.offers { offers = f.offers }
        if trial != f.trial { trial = f.trial }
        if canSteer != f.canSteer { canSteer = f.canSteer }
        if walkable != f.walkable { walkable = f.walkable }
        // その日が終わる(日没・夜明け)と再開の 1 行は消える
        if resumeBanner != nil, f.clock.phase != .day || f.clock.day != lastDay { resumeBanner = nil }
        lastDay = f.clock.day
        revision = f.revision

        let stale = f.map.chunkRevisions.indices.filter { chunks[$0]?.revision != f.map.chunkRevisions[$0] }
        if !stale.isEmpty {
            for c in await host.chunks(stale) where (chunks[c.index]?.revision ?? -1) <= c.revision {
                chunks[c.index] = c
            }
        }
        await refreshCard()
        // await の間に、もっと新しい Frame の取り込みが先に入っていたら、古い側はここで捨てる
        // (古い序・暗い場面・日の区切りを書き戻して、消えたはずの画面が居残るのを防ぐ)
        guard lastRevision == f.revision else { return }
        // 序が終わったことは、地図の区画と足元カードを引き終えてから見せる(序の画面が消えた時に、地図と足元カードがそろっている)
        if prologue != f.prologue { prologue = f.prologue }
        if darkStart != f.darkStart { darkStart = f.darkStart }
        // 日没・夜明けで「つづきから」を書く(D-save.md §2)。
        if f.clock.phase != lastPhase {
            lastPhase = f.clock.phase
            // 夜明けの自動セーブ(巻き戻しの戻り先。D-save.md §2)
            if f.clock.phase == .day { await saveDawn() }
            await saveResume()
        }
    }

    private func consume(_ report: StepReport) {
        lastSteerBlocked = report.events.contains { if case .steerBlocked = $0 { true } else { false } }
        if lastSteerBlocked { logPlay(kind: "blocked", fields: ["zone": "bottom"]) }
    }

    private func refreshCard() async {
        cardGeneration += 1
        let generation = cardGeneration
        guard let t = cardTarget else {
            footCard = nil
            return
        }
        let card = await host.footCard(at: t, page: footCardPage)
        guard generation == cardGeneration else { return }
        if card != footCard { footCard = card }
    }

    /// 断りの理由を持つ(画面には出さない。診断と試験用)。同じ文がまだ出ている間の繰り返しは、出す長さを延ばさない(押し続けても居残らない)。
    func show(notice ref: TextRef?) {
        guard let ref else { clearNotice(); return }
        // 断りの理由は画面に出さない(押せるボタンは必ず受け付けられる決め)。押した事実への応えと、端末内の記録だけ。
        refusals += 1
        haptics.nudge()
        var fields = ["reason": ref.id.rawValue]
        for (key, arg) in ref.args.sorted(by: { $0.key < $1.key }) { fields["arg." + key] = String(describing: arg) }
        logPlay(kind: "refused", fields: fields)
        let t = ProcessInfo.processInfo.systemUptime
        if noticeRef == ref, t - noticeShownAt < noticeLifetime { return }
        noticeTask?.cancel()
        noticeRef = ref
        noticeShownAt = t
        let lifetime = noticeLifetime
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            if !Task.isCancelled { noticeRef = nil }
        }
    }

    /// 断りを消す。次の選び・歩き・行為の開始で呼ぶ(今のマスの断りでなくなるため)。
    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        if noticeRef != nil { noticeRef = nil }
    }

    /// 出してから noticeLifetime 秒たっていたら消す(Task が遅れた時の保険。実時間で見る)。
    private func expireNoticeIfStale() {
        if noticeRef != nil, ProcessInfo.processInfo.systemUptime - noticeShownAt >= noticeLifetime { clearNotice() }
    }

    // MARK: - 保存

    /// 「つづきから」を書く(背面に回る・日没・夜明け)。時計は止めた状態で戻す(閉じている間は進まない)。
    func saveResume() async {
#if DEBUG
        if Self.freezeClock { return }  // 撮る起動は保存を書かない
#endif
        await settleUndo()  // 走り出した「戻す」を書いてから保存する(差し替えの中からは待たない)
        do {
            let data = try await host.saveData(slot: .resume, stamps: contentStamps)
            try await saveWriter.write(data, slot: .resume)
        } catch {
            log.error("save failed: \(String(describing: error), privacy: .public)")
        }
    }

    var contentStamps: [ContentStamp] {
        content.layers.map { ContentStamp(layer: $0.id, version: $0.version) }
    }

    var slowStepSummary: String? {
        guard !slowSteps.isEmpty else { return nil }
        return "\(slowSteps.count) 件・最長 \(slowSteps.map(\.milliseconds).max() ?? 0)ms"
    }
}

/// 「戻す」の差し替えの中にいるか(差し替えが呼ぶ保存が自分を待たないため)。
enum UndoChain {
    @TaskLocal static var inside = false
}
