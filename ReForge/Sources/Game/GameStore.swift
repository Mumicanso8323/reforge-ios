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
    private let log = Logger(subsystem: "com.yusukedoi.reforge", category: "game")

    private(set) var clock: ClockView
    private(set) var status: [StatusItem]
    private(set) var objective: String?
    private(set) var mapView: MapView
    private(set) var actors: [ActorSprite]
    private(set) var placements: [PlacementSprite]
    private(set) var route: [GridPoint]
    private(set) var focus: GridPoint?
    private(set) var decision: DecisionView?
    private(set) var sceneLines: [String]
    private(set) var prologue: PrologueView?
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

    /// 足元カードが注目しているマス(nil ならノアの足元)。
    private(set) var selected: GridPoint?
    private(set) var footCard: FootCard?
    /// 長押しで調べたマス(ふきだし)。
    private(set) var inspection: TileInspection?
    /// 断られた理由(足元カードに 1 行。数秒で消える)。
    private(set) var notice: String?

    /// 設計・ノートの画面側の状態(タブを切り替えても下書きを保つ。C-engine-ui.md §6。U17)。
    @ObservationIgnored let workbench = WorkbenchModel()

#if DEBUG
    /// 撮る起動だけの上書き(Debug/ScreenshotMode.swift)。保存せず、世界の状態も変えない。
    /// 画面の要素の解放を全部開く / 時計を止める(止めている間は保存も書かない)。
    static var forceAllUIOpen = false
    static var freezeClock = false
#endif

    /// 画面が前に出ているか(false の間は時計を進めない)。
    @ObservationIgnored var isActive = true
    /// 設定が開いている間 true(時計を進めない。L-10a)。閉じたら、止めていた間の実時間は進めず、再開した時点から数える。
    @ObservationIgnored var isPaused = false
    @ObservationIgnored private var lastRevision = -1
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var lastPhase: DayPhase = .day

    init(content: ContentDB, world: WorldState, saves: FileSaveStorage) {
        self.content = content
        self.saves = saves
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
        runEnded = f.runEnded
        ui = Self.shownUI(f)
        battles = f.battles
        defaultStance = f.defaultStance
        lastPhase = f.clock.phase
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
        var last = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let now = ProcessInfo.processInfo.systemUptime
            // 引っかかり(重い処理・背面からの復帰)で一度に大きく進めない。
            let dt = min(now - last, 0.25)
            last = now
#if DEBUG
            if Self.freezeClock { continue }
#endif
            guard isActive, !isPaused, clock.running else { continue }
            let (f, _) = await host.tick(realSeconds: dt)
            await refresh(f)
        }
    }

    /// いまの Frame と全区画を取り込む(最初の 1 回・テスト)。
    func load() async {
        await refresh(await host.frame)
    }

    // MARK: - 操作(すべて意図を送るだけ。確認ダイアログは出さない)

    /// マスをタップ: そこへ歩く(経路は本体が決め、点線で描く。歩いている途中のタップで行き先が変わる)。
    func walk(to cell: GridPoint) {
        selected = cell
        inspection = nil
        if let kind = placing {
            // 置くモード: タップで照準を動かし、照準の上をもう一度タップすると建てる(置けるときだけ)
            if let p = preview, p.at == cell, p.placeable {
                confirmPlacing()
            } else {
                Task { preview = await host.placementPreview(kind, at: cell) }
            }
            return
        }
        send(.crew(.walk(to: WorldPoint(mapView.layer, cell))))
    }

    /// マスを長押し: 調べる(ふきだし)。
    func inspect(_ cell: GridPoint) {
        selected = cell
        Task {
            inspection = await host.inspect(at: cell)
            // 調べたことで開いた要素があれば出す(U20。frame の版が上がっていなければ何もしない)
            await refresh(await host.frame)
            await refreshCard()
        }
    }

    func dismissInspection() { inspection = nil }

    /// 上の帯の時間の選択(夜作業 / 寝る)。
    func choose(_ a: BandAction) { send(a.command) }

    /// 決断を選ぶ(上の帯)。
    func decide(_ choice: ChoiceID) {
        guard let d = decision else { return }
        send(.narrative(.decide(decision: d.id, choice: choice)))
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
        let (f, rejection) = await host.perform(command)
        show(notice: rejection)
        await refresh(f)
        return rejection
    }

    func send(_ command: Command) {
        Task {
            let (f, rejection) = await host.perform(command)
            show(notice: rejection)
            await refresh(f)
        }
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
        if prologue != f.prologue { prologue = f.prologue }
        if runEnded != f.runEnded { runEnded = f.runEnded }
        if benchRevision != f.benchRevision { benchRevision = f.benchRevision }
        if ui != Self.shownUI(f) { ui = Self.shownUI(f) }
        if battles != f.battles { battles = f.battles }
        if defaultStance != f.defaultStance { defaultStance = f.defaultStance }
        revision = f.revision

        let stale = f.map.chunkRevisions.indices.filter { chunks[$0]?.revision != f.map.chunkRevisions[$0] }
        if !stale.isEmpty {
            for c in await host.chunks(stale) where (chunks[c.index]?.revision ?? -1) <= c.revision {
                chunks[c.index] = c
            }
        }
        await refreshCard()
        // 日没・夜明けで「つづきから」を書く(D-save.md §2)。
        if f.clock.phase != lastPhase {
            lastPhase = f.clock.phase
            // 夜明けの自動セーブ(巻き戻しの戻り先。D-save.md §2)
            if f.clock.phase == .day { await saveDawn() }
            await saveResume()
        }
    }

    private func refreshCard() async {
        guard let t = cardTarget else {
            footCard = nil
            return
        }
        let card = await host.footCard(at: t)
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
        let world = await host.world
        let env = SaveEnvelope(slot: .resume, world: world,
                               content: content.layers.map { ContentStamp(layer: $0.id, version: $0.version) })
        do {
            try saves.write(try SaveCodec.encode(env), slot: .resume)
        } catch {
            log.error("save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
