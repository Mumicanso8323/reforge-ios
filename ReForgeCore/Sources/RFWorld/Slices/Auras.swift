import RFKernel

/// 範囲の効果。地図上の点・人・置いた物から半径 r の中で、仲間の振る舞いや数値が変わる共通の仕組み
/// (ある人の声の範囲で仲間が配属に従わない / ある人の近くで獣が寄らない / 炉の排気で近くの精神力が減る)。
/// 効果の中身(何がどう変わるか)はコンテンツの AuraDef。範囲は出来事で強まり・弱まり・消える。
/// 持ち主: 共通(付け外しは出来事の効果と、置いた物・人の定義から。読むのは各システム)。
public struct AuraState: Codable, Equatable, Sendable {
    public var active: [EntityID: Aura] = [:]

    public init() {}
}

public struct Aura: Codable, Equatable, Sendable {
    public enum Source: Codable, Equatable, Sendable {
        case point(WorldPoint)
        case person(PersonID)
        case placement(EntityID)
    }

    public var id: EntityID
    public var kind: AuraKindID
    public var source: Source
    public var radius: Int
    /// 強さ(千分率。1000 = 定義どおり。出来事で半分にできる)。
    public var strength: Int
    public var origin: ProvenanceID
    public var until: GameTime?

    public init(id: EntityID, kind: AuraKindID, source: Source, radius: Int, strength: Int = 1000,
                origin: ProvenanceID, until: GameTime? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
        self.radius = radius
        self.strength = strength
        self.origin = origin
        self.until = until
    }
}
