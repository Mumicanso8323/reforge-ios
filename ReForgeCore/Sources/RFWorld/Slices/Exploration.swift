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
    /// 出来事の表を引き終えた区画(層 → 区画の格子のビット列)。
    public var exploredRegions: [LayerID: GridBitset] = [:]
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

    public init() {}

    /// 回数・クールダウンのキー(行為 × 場所)。POI なら場所の代わりに POI の実体。
    public static func countKey(_ interaction: InteractionID, poi: EntityID?, at p: WorldPoint) -> String {
        if let poi { return "\(interaction.rawValue)|poi:\(poi.raw)" }
        return "\(interaction.rawValue)|\(p.layer.rawValue)|\(p.point.x),\(p.point.y)"
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
