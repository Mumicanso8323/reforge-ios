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

    public init() {}
}

public struct FiredRecord: Codable, Equatable, Sendable {
    public var count: Int
    public var lastAt: GameTime
    /// 発火の来歴(効果で起きた変化の inputs になる)。
    public var lastRecord: ProvenanceID?

    public init(count: Int, lastAt: GameTime, lastRecord: ProvenanceID?) {
        self.count = count
        self.lastAt = lastAt
        self.lastRecord = lastRecord
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

    public init(event: EventID, at: GameTime) {
        self.event = event
        self.at = at
    }
}

public enum ObjectiveStatus: String, Codable, Sendable { case active, done, failed }

public struct SceneProgress: Codable, Equatable, Sendable {
    public var scene: SceneID
    public var line: Int

    public init(scene: SceneID, line: Int = 0) {
        self.scene = scene
        self.line = line
    }
}
