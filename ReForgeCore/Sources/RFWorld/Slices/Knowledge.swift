import RFKernel

/// プレイヤー(ノアたち)が知っていること。持ち主: 共通(書き込みは StepContext.learn / 地図の既知は RFCrew の視界)。
///
/// 認識の層はここだけを見て名前・説明・数値の見せ方を決める。事実を 1 つ知るだけで、
/// 既に作った物・置いた物・図鑑・地図の名前が書き換わる(名前は保存していないので)。
/// 巻き戻しでは、コンテンツが scope = memory とした事実・地図の既知・発見を持ち越す。
public struct KnowledgeState: Codable, Equatable, Sendable {
    public var facts: [FactID: FactRecord] = [:]
    /// 地図の既知(一度でも見たマス)。層ごと。
    public var mapKnown: [LayerID: GridBitset] = [:]
    /// 見つけた POI・鉱脈。
    public var discovered: Set<EntityID> = []
    /// 一度でも見た・触れた対象(図鑑の「影」を出すかどうか)。
    public var seen: Set<SubjectID> = []

    public init() {}

    public var factSet: Set<FactID> { Set(facts.keys) }
    public func knows(_ f: FactID) -> Bool { facts[f] != nil }
}

public struct FactRecord: Codable, Equatable, Sendable {
    public var learnedAt: GameTime
    public var run: Int
    /// どの行為・出来事で知ったか。
    public var via: ProvenanceID?

    public init(learnedAt: GameTime, run: Int, via: ProvenanceID?) {
        self.learnedAt = learnedAt
        self.run = run
        self.via = via
    }
}
