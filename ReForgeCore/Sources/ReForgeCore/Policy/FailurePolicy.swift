/// 失敗の代償(DEC-11 / OPEN-02、オーナー決定)。
///
/// 餓死・脱水が確定したらゲームオーバーにし、ゲームオーバー画面でプレイヤーが 4 つの方針から選ぶ。
/// 4 つはどれも同じ扱い(推奨の順位を付けない)。方針ごとに FailureRecovery を差し替えられる。
public protocol FailurePolicy: Sendable {
    /// 餓死・脱水が確定したときの結末。
    func resolve(_ s: GameState, reason: FailureReason) -> GameOutcome
    /// ゲームオーバー画面に並べる方針(並び順 = 表示順)。
    var recoveries: [any FailureRecovery] { get }
}

/// ゲームオーバー後の方針。
public enum RecoveryOption: String, Codable, CaseIterable, Sendable {
    /// 1. 最初からやり直す(実績を狙う人向け)
    case restart
    /// 2. 記憶を持ったまま巻き戻す(ローグライト派)
    case rewindWithMemory
    /// 3. 仲間や資源の一部を失って、その場から続ける(物語を失いたくない人向け)
    case continueWithLoss
    /// 4. 最後のセーブ地点からロードする
    case loadSavePoint
}

/// 方針の実行に要るもの。
public struct RecoveryContext: Sendable {
    public let game: Game
    /// 最後のセーブ地点(手動セーブ、または決まった地点の自動セーブ)。
    public let savePoint: GameState?
    /// 新しく始めるときの seed。
    public let newSeed: UInt64

    public init(game: Game, savePoint: GameState?, newSeed: UInt64) {
        self.game = game
        self.savePoint = savePoint
        self.newSeed = newSeed
    }
}

public protocol FailureRecovery: Sendable {
    var option: RecoveryOption { get }
    func isAvailable(_ failed: GameState, _ ctx: RecoveryContext) -> Bool
    /// 選んだときの新しい状態。選べないときは nil。
    func recover(_ failed: GameState, _ ctx: RecoveryContext) -> GameState?
}

/// 既定の方針: ゲームオーバーにして 4 つから選ばせる。
public struct ChoiceFailurePolicy: FailurePolicy {
    public let recoveries: [any FailureRecovery]

    public init(recoveries: [any FailureRecovery] = [
        RestartRecovery(), RewindWithMemoryRecovery(), ContinueWithLossRecovery(), LoadSavePointRecovery(),
    ]) {
        self.recoveries = recoveries
    }

    public func resolve(_ s: GameState, reason: FailureReason) -> GameOutcome {
        .gameOver(reason)
    }
}

// MARK: - 1. 最初からやり直す

public struct RestartRecovery: FailureRecovery {
    public let option = RecoveryOption.restart
    public init() {}

    public func isAvailable(_ failed: GameState, _ ctx: RecoveryContext) -> Bool { true }

    public func recover(_ failed: GameState, _ ctx: RecoveryContext) -> GameState? {
        ctx.game.newGame(seed: ctx.newSeed)
    }
}

// MARK: - 2. 記憶を持ったまま巻き戻す

/// 何をどこまで持ち越すか。**未決(OPEN-10)。値はすべて仮。**
public struct RewindConfig: Equatable, Sendable {
    /// 持ち越す割合(%、切り捨て)。仮: 50。
    public var carryOverPercent: Int
    /// 持ち越す物。仮: 食料・水・保存食を除く資材。建造物・仲間・日数は持ち越さない。
    public var carriedItems: [ItemID]
    /// 日誌を残すか。仮: 残す(「記憶」)。
    public var keepsJournal: Bool

    public init(carryOverPercent: Int = 50,
                carriedItems: [ItemID] = [ID.wood, ID.plantFiber, ID.stone, ID.clay, ID.ironOre, ID.coal,
                                          ID.charcoal, ID.ironIngot, ID.ironPlate],
                keepsJournal: Bool = true) {
        self.carryOverPercent = carryOverPercent
        self.carriedItems = carriedItems
        self.keepsJournal = keepsJournal
    }
}

public struct RewindWithMemoryRecovery: FailureRecovery {
    public let option = RecoveryOption.rewindWithMemory
    public let config: RewindConfig

    public init(config: RewindConfig = RewindConfig()) {
        self.config = config
    }

    public func isAvailable(_ failed: GameState, _ ctx: RecoveryContext) -> Bool { true }

    public func carried(from failed: GameState) -> [ItemAmount] {
        config.carriedItems.compactMap { item in
            let n = failed.quantity(item) * config.carryOverPercent / 100
            return n > 0 ? ItemAmount(item, n) : nil
        }
    }

    public func recover(_ failed: GameState, _ ctx: RecoveryContext) -> GameState? {
        let b = ctx.game.balance
        var s = ctx.game.newGame(seed: ctx.newSeed)
        let carried = carried(from: failed)
        for c in carried { s.add(c.item, c.quantity, balance: b) }
        if config.keepsJournal { s.log = failed.log + s.log }
        s.rewindCount = failed.rewindCount + 1
        s.appendLog(.rewound(carried: carried), limit: b.logLimit)
        return s
    }
}

// MARK: - 3. 失って、その場から続ける

/// 何を失うか。**未決(OPEN-11)。値はすべて仮。**
public struct LossConfig: Equatable, Sendable {
    /// 去る仲間の数(後ろに並んだ人から)。仮: 1。仲間が残っていなければ物資だけ失う。
    public var companionsLost: Int
    /// 失う物資の割合(%、各品目で切り捨て)。仮: 50。
    public var itemLossPercent: Int

    public init(companionsLost: Int = 1, itemLossPercent: Int = 50) {
        self.companionsLost = companionsLost
        self.itemLossPercent = itemLossPercent
    }
}

public struct ContinueWithLossRecovery: FailureRecovery {
    public let option = RecoveryOption.continueWithLoss
    public let config: LossConfig

    public init(config: LossConfig = LossConfig()) {
        self.config = config
    }

    public func isAvailable(_ failed: GameState, _ ctx: RecoveryContext) -> Bool { true }

    public func companionsLost(_ failed: GameState) -> [String] {
        Array(failed.companions.suffix(min(config.companionsLost, failed.companions.count)))
    }

    public func recover(_ failed: GameState, _ ctx: RecoveryContext) -> GameState? {
        let b = ctx.game.balance
        var s = failed
        let gone = companionsLost(failed)
        s.companions.removeLast(gone.count)
        var lost: [ItemAmount] = []
        for item in ctx.game.content.items.map(\.id) {
            let n = s.quantity(item) * config.itemLossPercent / 100
            if n > 0, s.remove(item, n) { lost.append(ItemAmount(item, n)) }
        }
        // 飢え・渇きの日数を 0 に戻し、その朝から続ける
        s.daysWithoutFood = 0
        s.daysWithoutWater = 0
        s.outcome = .ongoing
        s.appendLog(.continuedWithLoss(lostCompanions: gone, lostItems: lost), limit: b.logLimit)
        return s
    }
}

// MARK: - 4. 最後のセーブ地点からロード

public struct LoadSavePointRecovery: FailureRecovery {
    public let option = RecoveryOption.loadSavePoint
    public init() {}

    public func isAvailable(_ failed: GameState, _ ctx: RecoveryContext) -> Bool {
        ctx.savePoint?.isActive == true
    }

    public func recover(_ failed: GameState, _ ctx: RecoveryContext) -> GameState? {
        guard var s = ctx.savePoint, s.isActive else { return nil }
        s.appendLog(.loadedSavePoint(day: s.day), limit: ctx.game.balance.logLimit)
        return s
    }
}
