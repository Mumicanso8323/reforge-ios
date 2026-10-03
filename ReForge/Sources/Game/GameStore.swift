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
    private let playLog = PlayLog()

    private(set) var clock: ClockView
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
    /// 断られた理由(足元カードに 1 行。数秒で消える)。
    private(set) var notice: String?
    /// 夜の締めの 3 行(Frame.dayWrap。日没の間だけ。PT-B2)。
    private(set) var dayWrap: DayWrapView?
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
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var decisionUndoTask: Task<Void, Never>?
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

    init(content: ContentDB, world: WorldState, saves: FileSaveStorage,
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         performanceNow: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now },
         perfSink: any PerfSink = LoggerPerfSink(), saveWriter: (any SaveWriting)? = nil,
         haptics: (any HapticFiring)? = nil) {
        self.haptics = haptics ?? SystemHaptics()
        self.content = content
        self.saves = saves
        self.saveWriter = saveWriter ?? SaveWriter(storage: saves)
        self.defaults = defaults
        self.now = now
        self.performanceNow = performanceNow
        self.perfSink = perfSink
        let host = GameBootstrap.host(content: content, world: world)
        self.host = host
        let f = FrameBuilder(content: content).build(world, revision: 0, previous: nil, report: nil)
        clock = f.clock
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
        logPlay(kind: "build", fields: [
            "hand": MapTouchSettings.hand(defaults).rawValue,
            "directions": "\(MapTouchSettings.directions(defaults))",
            "neutral": "\(MapTouchSettings.neutralRadius(defaults))",
            "zoomPlan": MapTouchSettings.zoomPlan(defaults).rawValue,
            "tapWalk": "\(defaults.bool(forKey: MapTouchSettings.tapWalkKey))",
            "autoReturn": "\(defaults.object(forKey: MapTouchSettings.autoReturnKey) as? Bool ?? true)",
        ])
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

    // MARK: - 操作(すべて意図を送るだけ。確認ダイアログは出さない)

    /// マスを選び、足元カードをその場所へ替える。選んだだけでは歩かない。
    func select(_ cell: GridPoint) {
        if selected != cell { footCardPage = 0 }
        selected = cell
        inspection = nil
        if let kind = placing {
            // 置くモードのタップは照準を動かすだけ。建てるのは帯のボタンだけ。
            Task { preview = await host.placementPreview(kind, at: cell) }
            return
        }
        Task {
            inspection = await host.inspect(at: cell)
            await refresh(await host.frame)
            await refreshCard()
        }
    }

    /// 選んだマスへ歩く。カードのボタンだけがこの命令を送る。
    func walkToSelection() {
        guard let cell = selected else { return }
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
    func choose(_ a: BandAction) { send(a.command) }

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
        decisionUndoTask?.cancel()
        decisionUndoTask = nil
        decisionUndo = nil
        isPaused = false
    }

    /// 足元カードの行為。押し続ける行為は押し始め(pressing = true)と離した時(false)の 2 回。
    func act(_ a: FootCard.Action, pressing: Bool) {
        if a.hold {
            send(pressing ? a.start : a.end)
        } else if pressing {
            send(a.start)
        }
    }

    /// 意図を送り、断られた理由(認識の層を通した 1 行)を返す。地図以外のタブが自分の場所に出す(U17)。
    @discardableResult
    func perform(_ command: Command) async -> String? {
        noteOperation()
        let (f, rejection) = await perform(throughHost: command)
        show(notice: rejection)
        await refresh(f)
        return rejection
    }

    func send(_ command: Command) {
        noteOperation()
        Task {
            let start = performanceNow()
            let (f, rejection) = await perform(throughHost: command)
            let milliseconds = Self.milliseconds(from: start.duration(to: performanceNow()))
            if milliseconds > 100 { perfSink.recordApply(milliseconds: milliseconds) }
            show(notice: rejection)
            await refresh(f)
        }
    }

    /// 操作棒は他の命令と同じく本体へ送る。理由は端末内の記録のために呼び出し側で渡す。
    func steer(_ direction: StickDirection?, reason: String) {
        logPlay(kind: "steer", fields: ["direction": direction?.rawValue ?? "none", "reason": reason, "zone": "bottom"])
        send(.crew(.steer(direction: direction)))
    }

    func logPlay(kind: String, fields: [String: String]) {
        playLog?.append(PlayLogEvent(t: Date(), kind: kind, day: clock.day,
                                     minute: Int(clock.dayRemainingPermille), fields: fields))
    }

    /// host.perform と同じ(Frame と断った理由)。出来事も見て、振動を鳴らす。
    private func perform(throughHost command: Command) async -> (frame: Frame, rejection: String?) {
        let (f, report) = await host.send(command)
        consume(report)
        fireHaptics(for: report.events)
        let rejection: String?
        if let r = report.rejection { rejection = await host.describe(r) } else { rejection = nil }
        return (f, rejection)
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
        frameTime = ProcessInfo.processInfo.systemUptime
        if clock != f.clock { clock = f.clock }
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
        guard let t = cardTarget else {
            footCard = nil
            return
        }
        let card = await host.footCard(at: t, page: footCardPage)
        if card != footCard { footCard = card }
    }

    private func show(notice text: String?) {
        noticeTask?.cancel()
        notice = text
        guard text != nil else { return }
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { notice = nil }
        }
    }

    // MARK: - 保存

    /// 「つづきから」を書く(背面に回る・日没・夜明け)。時計は止めた状態で戻す(閉じている間は進まない)。
    func saveResume() async {
#if DEBUG
        if Self.freezeClock { return }  // 撮る起動は保存を書かない
#endif
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
