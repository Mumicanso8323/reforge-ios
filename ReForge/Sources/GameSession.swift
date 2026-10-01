import Foundation
import Observation
import ReForgeCore

/// 拠点画面に出すシート。1 度に 1 つだけ。
enum ActiveSheet: String, Identifiable {
    case gather, craft, build, journal, settings, nightfall, dawn
    var id: String { rawValue }
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

    @ObservationIgnored private let store: SaveStore
    @ObservationIgnored private let purchases: () -> Purchases
    @ObservationIgnored private var counter = 0

    init(game: Game, state: GameState, savePoint: GameState?, startPaused: Bool,
         store: SaveStore, purchases: @escaping () -> Purchases) {
        self.game = game
        self.text = GameText(content: game.content, balance: game.balance)
        self.state = state
        self.savePoint = savePoint
        self.isPaused = startPaused
        self.store = store
        self.purchases = purchases
        syncSheetWithPhase()
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

    var clockRunning: Bool {
        !isPaused && state.isActive && state.phase == .day && sheet != .dawn
    }

    /// UI のタイマーから。dt は実時間の経過(秒)。
    func advanceClock(by dt: Double) {
        guard clockRunning else { return }
        let before = state.phase
        state = game.tick(state, deltaSeconds: dt)
        if state.phase != before || !state.isActive {
            persist()
            syncSheetWithPhase()
        }
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        persist()
    }

    func play() { isPaused = false }

    /// アプリが非アクティブになった(背面・ロック・着信)。自動で ⏸ にして保存する。
    func didBecomeInactive() {
        isPaused = true
        persist()
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
        if a == .rest, state.isActive, state.phase == .dusk || state.phase == .night {
            sleep()
            return true
        }
        switch game.perform(a, on: state) {
        case .success(let next):
            let wasPhase = state.phase
            state = next
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

    func startNightWork() {
        switch game.startNightWork(state) {
        case .success(let next):
            state = next
            sheet = nil
            persist()
        case .failure(let e):
            show(text.message(for: e))
        }
    }

    func sleep() {
        guard case .success(let next) = game.sleep(state) else { return }
        state = next
        if state.isActive {
            // 決まった地点の自動セーブ: 毎朝
            persist(savePoint: true)
            sheet = .dawn
        } else {
            persist()
            sheet = nil
        }
    }

    /// 夜明けの結果シートを閉じて、朝をはじめる。
    func beginMorning() {
        sheet = nil
    }

    /// 手動セーブ。
    func manualSave() {
        guard state.isActive else { return }
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
        // やり直し・巻き戻しはその朝をセーブ地点にする。続行・ロードは既存のセーブ地点を残す
        persist(savePoint: option == .restart || option == .rewindWithMemory)
    }

    func continueAfterVictory() {
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
        syncSheetWithPhase()
    }

    /// 日没になったら S1-N を出す。
    private func syncSheetWithPhase() {
        if !state.isActive {
            // ゲームオーバー・勝利は全画面で出すので、シートは閉じておく
            sheet = nil
        } else if state.phase == .dusk {
            sheet = .nightfall
        } else if sheet == .nightfall {
            sheet = nil
        }
    }

    func persist(savePoint writeSavePoint: Bool = false) {
        store.saveResume(state, purchases: purchases())
        if writeSavePoint, state.isActive {
            savePoint = state
            store.saveSavePoint(state, purchases: purchases())
        }
    }
}
