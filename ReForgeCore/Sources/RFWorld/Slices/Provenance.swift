import RFKernel
import RFMatter

/// 来歴。プレイヤーが作った物・置いた物・選んだこと・倒した相手・失った仲間などを、誰が・いつ・何を・どこで・
/// 何から、の構造で残す(文章のログではない)。後の開示・条件・仲間の記憶・日誌は、ここを問い合わせて
/// 「あのとき自分がしたこと」を指す。
///
/// - 追記のみ。書き換えるのは tags(後から意味が付く: 効果 reinterpret)と count(同じ行為の繰り返しをまとめる)だけ。
/// - ラインの生産は 1 個ずつ記録しない。置いたモジュールの produced 記録 1 件の count を増やす。
/// - 巻き戻しで世界状態ごと夜明けに戻る。前の周回で覚えておくもの(memorable の印)は RunState.pastLives に写す。
public struct ProvenanceLedger: Codable, Equatable, Sendable {
    public private(set) var records: [ProvenanceRecord] = []
    public private(set) var nextID: Int = 1
    /// 「工業の初めて」の索引(行為 × 対象の種類 → 最初の記録)。初めて作った・建てた・配属した・解体した・観測した。
    public private(set) var firsts: [String: ProvenanceID] = [:]

    public init() {}

    /// 行為 × 対象の種類の鍵(実体の番号は見ない)。
    public static func firstKey(_ act: ActKind, _ subject: SubjectRef) -> String { "\(act.rawValue)|\(subject.kindKey)" }

    public func first(_ act: ActKind, _ subject: SubjectRef) -> ProvenanceID? { firsts[Self.firstKey(act, subject)] }

    /// どの来歴とも結び付かない物(初期の持ち物など)。
    public static let unknownOrigin = ProvenanceID(0)

    @discardableResult
    public mutating func append(_ make: (ProvenanceID) -> ProvenanceRecord) -> ProvenanceID {
        let id = ProvenanceID(nextID)
        nextID += 1
        let r = make(id)
        records.append(r)
        let key = Self.firstKey(r.act, r.subject)
        if firsts[key] == nil { firsts[key] = id }
        return id
    }

    public func record(_ id: ProvenanceID) -> ProvenanceRecord? {
        // ID は 1 から連番で records の順と一致する(巻き戻しで切り詰めても先頭からの順は崩れない)
        let i = id.raw - (records.first?.id.raw ?? 1)
        guard i >= 0, i < records.count, records[i].id == id else { return records.first { $0.id == id } }
        return records[i]
    }

    /// 番号を先へ進める(巻き戻しの後、前の周回の記録と番号を重ねないため)。
    public mutating func continueNumbering(after other: ProvenanceLedger) {
        nextID = max(nextID, other.nextID)
    }

    public mutating func update(_ id: ProvenanceID, _ body: (inout ProvenanceRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        body(&records[i])
    }

    /// 来歴の木を下る: id を入力に使って生まれた記録をすべて(推移的に)。「あのとき作った鉄から作られた物」。
    public func descendants(of id: ProvenanceID) -> [ProvenanceRecord] {
        var frontier: Set<ProvenanceID> = [id]
        var out: [ProvenanceRecord] = []
        for r in records where r.id > id {
            if !frontier.isDisjoint(with: r.inputs) {
                out.append(r)
                frontier.insert(r.id)
            }
        }
        return out
    }
}

public struct ProvenanceRecord: Codable, Equatable, Sendable {
    public var id: ProvenanceID
    public var at: GameTime
    public var day: Int
    public var run: Int
    /// 誰がしたか(仲間の自動の行為なら仲間、出来事が起こしたなら nil)。
    public var actor: PersonID?
    public var act: ActKind
    /// 何を。
    public var subject: SubjectRef
    public var place: WorldPoint?
    /// 何から(材料の来歴・試作の来歴など)。
    public var inputs: [ProvenanceID]
    /// 印(コンテンツが付ける。後の開示が指す単位)。
    public var tags: Set<ProvenanceTag>
    /// 同じ行為をまとめた回数(ラインの生産数など)。
    public var count: Int
    /// 行為ごとの詳細(純度・選んだ方針など)。
    public var detail: [String: Value]

    public init(id: ProvenanceID, at: GameTime, day: Int, run: Int, actor: PersonID?, act: ActKind,
                subject: SubjectRef, place: WorldPoint? = nil, inputs: [ProvenanceID] = [],
                tags: Set<ProvenanceTag> = [], count: Int = 1, detail: [String: Value] = [:]) {
        self.id = id
        self.at = at
        self.day = day
        self.run = run
        self.actor = actor
        self.act = act
        self.subject = subject
        self.place = place
        self.inputs = inputs
        self.tags = tags
        self.count = count
        self.detail = detail
    }
}

/// 来歴が指す対象。
public enum SubjectRef: Codable, Hashable, Sendable {
    case none
    case item(ItemID)
    /// 物質(名前の部品で指す: 「精鉄板」を初めて作った、など)。
    case matter(MatterName)
    case entity(EntityID)
    case module(ModuleKindID, EntityID?)
    case structure(StructureKindID, EntityID?)
    case person(PersonID)
    case design(EntityID)
    case enemy(EnemyKindID, EntityID?)
    case poi(POIKindID, EntityID?)
    case event(EventID)
    case choice(EventID, ChoiceID)
    case fact(FactID)
    case research(ResearchID)
    case skill(SkillID)
    case interaction(InteractionID)
    /// 有限の部品(残骸の区画など): 地点 + 部品の名前。
    case part(EntityID, String)
    case sheet(SheetID)
    case aura(AuraKindID, EntityID?)
    /// 能力(使った・効いた)。
    case ability(AbilityID)

    /// 種類の鍵(「初めて」の判定用。実体の番号を除く)。
    public var kindKey: String {
        switch self {
        case .none: "none"
        case .item(let k): "item:\(k)"
        case .matter(let n): "matter:\(n.parts.map { "\($0)" }.joined(separator: "/"))"
        case .entity: "entity"
        case .module(let k, _): "module:\(k)"
        case .structure(let k, _): "structure:\(k)"
        case .person(let p): "person:\(p)"
        case .design: "design"
        case .enemy(let k, _): "enemy:\(k)"
        case .poi(let k, _): "poi:\(k)"
        case .event(let e): "event:\(e)"
        case .choice(let e, let c): "choice:\(e):\(c)"
        case .fact(let f): "fact:\(f)"
        case .research(let r): "research:\(r)"
        case .skill(let s): "skill:\(s)"
        case .interaction(let i): "interaction:\(i)"
        case .part(_, let name): "part:\(name)"
        case .sheet(let s): "sheet:\(s)"
        case .aura(let k, _): "aura:\(k)"
        case .ability(let a): "ability:\(a)"
        }
    }
}
