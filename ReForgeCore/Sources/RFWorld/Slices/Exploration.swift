import RFKernel

/// 探索の進み具合。持ち主: RFExploration。
///
/// - POI ごとの進み(訪れた回数・印・有限の部品の状態・修理の段階)。
/// - 進行中の行為(漁る・汲む・掘る・解体する…)。昼は固定ステップで進み、終わると得られる物が入る。
/// - 探索の出来事の表を引いた区画・一度きりの出来事・探索範囲(拠点からどこまで行ったか)。
/// - 採集のクールダウン(マス × 行為 → 最後に取った日)。
public struct ExplorationState: Codable, Equatable, Sendable {
    public var poi: [EntityID: POIProgress] = [:]
    /// 行為ごとの回数(残骸を漁った回数など。上限はコンテンツ)。キーは `ExplorationState.countKey`。
    public var interactionCounts: [String: Int] = [:]
    /// 進行中の行為(人 → 行為)。
    public var active: [PersonID: ActiveInteraction] = [:]
    /// 採集した日(キー `ExplorationState.countKey` → 日)。クールダウンの判定に使う。
    public var harvestedDay: [String: Int] = [:]
    /// 出来事の表を引き終えた区画(`ExplorationState.regionKey`(層 × 場)→ 区画の格子のビット列)。
    public var exploredRegions: [String: GridBitset] = [:]
    /// 探索の出来事が起きた回数(一度きりの判定にも使う)。
    public var exploreFired: [EventID: Int] = [:]
    /// 前のステップでいた場所(歩いて入ったことの判定)。
    public var lastPositions: [PersonID: WorldPoint] = [:]
    /// いまそばにいる POI(入った・出たの判定)。
    public var nearPOI: [PersonID: EntityID] = [:]
    /// 拠点の中心から最も遠くまで行った距離(マス。チェビシェフ)。
    public var farthest: Int = 0
    /// 探索範囲(1 から。原作 ExplorationRange)。出来事・場の解放に使う。
    public var range: Int = 1
    /// 地図の光の点(id → 位置。効果 beacon が置く。U19)。古いセーブには無い(空で読む)。
    public var beacons: [String: WorldPoint] = [:]
    /// 続けて採る(PT-B1)で、仲間が移った先の「配属の時の場所」(人 → 起点)。移った人がいる間だけ持つ。
    /// nil(空)の間は保存に書かない(保存の形は変えない)。
    public var continueHome: [PersonID: ContinueHome]?
    /// 続けて採っていたノアが「近くにもう無い」で止まった印(次に行為を始めると消える)。nil は書かない。
    public var continueStop: ContinueStop?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case poi, interactionCounts, active, harvestedDay, exploredRegions, exploreFired, lastPositions, nearPOI
        case farthest, range, beacons, continueHome, continueStop
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poi = try c.decode([EntityID: POIProgress].self, forKey: .poi)
        interactionCounts = try c.decode([String: Int].self, forKey: .interactionCounts)
        active = try c.decode([PersonID: ActiveInteraction].self, forKey: .active)
        harvestedDay = try c.decode([String: Int].self, forKey: .harvestedDay)
        exploredRegions = try c.decode([String: GridBitset].self, forKey: .exploredRegions)
        exploreFired = try c.decode([EventID: Int].self, forKey: .exploreFired)
        lastPositions = try c.decode([PersonID: WorldPoint].self, forKey: .lastPositions)
        nearPOI = try c.decode([PersonID: EntityID].self, forKey: .nearPOI)
        farthest = try c.decode(Int.self, forKey: .farthest)
        range = try c.decode(Int.self, forKey: .range)
        beacons = try c.decodeIfPresent([String: WorldPoint].self, forKey: .beacons) ?? [:]
        continueHome = try c.decodeIfPresent([PersonID: ContinueHome].self, forKey: .continueHome)
        continueStop = try c.decodeIfPresent(ContinueStop.self, forKey: .continueStop)
    }

    /// 区画のビット列のキー(層 × 場。場の無い地形は "-")。
    public static func regionKey(_ layer: LayerID, field: String?) -> String { "\(layer.rawValue)|\(field ?? "-")" }

    /// 回数・クールダウンのキー(行為 × 場所)。POI なら場所の代わりに POI の実体。
    public static func countKey(_ interaction: InteractionID, poi: EntityID?, at p: WorldPoint) -> String {
        if let poi { return "\(interaction.rawValue)|poi:\(poi.raw)" }
        return "\(interaction.rawValue)|\(p.layer.rawValue)|\(p.point.x),\(p.point.y)"
    }

    /// countKey の逆(マスの鍵だけ。POI の鍵は nil)。行為の ID とマスを返す。
    public static func point(fromKey key: String) -> (interaction: InteractionID, at: WorldPoint)? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].hasPrefix("poi:") else { return nil }
        let xy = parts[2].split(separator: ",")
        guard xy.count == 2, let x = Int(xy[0]), let y = Int(xy[1]) else { return nil }
        return (InteractionID(rawValue: String(parts[0])), WorldPoint(LayerID(rawValue: String(parts[1])), GridPoint(x, y)))
    }
}

/// 続けて採る仲間の起点(配属の時の場所)。cell は移った先(今の配属のマスと違えば古いので使わない)。
public struct ContinueHome: Codable, Equatable, Sendable {
    public var origin: WorldPoint
    public var cell: WorldPoint

    public init(origin: WorldPoint, cell: WorldPoint) {
        self.origin = origin
        self.cell = cell
    }
}

/// 続けて採るのが「近くにもう無い」で止まった印。
public struct ContinueStop: Codable, Equatable, Sendable {
    public var interaction: InteractionID
    public var at: WorldPoint
    /// 止まった日。日が変われば印は出さない(古い保存は nil で、そのまま出す)。
    public var day: Int?

    public init(interaction: InteractionID, at: WorldPoint, day: Int? = nil) {
        self.interaction = interaction
        self.at = at
        self.day = day
    }
}

public struct POIProgress: Codable, Equatable, Sendable {
    public var visits: Int = 0
    /// 調べ尽くした・遺品を取ったなどの印(コンテンツの ID 文字列)。
    public var flags: Set<String> = []
    /// 有限の部品(残骸の区画など)。部品の名前 → 状態。取り外し・解体・作り直しは来歴に残る。
    public var parts: [String: PartState] = [:]
    /// 部品の修理の段階(部品の名前 → 段階。0 = 壊れたまま)。段階ごとに機能が開く(BEAT-09)。
    public var repair: [String: Int] = [:]

    public init() {}

    public func part(_ name: String) -> PartState { parts[name] ?? .intact }
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

    /// この状態にした来歴(無傷なら nil)。
    public var record: ProvenanceID? {
        switch self {
        case .intact: nil
        case .salvaged(let r), .dismantled(let r), .rebuilt(let r): r
        }
    }
}

/// 進行中の行為 1 つ。
public struct ActiveInteraction: Codable, Equatable, Sendable {
    public var interaction: InteractionID
    /// 向けたマス。
    public var at: WorldPoint
    /// 対象の POI(POI に向けた行為なら)。
    public var poi: EntityID?
    /// 対象の部品(有限の部品の操作なら)。
    public var part: String?
    /// 進んだゲーム秒。
    public var progress: Int64 = 0
    /// 押し続ける行為で、いま押しているか。
    public var holding: Bool
    /// 始めたときに使った材料の来歴(作り直しの記録の inputs)。取りやめたら戻す。
    public var spent: [CostLot] = []
    public var startedAt: GameTime

    public init(interaction: InteractionID, at: WorldPoint, poi: EntityID?, part: String?, holding: Bool,
                spent: [CostLot], startedAt: GameTime) {
        self.interaction = interaction
        self.at = at
        self.poi = poi
        self.part = part
        self.holding = holding
        self.spent = spent
        self.startedAt = startedAt
    }
}

/// 使った材料 1 山(取りやめたときに同じ来歴で戻すため)。
public struct CostLot: Codable, Equatable, Sendable {
    public var stuff: Stuff
    public var origins: [ProvenanceID: Int]

    public init(stuff: Stuff, origins: [ProvenanceID: Int]) {
        self.stuff = stuff
        self.origins = origins
    }
}

/// 有限の部品と POI のマスの対応(画面も使う)。parts[i] ↔ 占めるマスを (y, x) の昇順に並べた i 番目
/// (足りない分はマスを持たない)。
public enum PlacementPartIndex {
    /// マス(POI の at からの相対)に当たる部品の名前。
    public static func part(atOffset off: GridPoint, footprint: [GridPoint], parts: [String]) -> String? {
        guard let i = footprint.sorted().firstIndex(of: off), i < parts.count else { return nil }
        return parts[i]
    }

    /// 部品のマス(POI の at からの相対)。マスを持たない部品は nil。
    public static func offset(of part: String, footprint: [GridPoint], parts: [String]) -> GridPoint? {
        guard let i = parts.firstIndex(of: part), i < footprint.count else { return nil }
        return footprint.sorted()[i]
    }
}
