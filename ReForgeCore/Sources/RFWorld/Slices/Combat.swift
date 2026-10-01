import RFKernel

/// 地図上の脅威と、進行中の戦闘。持ち主: RFCombat。
///
/// - 脅威(ThreatState)は地図の上の実体。夜に灯りの外から食料を狙って来る・森で人を見つけて寄って来る・巣を守る。
/// - 戦闘(BattleState)は 1 次元の帯(既定 6 マス)で、手番ごとに自動で進む。プレイヤーが選ぶのは方針と撤退だけ。
/// - 文章は持たない。何が起きたかは来歴(倒した・逃げた・奪われた)と、帯の上の直近の手(beats)の数だけ。
public struct CombatState: Codable, Equatable, Sendable {
    public var threats: [EntityID: ThreatState] = [:]
    public var battles: [EntityID: BattleState] = [:]
    /// 巣(地図の POI の実体)の状態。壊したか・守りが出たか。
    public var nests: [EntityID: NestState] = [:]
    /// 今夜これから来る獣(日没に決める。時刻が来たら地図に出る)。
    public var plannedRaids: [PlannedRaid] = []
    /// 作動して、夜明けまで効かない罠(置いた物の実体)。
    public var sprungTraps: Set<EntityID> = []
    /// 戦闘が始まったときの方針(寝ている間の戦闘もこれで進む)。
    public var defaultStance: BattleState.Stance = .keepDistance
    /// 種類ごとの倒した数(来歴が正。画面と敵の拡大(R2)の読みやすい写し)。
    public var kills: [EnemyKindID: Int] = [:]
    /// 終わったばかりの戦闘(帯に結果を残す。次の戦闘が始まるか夜明けで消える)。
    public var lastBattle: BattleState?
    /// 今夜の集計(日没で 0 に戻す。夜明けの要約の材料)。
    public var night = NightTally()

    public init() {}

    /// その人がいま入っている戦闘。
    public func battle(of person: PersonID) -> BattleState? {
        battles.values.sorted { $0.id < $1.id }.first { $0.participants.contains(person) }
    }
}

/// 地図上の敵の群れ 1 つ(群れは数で持つ)。
public struct ThreatState: Codable, Equatable, Sendable {
    /// 何をしに来たか。
    public enum Intent: Codable, Equatable, Sendable {
        /// 食料を狙って target(蓄えの場所)へ向かう。
        case raid(target: WorldPoint)
        /// 人を見つけて寄って来る(森の近道など)。
        case hunt(person: PersonID)
        /// 巣を守る(動かない)。
        case guardNest(poi: EntityID)
        /// うろつく(効果で出した獣の既定)。
        case roam
    }

    public var id: EntityID
    public var kind: EnemyKindID
    public var position: WorldPoint
    public var count: Int
    /// 群れの残りの体力の合計(戦闘で減った分は残る)。
    public var hp: Int
    public var intent: Intent
    /// 歩いている道(先頭が次のマス)。progress は使わず、moveCarry で進む。
    public var motion: Motion?
    /// 1 マス進むまでの貯め(マス毎時 × ゲーム秒。3600 で 1 マス)。
    public var moveCarry: Int = 0
    /// 夜明けに帰るか。
    public var nocturnal: Bool
    /// この時刻までは人に寄らない(負かした・逃げられた直後)。
    public var calmUntil: GameTime?
    /// 出てきた巣(あれば)。
    public var nest: EntityID?
    /// 出した効果の引き金(あれば)。
    public var origin: ProvenanceID?

    public init(id: EntityID, kind: EnemyKindID, position: WorldPoint, count: Int, hp: Int, intent: Intent,
                nocturnal: Bool, nest: EntityID? = nil, origin: ProvenanceID? = nil) {
        self.id = id
        self.kind = kind
        self.position = position
        self.count = count
        self.hp = hp
        self.intent = intent
        self.nocturnal = nocturnal
        self.nest = nest
        self.origin = origin
    }
}

/// 1 次元の自動戦闘(既定 6 マスの帯)。味方が左(0 側)、敵が右。プレイヤーが選ぶのは方針と撤退だけ。
public struct BattleState: Codable, Equatable, Sendable {
    public enum Stance: String, Codable, Sendable {
        /// 前に出る: 間合いを詰めて打つ。与える傷も受ける傷も増える。
        case advance
        /// 距離を取る: 武器の届く一番遠い間合いを保つ(届かない武器なら、来るのを待って先に打つ)。
        case keepDistance
    }

    /// どこで・何の戦いか。
    public enum Kind: Codable, Equatable, Sendable {
        /// 拠点の蓄えを狙って来た獣と(負ければ奪われる)。
        case raid(target: WorldPoint)
        /// 外で出会った(森の近道・見張りが見つけた)。
        case encounter
        /// 巣を守る獣と(勝てば巣が壊れる)。
        case nest(poi: EntityID)
    }

    public enum Outcome: String, Codable, Sendable { case won, lost, fled }

    public var id: EntityID
    public var kind: Kind
    /// 地図の上の場所(画面はここを指す)。
    public var at: WorldPoint
    public var laneSize: Int
    public var participants: [PersonID]
    /// 加わっている脅威(地図の実体)。
    public var enemies: [EntityID]
    public var units: [BattleUnit]
    public var stance: BattleState.Stance
    public var retreating: Bool
    /// 進んだ手番の数。
    public var turn: Int
    /// 次の手番の時刻。
    public var nextTurnAt: GameTime
    public var startedAt: GameTime
    /// 経過(ゲーム秒)。
    public var elapsed: Int64
    /// 始まりの来歴(勝ち負けの記録の inputs になる)。
    public var origin: ProvenanceID
    /// 倒れた人が死ぬ戦いか(R1 の獣は false。R3 の拠点の外の集団との戦いで true。死者は戻らない)。
    public var lethal: Bool
    /// 直近の手番に起きたこと(帯の描画用。文は持たない)。
    public var beats: [BattleBeat]
    /// 終わったときだけ入る。
    public var outcome: Outcome?

    public init(id: EntityID, kind: Kind, at: WorldPoint, laneSize: Int, participants: [PersonID], enemies: [EntityID],
                units: [BattleUnit], stance: Stance, startedAt: GameTime, firstTurnAt: GameTime, origin: ProvenanceID,
                lethal: Bool = false) {
        self.id = id
        self.kind = kind
        self.at = at
        self.laneSize = laneSize
        self.participants = participants
        self.enemies = enemies
        self.units = units
        self.stance = stance
        self.retreating = false
        self.turn = 0
        self.nextTurnAt = firstTurnAt
        self.startedAt = startedAt
        self.elapsed = 0
        self.origin = origin
        self.lethal = lethal
        self.beats = []
    }
}

/// 帯の上の 1 体(人か敵)。
public struct BattleUnit: Codable, Equatable, Sendable {
    public enum Ref: Codable, Equatable, Sendable {
        case person(PersonID)
        /// 群れ(threat)の index 番目の 1 体。
        case enemy(threat: EntityID, kind: EnemyKindID, index: Int)
    }

    public enum Side: String, Codable, Sendable { case allies, enemies }

    public enum State: String, Codable, Sendable {
        case active
        /// 倒れて帯から外れた(人)。
        case down
        /// 撤退で抜けた。
        case escaped
        /// 死んだ(敵は倒された。人は lethal の戦いだけ)。
        case dead
    }

    public var ref: Ref
    public var side: Side
    /// 帯の上の位置(0...laneSize-1)。
    public var position: Int
    public var hp: Int
    public var maxHP: Int
    public var attack: Int
    public var defense: Int
    public var speed: Int
    /// 武器の届く間合い(帯のマス数。0 = 同じマスだけ)。
    public var reachMin: Int
    public var reachMax: Int
    public var state: State = .active
    public var damageTaken: Int = 0
    public var kills: Int = 0
    /// 使っている武器の来歴(あの剛鉄で作った槍、を後で指せる)。
    public var weaponOrigin: ProvenanceID?
    /// 状態異常・部位の傷(R2: 出血・骨折など。種類 → 重さ)。R1 は空。
    public var status: [String: Int] = [:]

    public init(ref: Ref, side: Side, position: Int, hp: Int, maxHP: Int, attack: Int, defense: Int, speed: Int,
                reachMin: Int, reachMax: Int, weaponOrigin: ProvenanceID? = nil) {
        self.ref = ref
        self.side = side
        self.position = position
        self.hp = hp
        self.maxHP = maxHP
        self.attack = attack
        self.defense = defense
        self.speed = speed
        self.reachMin = reachMin
        self.reachMax = reachMax
        self.weaponOrigin = weaponOrigin
    }

    public var isActive: Bool { state == .active }
    public var person: PersonID? { if case .person(let p) = ref { p } else { nil } }
}

/// 手番の中の 1 手(units の添字で指す)。
public struct BattleBeat: Codable, Equatable, Sendable {
    public enum Act: String, Codable, Sendable { case hit, miss, move, escape, caught }

    public var actor: Int
    public var target: Int?
    public var act: Act
    public var damage: Int
    public var critical: Bool

    public init(actor: Int, target: Int?, act: Act, damage: Int = 0, critical: Bool = false) {
        self.actor = actor
        self.target = target
        self.act = act
        self.damage = damage
        self.critical = critical
    }
}

/// 巣の状態。
public struct NestState: Codable, Equatable, Sendable {
    /// 壊した記録(壊れていなければ nil)。
    public var destroyed: ProvenanceID?
    /// 守りの獣が出ている脅威。
    public var guardThreat: EntityID?

    public init(destroyed: ProvenanceID? = nil, guardThreat: EntityID? = nil) {
        self.destroyed = destroyed
        self.guardThreat = guardThreat
    }
}

/// 今夜来る予定の群れ。
public struct PlannedRaid: Codable, Equatable, Sendable {
    public var kind: EnemyKindID
    public var count: Int
    public var at: GameTime
    /// 出てくる巣(無ければ灯りの外の遠いマスから)。
    public var nest: EntityID?

    public init(kind: EnemyKindID, count: Int, at: GameTime, nest: EntityID?) {
        self.kind = kind
        self.count = count
        self.at = at
        self.nest = nest
    }
}

/// 一晩の集計。
public struct NightTally: Codable, Equatable, Sendable {
    public var raids = 0
    public var battles = 0
    public var kills = 0
    /// 奪われた物(物の ID → 数)。
    public var stolen: [ItemID: Int] = [:]
    public var injured: [PersonID] = []

    public init() {}
}
