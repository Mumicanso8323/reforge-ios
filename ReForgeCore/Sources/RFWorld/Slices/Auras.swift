import RFKernel

/// 範囲の効果。地図上の点・人・置いた物から半径 r の中で、仲間の振る舞いや数値が変わる共通の仕組み
/// (ある人の範囲で仲間が配属に従わず中心へ歩く / ある人の近くで敵が寄らない / ある置いた物の近くで数値が減る)。
/// 効果の中身(何がどう変わるか)はコンテンツの AuraDef。範囲は出来事で付き・強まり・弱まり・縮み・消える。
/// 持ち主: U11(付け外しは効果と、置いた物・人の定義から。毎ステップの整理は RFRules.Auras.maintain。読むのは各システム)。
public struct AuraState: Codable, Equatable, Sendable {
    public var active: [EntityID: Aura] = [:]
    /// 種類ごとの掛け率(効果 scaleAura)。これから付く範囲(定義から付くもの)にも効く。
    public var kindScale: [AuraKindID: AuraScale] = [:]

    public init() {}
}

/// 種類ごとの掛け率(千分率)。
public struct AuraScale: Codable, Equatable, Sendable {
    public var strength: Int
    public var radius: Int

    public init(strength: Int = 1000, radius: Int = 1000) {
        self.strength = strength
        self.radius = radius
    }
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
    /// 置いた物・人の定義から付いた範囲(中心が消えれば一緒に消える)。出来事から付いたものは nil。
    public var fromDefinition: Bool?

    public init(id: EntityID, kind: AuraKindID, source: Source, radius: Int, strength: Int = 1000,
                origin: ProvenanceID, until: GameTime? = nil, fromDefinition: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
        self.radius = radius
        self.strength = strength
        self.origin = origin
        self.until = until
        self.fromDefinition = fromDefinition
    }
}
