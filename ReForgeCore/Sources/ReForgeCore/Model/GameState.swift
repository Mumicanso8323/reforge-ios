/// 1 日の中の位置(§5.3)。
public enum Phase: String, Codable, Equatable, Sendable {
    /// 昼。時計がリアルタイムで進み、行動できる。
    case day
    /// 日没。「夜作業をする」か「寝る」を選ぶ。
    case dusk
    /// 夜作業中。火のそばでできる作業だけ。
    case night
    /// 夜明け(予約。MVP では「寝る」で直接 .day に戻る)。
    case dawn
}

public enum FailureReason: String, Codable, Equatable, Sendable {
    case starvation
    case dehydration
}

public enum GameOutcome: Codable, Equatable, Sendable {
    case ongoing
    case victory
    case gameOver(FailureReason)
}

public struct Building: Codable, Equatable, Sendable {
    public var id: BuildingID
    public var builtOnDay: Int

    public init(id: BuildingID, builtOnDay: Int) {
        self.id = id
        self.builtOnDay = builtOnDay
    }
}

/// 1 日分の消費・生産の集計。寝たときの結果シートと日誌の集計行に使う。
public struct DayTally: Codable, Equatable, Sendable {
    public var consumed: [ItemID: Int] = [:]
    public var produced: [ItemID: Int] = [:]
    /// この日、食料(保存食を含む)が足りない瞬間があったか。
    public var foodShort = false
    public var waterShort = false

    public init() {}

    mutating func addConsumed(_ item: ItemID, _ n: Int) {
        guard n > 0 else { return }
        consumed[item, default: 0] += n
    }

    mutating func addProduced(_ item: ItemID, _ n: Int) {
        guard n > 0 else { return }
        produced[item, default: 0] += n
    }
}

/// 夜が明けたときの報告(結果シートの中身)。
public struct DawnReport: Codable, Equatable, Sendable {
    /// 終わった日。
    public var endedDay: Int
    public var tally: DayTally
    public var daysWithoutFood: Int
    public var daysWithoutWater: Int
}

/// ゲームの状態。値型で、Resolver はこれを受け取って新しい状態を返す。
public struct GameState: Codable, Equatable, Sendable {
    public var seed: UInt64
    public var rngState: UInt64

    public var day: Int
    public var phase: Phase
    /// 昼に経過した実時間(秒)。0...daySeconds。
    public var dayElapsedSeconds: Double
    /// その日の消費・生産をどこまで適用したか(ゲーム内秒。0...1 日)。
    public var dayProgressGameSeconds: Int
    public var actionPointsLeft: Int
    /// いまの区間(昼 or 夜作業)の行動ポイントの上限。表示の「7/10」の分母。
    public var actionBudget: Int

    public var inventory: [ItemID: Int]
    public var buildings: [Building]
    /// 主人公以外の仲間。人口 = 1 + companions.count。
    public var companions: [String]
    public var scavengeRemaining: Int
    public var daysWithoutFood: Int
    public var daysWithoutWater: Int

    public var today: DayTally
    public var lastDawn: DawnReport?
    public var log: [LogEntry]

    public var outcome: GameOutcome
    /// 一度勝利したか(勝利後は「つづける」で同じルールのまま遊べる。勝利判定は 1 回だけ)。
    public var hasWon: Bool
    /// 「記憶を持ったまま巻き戻す」を使った回数。
    public var rewindCount: Int

    public var population: Int { 1 + companions.count }

    public func quantity(_ item: ItemID) -> Int { inventory[item] ?? 0 }

    public func has(_ building: BuildingID) -> Bool { buildings.contains { $0.id == building } }

    public var hasFire: Bool { has(ID.campfire) }

    public var isActive: Bool { outcome == .ongoing }

    /// 食料・水の保管上限。
    public func cap(for item: ItemID, balance: Balance) -> Int? {
        guard item == ID.food || item == ID.water else { return nil }
        return has(ID.storageCrate) ? balance.foodWaterCapWithCrate : balance.foodWaterCap
    }

    /// 上限を守って増やす。実際に増えた量を返す。
    @discardableResult
    mutating func add(_ item: ItemID, _ n: Int, balance: Balance) -> Int {
        guard n > 0 else { return 0 }
        let current = quantity(item)
        var target = current + n
        if let cap = cap(for: item, balance: balance) { target = min(target, max(cap, current)) }
        inventory[item] = target
        return target - current
    }

    /// 足りていれば減らして true。
    @discardableResult
    mutating func remove(_ item: ItemID, _ n: Int) -> Bool {
        guard n >= 0, quantity(item) >= n else { return false }
        inventory[item] = quantity(item) - n
        return true
    }

    mutating func appendLog(_ event: LogEvent, limit: Int) {
        log.append(LogEntry(day: day, event: event))
        if log.count > limit { log.removeFirst(log.count - limit) }
    }
}
