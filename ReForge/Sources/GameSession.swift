import Foundation
import Observation
import ReForgeCore

/// 拠点画面に出すシート。1 度に 1 つだけ。プレイヤーが開いたときだけ出し、ゲームの側からは開かない。
/// 採取は拠点の画面に直接並べる。日没・夜明けは画面の中の表示が切り替わるだけ。
enum ActiveSheet: String, Identifiable {
    case craft, build, journal, settings
    var id: String { rawValue }
}

/// 休む・寝るの直後に数秒だけ出す知らせ(夜明けの要約と「取り消す」)。何も押さなくても消える。
struct RestToast: Equatable {
    let id: Int
    /// 夜明けの要約、または「体を休めた」。
    let lines: [String]
    /// 夜明けの要約か(別の行動をしても要約は残す。「体を休めた」は消す)。
    let isDawn: Bool
    /// 「取り消す」を出す残り秒。
    var undoRemaining: Double
    /// 知らせ全体を出す残り秒。
    var remaining: Double
}

/// 1 回のプレイ。GameState を 1 つ持ち、操作を Game(規則)に渡して結果で置き換えるだけ(§5.2)。
/// 昼の時計はここで回す。アプリが非アクティブの間は止める(REQ-13 / DEC-03)。
@MainActor
@Observable
final class GameSession {
    let game: Game
    let text: GameText
    private(set) var state: GameState
    private(set) var savePoint: GameState?
    /// 昼の時計が止まっているか(⏸)。
    private(set) var isPaused: Bool
    var sheet: ActiveSheet? = nil
    /// 直前の採取の結果(S2 の行の右に一瞬出す)。
    private(set) var flash: (kind: GatherKind, text: String, id: Int)? = nil
    /// 拒否の理由など、短く出す一言。
    private(set) var notice: (text: String, id: Int)? = nil
    /// 休む・寝るの直後の知らせ。
    private(set) var toast: RestToast? = nil
    /// 休む・寝るの取り消し用の控え。押し間違いは確認ダイアログでなく、これで戻す。
    private var restSnapshot: (undo: RestUndo, savePoint: GameState?)? = nil

    /// 「取り消す」を出す秒数と、夜明けの要約を出す秒数。
    static let undoSeconds: Double = 4
    static let dawnToastSeconds: Double = 6

    @ObservationIgnored private let store: SaveStore
    @ObservationIgnored private let purchases: () -> Purchases
    @ObservationIgnored private var counter = 0
    /// アプリが非アクティブになって自動で止めたか(戻ったら自動で再開する。手で止めたときは止めたまま)。
    @ObservationIgnored private var pausedByInactivity = false

    init(game: Game, state: GameState, savePoint: GameState?, startPaused: Bool,
         store: SaveStore, purchases: @escaping () -> Purchases) {
        self.game = game
        self.text = GameText(content: game.content, balance: game.balance)
        self.state = state
        self.savePoint = savePoint
        self.isPaused = startPaused
        self.store = store
        self.purchases = purchases
    }

    /// 新しく始める(はじめから)。
    static func newGame(game: Game, store: SaveStore, purchases: @escaping () -> Purchases) -> GameSession {
        let s = game.newGame(seed: UInt64.random(in: .min ... .max))
        let session = GameSession(game: game, state: s, savePoint: s, startPaused: false,
                                  store: store, purchases: purchases)
        session.persist(savePoint: true)
        return session
    }

    /// 保存から復帰する(つづきから)。時計は止めたまま表示し、▶ で再開する(S1)。
    static func resume(game: Game, store: SaveStore, purchases: @escaping () -> Purchases) -> GameSession? {
        guard let file = store.loadResume() else { return nil }
        let s = game.resume(file.state, elapsedWallClock: 0)
        return GameSession(game: game, state: s, savePoint: store.loadSavePoint(), startPaused: true,
                           store: store, purchases: purchases)
    }

    // MARK: 時計

    /// 昼の時計が進むか。寝た直後に「取り消す」が出ている数秒は朝の時計を止めておく
    /// (取り消せるのは何も起きていない間だけなので、時計が進むと取り消せなくなる)。
    var clockRunning: Bool {
        !isPaused && state.isActive && state.phase == .day && restSnapshot == nil
    }

    /// UI のタイマーから。dt は実時間の経過(秒)。
    func advanceClock(by dt: Double) {
        ageToast(by: dt)
        guard clockRunning else { return }
        let before = state.phase
        state = game.tick(state, deltaSeconds: dt)
        if state.phase != before || !state.isActive {
            persist()
            phaseDidChange()
        }
    }

    func pause() {
        pausedByInactivity = false
        guard !isPaused else { return }
        isPaused = true
        persist()
    }

    func play() {
        pausedByInactivity = false
        isPaused = false
    }

    /// アプリが非アクティブになった(背面・ロック・着信)。自動で ⏸ にして保存する。
    func didBecomeInactive() {
        if !isPaused { pausedByInactivity = true }
        isPaused = true
        persist()
    }

    /// アプリに戻ってきた。自動で止めた時計は自動で再開する(▶ を押させない)。
    func didBecomeActive() {
        guard pausedByInactivity else { return }
        pausedByInactivity = false
        isPaused = false
    }

    var dayRemainingFraction: Double { game.timeModel.dayRemainingFraction(state) }

    // MARK: 行動

    /// 実行前の可否(行の disabled と理由の表示用)。できるなら nil。
    func blocker(_ a: Action) -> String? {
        if case .failure(let e) = game.perform(a, on: state) { return text.message(for: e) }
        return nil
    }

    @discardableResult
    func perform(_ a: Action) -> Bool {
        if a == .rest { return rest() }
        switch game.perform(a, on: state) {
        case .success(let next):
            let wasPhase = state.phase
            state = next
            dropRestUndo()
            if case .gather(let kind) = a, case let .gathered(_, gains, _) = next.log.last?.event {
                counter += 1
                flash = (kind, text.gainFlash(gains), counter)
            }
            afterChange(from: wasPhase)
            return true
        case .failure(let e):
            show(text.message(for: e))
            return false
        }
    }

    /// 外の作業を夜に押したときなど、押せない理由を一言出す。
    func show(_ message: String) {
        counter += 1
        notice = (message, counter)
    }

    var canStartNightWork: Bool { game.canStartNightWork(state) }

    func startNightWork() {
        switch game.startNightWork(state) {
        case .success(let next):
            state = next
            dropRestUndo()
            persist()
        case .failure(let e):
            show(text.message(for: e))
        }
    }

    /// 休む(昼)・寝る(日没・夜作業中)。確認は出さずにすぐ実行し、数秒だけ「取り消す」を出す。
    /// 寝たら夜明けの要約を数秒だけ出す(全部の内訳は日誌)。どちらも画面は止めない。
    @discardableResult
    func rest() -> Bool {
        switch game.restWithUndo(state) {
        case .success(let undo):
            let savePointBefore = savePoint
            let slept = state.phase != .day
            state = undo.after
            // 決まった地点の自動セーブ: 毎朝
            persist(savePoint: slept && state.isActive)
            if !state.isActive {
                // ゲームオーバー・勝利は全画面で出すので、シートは閉じておく
                sheet = nil
            } else if !slept {
                phaseDidChange()
            }
            counter += 1
            // 取り消せる休みの直後の休み(連打)は、まとめて最初の休みの前まで戻せるようにする
            let previous = restSnapshot.flatMap { $0.undo.canUndo(undo.before) ? $0 : nil }
            let chained = undo.following(previous?.undo)
            if chained.canUndo(state) {
                restSnapshot = (chained, previous?.savePoint ?? savePointBefore)
                let lines = slept ? state.lastDawn.map(text.dawnSummary) ?? [] : state.log.last.map { [text.journal($0)] } ?? []
                toast = RestToast(id: counter, lines: lines, isDawn: slept, undoRemaining: Self.undoSeconds,
                                  remaining: slept ? Self.dawnToastSeconds : Self.undoSeconds)
            } else {
                restSnapshot = nil
                toast = nil
            }
            return true
        case .failure(let e):
            show(text.message(for: e))
            return false
        }
    }

    /// 「取り消す」を出しているか(押せば休む前に戻る)。
    var canUndoRest: Bool {
        guard let snap = restSnapshot, let toast, toast.undoRemaining > 0 else { return false }
        return snap.undo.canUndo(state)
    }

    /// 休む・寝るを取り消す。休む前の状態(と、寝て書いた朝のセーブ地点)をそのまま戻す。
    func undoRest() {
        guard canUndoRest, let snap = restSnapshot, let before = snap.undo.undo(state) else { return }
        state = before
        restSnapshot = nil
        toast = nil
        if let sp = snap.savePoint, sp != savePoint {
            savePoint = sp
            store.saveSavePoint(sp, purchases: purchases())
        }
        persist()
    }

    /// 手動セーブ。
    func manualSave() {
        guard state.isActive else { return }
        dropRestUndo()
        state = game.markManualSave(state)
        persist(savePoint: true)
        if let last = state.log.last { show(text.journal(last)) }
    }

    // MARK: 結末

    var gameOverReason: FailureReason? {
        if case .gameOver(let r) = state.outcome { return r }
        return nil
    }

    var isVictory: Bool { state.outcome == .victory }

    func recoveryChoices() -> [(recovery: any FailureRecovery, available: Bool)] {
        game.recoveryChoices(for: state, savePoint: savePoint)
    }

    func recover(_ option: RecoveryOption) {
        guard let next = game.recover(option, from: state, savePoint: savePoint) else { return }
        state = next
        isPaused = false
        sheet = nil
        dropRestUndo()
        // やり直し・巻き戻しはその朝をセーブ地点にする。続行・ロードは既存のセーブ地点を残す
        persist(savePoint: option == .restart || option == .rewindWithMemory)
    }

    func continueAfterVictory() {
        dropRestUndo()
        state = game.continueAfterVictory(state)
        persist()
    }

    // MARK: 内部

    private func afterChange(from wasPhase: Phase) {
        if state.day != savePoint?.day, state.phase == .day, wasPhase != .day {
            persist(savePoint: true)
        } else {
            persist()
        }
        phaseDidChange()
    }

    /// 時間帯が変わった。新しいシートは出さない(拠点の画面がその場で夜の表示に変わる)。
    /// 日没に開いていた「作る」「建てる」は、その時間帯には使えないので黙って閉じる。日誌・設定はそのまま。
    private func phaseDidChange() {
        if !state.isActive {
            // ゲームオーバー・勝利は全画面で出すので、シートは閉じておく
            sheet = nil
        } else if state.phase == .dusk, sheet == .craft || sheet == .build {
            sheet = nil
        }
    }

    /// 別のことが起きたので、もう取り消せない。夜明けの要約は残す。
    private func dropRestUndo() {
        restSnapshot = nil
        guard var t = toast else { return }
        if t.isDawn {
            t.undoRemaining = 0
            toast = t
        } else {
            toast = nil
        }
    }

    /// 知らせの残り時間を減らす(UI のタイマーから。何も押さなくても消える)。
    private func ageToast(by dt: Double) {
        guard var t = toast, dt > 0 else { return }
        t.undoRemaining -= dt
        t.remaining -= dt
        if t.undoRemaining <= 0 { restSnapshot = nil }
        toast = t.remaining > 0 ? t : nil
    }

    func persist(savePoint writeSavePoint: Bool = false) {
        store.saveResume(state, purchases: purchases())
        if writeSavePoint, state.isActive {
            savePoint = state
            store.saveSavePoint(state, purchases: purchases())
        }
    }
}
