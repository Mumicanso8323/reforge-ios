import RFKernel

/// 地図上の脅威と、進行中の戦闘。持ち主: RFCombat。
public struct CombatState: Codable, Equatable, Sendable {
    public var threats: [EntityID: ThreatState] = [:]
    public var battles: [EntityID: BattleState] = [:]

    public init() {}
}

/// 地図上の敵 1 体(群れは数で持つ)。
public struct ThreatState: Codable, Equatable, Sendable {
    public var id: EntityID
    public var kind: EnemyKindID
    public var position: WorldPoint
    public var count: Int
    public var health: Milli
    /// 何を狙っているか(食料庫・人…)。コンテンツの ID 文字列。
    public var intent: String
    public var motion: Motion?

    public init(id: EntityID, kind: EnemyKindID, position: WorldPoint, count: Int, health: Milli, intent: String) {
        self.id = id
        self.kind = kind
        self.position = position
        self.count = count
        self.health = health
        self.intent = intent
    }
}

/// 1 次元の自動戦闘(6 マスの帯)。プレイヤーが選ぶのは方針と撤退だけ。
public struct BattleState: Codable, Equatable, Sendable {
    public enum Stance: String, Codable, Sendable { case advance, keepDistance }

    public var id: EntityID
    public var participants: [PersonID]
    public var enemies: [EntityID]
    /// 帯の上の位置(参加者・敵 → 0...5)。
    public var lane: [String: Int]
    public var stance: Stance
    public var retreating: Bool
    public var elapsed: Int64
    /// 始まりの来歴(勝ち負けの記録の inputs になる)。
    public var origin: ProvenanceID

    public init(id: EntityID, participants: [PersonID], enemies: [EntityID], origin: ProvenanceID) {
        self.id = id
        self.participants = participants
        self.enemies = enemies
        self.lane = [:]
        self.stance = .keepDistance
        self.retreating = false
        self.elapsed = 0
        self.origin = origin
    }
}
