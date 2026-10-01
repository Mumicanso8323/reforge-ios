/// ゲームの規則一式。状態(GameState)は持たず、状態を受け取って新しい状態を返す。
/// UI はこれと GameState を 1 つずつ持つだけでよい。
public struct Game: Sendable {
    public let content: ContentDB
    public let timeModel: any TimeModel
    public let failurePolicy: any FailurePolicy
    public let offlinePolicy: any OfflinePolicy

    public var balance: Balance { timeModel.balance }

    public init(content: ContentDB,
                timeModel: any TimeModel = MixedDayNightTimeModel(),
                failurePolicy: any FailurePolicy = ChoiceFailurePolicy(),
                offlinePolicy: any OfflinePolicy = NoOfflineProgress()) {
        self.content = content
        self.timeModel = timeModel
        self.failurePolicy = failurePolicy
        self.offlinePolicy = offlinePolicy
    }

    // MARK: 新規

    public func newGame(seed: UInt64) -> GameState {
        var s = GameState(
            seed: seed, rngState: seed,
            day: 1, phase: .day, dayElapsedSeconds: 0, dayProgressGameSeconds: 0,
            actionPointsLeft: timeModel.dayActionBudget, actionBudget: timeModel.dayActionBudget,
            inventory: balance.initialInventory, buildings: [], companions: balance.initialCompanions,
            scavengeRemaining: balance.scavengeCount, daysWithoutFood: 0, daysWithoutWater: 0,
            today: DayTally(), lastDawn: nil, log: [],
            outcome: .ongoing, hasWon: false, rewindCount: 0)
        s.appendLog(.newGame, limit: balance.logLimit)
        return s
    }

    // MARK: 行動と時間

    public func perform(_ action: Action, on s: GameState) -> Result<GameState, ActionError> {
        if action == .rest, s.isActive, s.phase == .dusk || s.phase == .night {
            return sleep(s)
        }
        var rng = SeededRandom(state: s.rngState)
        return ActionResolver.apply(s, action, rng: &rng, content: content, timeModel: timeModel).map { next in
            var next = next
            next.rngState = rng.state
            return next
        }
    }

    /// 昼の経過。UI のタイマーから、アプリがアクティブな間だけ呼ぶ。
    public func tick(_ s: GameState, deltaSeconds: Double) -> GameState {
        var rng = SeededRandom(state: s.rngState)
        var next = timeModel.tick(s, deltaSeconds: deltaSeconds, rng: &rng)
        next.rngState = rng.state
        return checkFailure(next)
    }

    /// 寝る(日没・夜作業中。昼でも呼べるが UI は日没後だけ出す)。
    public func sleep(_ s: GameState) -> Result<GameState, ActionError> {
        guard s.isActive else { return .failure(.gameNotActive) }
        guard s.phase != .dawn else { return .failure(.notAllowed(s.phase)) }
        var rng = SeededRandom(state: s.rngState)
        var next = timeModel.sleep(s, rng: &rng)
        next.rngState = rng.state
        next = checkFailure(next)
        if next.isActive, Victory.check(next, balance) {
            next.outcome = .victory
            next.hasWon = true
            next.appendLog(.victory, limit: balance.logLimit)
        }
        return .success(next)
    }

    public func canStartNightWork(_ s: GameState) -> Bool {
        s.isActive && s.phase == .dusk && s.hasFire && timeModel.nightActionBudget > 0
    }

    public func startNightWork(_ s: GameState) -> Result<GameState, ActionError> {
        guard s.isActive else { return .failure(.gameNotActive) }
        guard s.phase == .dusk else { return .failure(.notAllowed(s.phase)) }
        guard canStartNightWork(s) else { return .failure(.noFireAtNight) }
        return .success(timeModel.startNightWork(s))
    }

    /// 勝利のあと「つづける」。同じルールで遊び続ける(勝利判定はもうしない)。
    public func continueAfterVictory(_ s: GameState) -> GameState {
        guard s.outcome == .victory else { return s }
        var s = s
        s.outcome = .ongoing
        return s
    }

    /// アプリの復帰。DEC-03 の既定では何も進めない。
    public func resume(_ s: GameState, elapsedWallClock: Double) -> GameState {
        offlinePolicy.onResume(s, elapsedWallClock: elapsedWallClock)
    }

    /// 手動セーブの印を日誌に残す。
    public func markManualSave(_ s: GameState) -> GameState {
        var s = s
        s.appendLog(.manualSave, limit: balance.logLimit)
        return s
    }

    // MARK: 失敗と立て直し

    private func checkFailure(_ s: GameState) -> GameState {
        guard s.isActive, let reason = SurvivalResolver.failure(s, balance) else { return s }
        var s = s
        s.outcome = failurePolicy.resolve(s, reason: reason)
        if case .gameOver = s.outcome { s.appendLog(.gameOver(reason), limit: balance.logLimit) }
        return s
    }

    public func recoveryContext(for failed: GameState, savePoint: GameState?) -> RecoveryContext {
        var rng = SeededRandom(state: failed.rngState ^ 0x5DEE_CE66_D1CE_4E5B)
        return RecoveryContext(game: self, savePoint: savePoint, newSeed: rng.next())
    }

    /// ゲームオーバー画面の選択肢(表示順)と選べるかどうか。
    public func recoveryChoices(for failed: GameState, savePoint: GameState?) -> [(recovery: any FailureRecovery, available: Bool)] {
        let ctx = recoveryContext(for: failed, savePoint: savePoint)
        return failurePolicy.recoveries.map { ($0, $0.isAvailable(failed, ctx)) }
    }

    public func recover(_ option: RecoveryOption, from failed: GameState, savePoint: GameState?) -> GameState? {
        guard case .gameOver = failed.outcome else { return nil }
        let ctx = recoveryContext(for: failed, savePoint: savePoint)
        guard let r = failurePolicy.recoveries.first(where: { $0.option == option }),
              r.isAvailable(failed, ctx) else { return nil }
        return r.recover(failed, ctx)
    }
}
