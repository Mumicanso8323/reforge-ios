import RFKernel
import RFMatter

extension PersonID {
    /// 主人公(固定)。
    public static let noah: PersonID = "person.noah"
}

/// ノア・仲間・まだ会っていない人。持ち主: RFCrew。
/// 仲間は地図上の実体で、位置を持ち、実際に歩き・運び・モジュールに付き・戦う。
public struct PeopleState: Codable, Equatable, Sendable {
    public var persons: [PersonID: PersonState] = [:]
    /// 表示と処理の順(決定的に回すため。辞書の順に頼らない)。
    public var order: [PersonID] = []
    /// 拠点の外の集団(R2〜R3: 接触・関係・縄張り・対立と和解)。ノアたちの拠点は集団に入れない。
    public var groups: [GroupID: GroupState] = [:]

    public init() {}

    public subscript(id: PersonID) -> PersonState? {
        get { persons[id] }
        set {
            if persons[id] == nil, newValue != nil, !order.contains(id) { order.append(id) }
            persons[id] = newValue
        }
    }

    /// 拠点の一員(ノアを含む)。
    public var members: [PersonID] { order.filter { persons[$0]?.presence.isMember == true } }
}

public enum Presence: Codable, Equatable, Sendable {
    /// まだ会っていない(存在は内部にだけある。総数は見せない)。
    case unmet
    /// 会ったが一員ではない(倒れていた人・他の集団の人)。
    case met(at: GameTime)
    case member(since: GameTime)
    /// 一時的にいない(遠征・離脱)。
    case away(since: GameTime)
    /// 死んだ。戻らない。来歴で死因を指す。
    case dead(at: GameTime, record: ProvenanceID?)

    public var isMember: Bool { if case .member = self { true } else { false } }
    public var isAlive: Bool { if case .dead = self { false } else { true } }
}

public struct PersonState: Codable, Equatable, Sendable {
    public var id: PersonID
    public var presence: Presence
    /// 地図上の位置(いない人は nil)。
    public var position: WorldPoint?
    public var facing: Direction = .south
    /// 歩いている途中(経路と、次のマスへの進み具合 0...1000)。
    public var motion: Motion?
    /// プレイヤーが決めた役割(運搬・モジュールに付く…)。
    public var assignment: Assignment = .idle
    /// 出来事・範囲の効果がプレイヤーの配属を上書きしているとき(その間 assignment は守られない)。
    public var override: AssignmentOverride?
    /// いま実際にしていること(役割から仲間が自分で決める。ノアはコマンドから)。
    public var activity: Activity = .idle
    public var body: BodyState = BodyState()
    /// ノアとの関係(ノア自身は使わない)。
    public var relation: RelationState = RelationState()
    /// 思想の傾き(軸 → 値)。判断への賛否の元。
    public var ideology: [IdeologyAxisID: Int] = [:]
    /// 記憶。巻き戻しをまたいで残るものがある。
    public var memories: [MemoryRecord] = []
    public var skills: Set<SkillID> = []
    /// 拠点の外の集団に属しているとき。
    public var group: GroupID?
    /// 装備(枠 → 物)。R1 は武器 1 枠だけ使う。
    public var equipment: [String: EquippedItem] = [:]

    public init(id: PersonID, presence: Presence) {
        self.id = id
        self.presence = presence
    }
}

/// 拠点の外の集団。
public struct GroupState: Codable, Equatable, Sendable {
    /// 拠点との関係(負は敵対)。
    public var relation: Int = 0
    /// 知っているか(見せるか)。
    public var known: Bool = false
    /// 縄張り(地表)。
    public var territory: GridRect?
    /// 集団の状態の印(コンテンツの ID 文字列。対立中・和解など)。
    public var flags: Set<String> = []

    public init() {}
}

/// 配属の上書き(「ある声の範囲の中の仲間が配属に従わず、その人物の方へ歩く」など)。
public struct AssignmentOverride: Codable, Equatable, Sendable {
    public var assignment: Assignment
    /// どの範囲の効果から来たか(範囲が消えれば上書きも消える)。出来事からなら nil。
    public var aura: EntityID?
    public var until: GameTime?
    public var origin: ProvenanceID

    public init(assignment: Assignment, aura: EntityID?, until: GameTime?, origin: ProvenanceID) {
        self.assignment = assignment
        self.aura = aura
        self.until = until
        self.origin = origin
    }
}

public struct Motion: Codable, Equatable, Sendable {
    /// これから進むマス(先頭が次のマス)。
    public var path: [GridPoint]
    /// 次のマスへの進み具合(千分率)。描画の補間にも使う。
    public var progress: Int

    public init(path: [GridPoint], progress: Int = 0) {
        self.path = path
        self.progress = progress
    }
}

/// プレイヤーが仲間に与える役割。
public enum Assignment: Codable, Equatable, Sendable {
    case idle
    /// 運搬の経路を担当する。
    case haul(route: EntityID)
    /// モジュール・研究机などに付く。
    case operate(placement: EntityID)
    /// 見張り(夜の脅威に備える)。
    case guardArea(center: WorldPoint, radius: Int)
    /// 建造を手伝う。
    case build(placement: EntityID)
    /// 採取を続ける(行為と場所)。
    case gather(interaction: InteractionID, at: WorldPoint)
    case follow(person: PersonID)
    case rest
}

/// いまの動作(描画と「誰が何をしているか」の表示に使う)。
public enum Activity: Codable, Equatable, Sendable {
    case idle
    case walking(to: WorldPoint)
    case working(at: EntityID)
    case carrying(route: EntityID)
    case interacting(interaction: InteractionID, at: WorldPoint, progress: Int)
    case fighting(battle: EntityID)
    case sleeping
    case talking(with: PersonID)
}

/// 体。値は千分率の固定小数。
public struct BodyState: Codable, Equatable, Sendable {
    public var health = Milli(100)
    public var stamina = Milli(100)
    /// 満腹(0 で空腹)。
    public var satiety = Milli(100)
    public var hydration = Milli(100)
    /// 精神力。外で減り、シェルターで戻る。
    public var mind = Milli(100)
    /// 負傷・病気などの状態(種類 → 重さ)。種類はコンテンツの ID。
    public var conditions: [StatID: Int] = [:]

    public init() {}
}

/// ノアとの関係。ランク 0...10、次のランクまでの点はコンテンツの式。
public struct RelationState: Codable, Equatable, Sendable {
    public var points: Int = 0
    public var rank: Int = 0

    public init() {}
}

/// 仲間の記憶 1 つ。about で来歴(あのとき起きたこと)を指す。
public struct MemoryRecord: Codable, Equatable, Sendable {
    public var kind: MemoryKindID
    public var at: GameTime
    /// どの周回で得たか(巻き戻しの後も残る記憶は、前の周回の番号のまま)。
    public var run: Int
    public var about: ProvenanceID?
    /// 巻き戻しをまたいで残るか。
    public var persistsAcrossRewind: Bool

    public init(kind: MemoryKindID, at: GameTime, run: Int, about: ProvenanceID?, persistsAcrossRewind: Bool) {
        self.kind = kind
        self.at = at
        self.run = run
        self.about = about
        self.persistsAcrossRewind = persistsAcrossRewind
    }
}

public struct EquippedItem: Codable, Equatable, Sendable {
    public var stuff: Stuff
    public var origin: ProvenanceID?
    /// 減ったら戻らない品の残り(千分率)。
    public var durability: Milli?

    public init(stuff: Stuff, origin: ProvenanceID?, durability: Milli? = nil) {
        self.stuff = stuff
        self.origin = origin
        self.durability = durability
    }
}
