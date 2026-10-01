import RFKernel

/// POI を調べた進み具合。持ち主: RFExploration。
public struct ExplorationState: Codable, Equatable, Sendable {
    public var poi: [EntityID: POIProgress] = [:]
    /// 行為ごとの回数(残骸を漁った回数など。上限はコンテンツ)。
    public var interactionCounts: [String: Int] = [:]

    public init() {}
}

public struct POIProgress: Codable, Equatable, Sendable {
    public var visits: Int = 0
    /// 調べ尽くした・遺品を取ったなどの印(コンテンツの ID 文字列)。
    public var flags: Set<String> = []
    /// 有限の部品(残骸の区画など)。部品の名前 → 状態。取り外し・解体・作り直しは来歴に残る。
    public var parts: [String: PartState] = [:]

    public init() {}
}

/// 有限で戻らない部品の状態。
public enum PartState: Codable, Equatable, Sendable {
    case intact
    /// 漁った・取り外した(使える物を取った)。
    case salvaged(record: ProvenanceID)
    /// 解体した(材料にした)。後で作り直しを求められることがある。
    case dismantled(record: ProvenanceID)
    /// 自分の工業で作り直した。
    case rebuilt(record: ProvenanceID)
}
