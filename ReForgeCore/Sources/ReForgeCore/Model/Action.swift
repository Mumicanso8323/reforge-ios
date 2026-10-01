/// 採取の種類(§6.3)。
public enum GatherKind: String, Codable, CaseIterable, Equatable, Sendable {
    case food, water, wood, stone, ore, scavenge
}

/// プレイヤーの行動。
public enum Action: Equatable, Sendable {
    case gather(GatherKind)
    /// 製作を times 回(1 回 1 行動ポイント)。
    case craft(RecipeID, times: Int)
    case build(BuildingID)
    /// 休む。昼は残りの行動を捨てて日没へ。夜は「寝る」と同じ。
    case rest

    /// 採取・建造は外での作業(夜はできない)。
    public var isOutdoor: Bool {
        switch self {
        case .gather, .build: true
        case .craft, .rest: false
        }
    }
}

public enum ActionError: Error, Equatable, Sendable {
    /// その時間帯にはできない。
    case notAllowed(Phase)
    case noActionPoints
    /// 材料が足りない。items はどれか 1 つでよい候補(「石炭か木炭」)。have は候補の合計。
    case insufficient([ItemID], have: Int, need: Int)
    /// どれか 1 つが要る。
    case needsBuilding([BuildingID])
    case alreadyBuilt(BuildingID)
    case scavengeExhausted
    /// 焚き火台の無い夜は作業できない。
    case noFireAtNight
    case gameNotActive
    case invalidQuantity
    case unknown
}
