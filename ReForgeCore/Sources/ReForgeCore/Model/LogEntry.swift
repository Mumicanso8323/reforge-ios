/// 日誌の 1 行。文言は JournalText が組み立てる(文字列を保存しないので後から多言語化できる)。
public struct LogEntry: Codable, Equatable, Sendable {
    public var day: Int
    public var event: LogEvent

    public init(day: Int, event: LogEvent) {
        self.day = day
        self.event = event
    }
}

public enum LogEvent: Codable, Equatable, Sendable {
    case newGame
    case gathered(GatherKind, gains: [ItemAmount], scavengeLeft: Int?)
    case crafted(RecipeID, times: Int, output: ItemAmount)
    case built(BuildingID)
    case restedDay
    /// 夜が明けた。終わった日の集計つき。
    case dawn(DawnReport)
    case victory
    case gameOver(FailureReason)
    case rewound(carried: [ItemAmount])
    case continuedWithLoss(lostCompanions: [String], lostItems: [ItemAmount])
    case loadedSavePoint(day: Int)
    case manualSave
}
