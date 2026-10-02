import RFKernel

/// 出来事の進み。持ち主: RFNarrative。
/// 出来事は日数でなく、プレイヤーの行動(DomainEvent)と世界の状態で起きる。条件と効果はコンテンツのデータ。
public struct NarrativeState: Codable, Equatable, Sendable {
    public var fired: [EventID: FiredRecord] = [:]
    /// 決断待ち。プレイヤーを止めてよいのはこれ(blocking のもの)だけ。
    public var pending: [PendingDecision] = []
    /// 予約した出来事(効果 schedule)。
    public var scheduled: [ScheduledEvent] = []
    /// 汎用の数(コンテンツが名前を決める)。
    public var counters: [CounterID: Int] = [:]
    /// 追跡カウンタの端数(近くで働いたゲーム秒など)。TrackerDef が counters に繰り上げる。
    public var trackerCarry: [CounterID: Int64] = [:]
    public var objectives: [ObjectiveID: ObjectiveStatus] = [:]
    public var chapter: ChapterID?
    /// いま流れている場面(会話の定型文の並び)。画面の下の帯で流し、地図を止めない。
    public var scene: SceneProgress?
    public var ending: EndingID?
    /// 直近の仲間の一言(新しい順でなく言った順。上限 lineLogLimit)。同じ一言を続けて言わないためと、画面の帯のため。
    public var lineLog: [SpokenLine] = []

    /// 工程表の進み(記録を開いた・答えを置いた・工程表を使った・選ぶ表)。無い保存は空として読む。
    public var sheets: [SheetID: SheetProgress]?

    public static let lineLogLimit = 16

    public func sheet(_ id: SheetID) -> SheetProgress { sheets?[id] ?? SheetProgress() }

    public mutating func updateSheet(_ id: SheetID, _ body: (inout SheetProgress) -> Void) {
        var all = sheets ?? [:]
        var p = all[id] ?? SheetProgress()
        body(&p)
        all[id] = p
        sheets = all
    }

    public init() {}
}

/// 仲間の一言 1 つ(文字は持たない。LineDef の ID だけ)。
public struct SpokenLine: Codable, Equatable, Sendable {
    public var person: PersonID
    public var line: LineID
    public var at: GameTime

    public init(person: PersonID, line: LineID, at: GameTime) {
        self.person = person
        self.line = line
        self.at = at
    }
}

public struct FiredRecord: Codable, Equatable, Sendable {
    public var count: Int
    public var lastAt: GameTime
    /// 発火の来歴(効果で起きた変化の inputs になる)。
    public var lastRecord: ProvenanceID?
    /// 最後に起きた日(1 日 1 回までの判定)。
    public var lastDay: Int?

    public init(count: Int, lastAt: GameTime, lastRecord: ProvenanceID?, lastDay: Int? = nil) {
        self.count = count
        self.lastAt = lastAt
        self.lastRecord = lastRecord
        self.lastDay = lastDay
    }
}

public struct PendingDecision: Codable, Equatable, Sendable {
    public var id: EntityID
    public var event: EventID
    /// 出したときに選べた選択肢。
    public var choices: [ChoiceID]
    /// 決めるまで時計を止めるか(コンテンツの指定。既定は止めない)。
    public var blocking: Bool
    public var since: GameTime
    public var origin: ProvenanceID?

    public init(id: EntityID, event: EventID, choices: [ChoiceID], blocking: Bool, since: GameTime, origin: ProvenanceID?) {
        self.id = id
        self.event = event
        self.choices = choices
        self.blocking = blocking
        self.since = since
        self.origin = origin
    }
}

public struct ScheduledEvent: Codable, Equatable, Sendable {
    public var event: EventID
    public var at: GameTime
    /// 予約した効果の引き金(起きたときの来歴の inputs に入る)。
    public var cause: ProvenanceID?

    public init(event: EventID, at: GameTime, cause: ProvenanceID? = nil) {
        self.event = event
        self.at = at
        self.cause = cause
    }
}

public enum ObjectiveStatus: String, Codable, Sendable { case active, done, failed }

public struct SceneProgress: Codable, Equatable, Sendable {
    public var scene: SceneID
    public var line: Int
    /// いまの行を出し始めた時刻(押さなくても時間で次の行へ流れる)。
    public var lineSince: GameTime?
    /// 場面を始めた出来事の来歴(行の条件の引き金)。
    public var origin: ProvenanceID?

    public init(scene: SceneID, line: Int = 0, lineSince: GameTime? = nil, origin: ProvenanceID? = nil) {
        self.scene = scene
        self.line = line
        self.lineSince = lineSince
        self.origin = origin
    }
}

/// 工程表 1 つの進み(U15。BEAT-05・06・07・29)。来歴の ID だけを持つ(文字は持たない)。
public struct SheetProgress: Codable, Equatable, Sendable {
    /// 表そのものを開いた。
    public var openedIndex = false
    /// 開いた記録の席。
    public var openedSlots: Set<Int> = []
    /// 開いた空いた席。
    public var emptySeen: Set<Int> = []
    /// 行 → 置いた答えの来歴。
    public var answers: [String: ProvenanceID] = [:]
    /// 工程表で付けた技能(人 → 技能)。
    public var granted: [PersonID: [SkillID]] = [:]
    /// 使わなかった人(人 → 本人が断ったか)。
    public var declined: [PersonID: Bool] = [:]
    /// 仲間が自分で言った「含める(true)/ 含めない(false)」。
    public var declared: [PersonID: Bool] = [:]
    /// プレイヤーが決めた「含める / 含めない」。
    public var chosen: [PersonID: Bool] = [:]
    /// 選ぶ表を締めた来歴。
    public var locked: ProvenanceID?

    public init() {}

    /// 含めるか(プレイヤーの決定 → 本人の言い分 → 含めない)。
    public func included(_ p: PersonID) -> Bool { chosen[p] ?? declared[p] ?? false }
}
