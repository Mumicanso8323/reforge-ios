import RFKernel
import RFMap
import RFMatter

// 探索と拠点の定義(持ち主: U8)。E-content.md §2 の `fields`・`exploreEvents`・`exploration`・`base`、
// と InteractionDef・StructureDef・Yield に足した省略可能な項目の型。本文は持たない(TextID・SceneID で指す)。

public enum FieldTag {}
/// 探索の場(原作 `FieldType`: 平原・川辺・岩山・森・残骸のまわり…)。
public typealias FieldID = TypedID<FieldTag>

/// 探索の場。地形か POI で決まる。出来事の表(ExploreEventDef)はこの ID で引く。
public struct FieldDef: ContentDef, Equatable {
    public var id: FieldID
    /// この場になる地形。
    public var terrains: [TerrainID]?
    /// この場になる POI(POI のそばでは地形より POI の場が勝つ)。
    public var pois: [POIKindID]?
    /// 探索範囲がこれ未満の間は、この場の出来事を引かない(原作 MinExplorationRange)。
    public var minRange: Int?

    public init(id: FieldID, terrains: [TerrainID]? = nil, pois: [POIKindID]? = nil, minRange: Int? = nil) {
        self.id = id
        self.terrains = terrains
        self.pois = pois
        self.minRange = minRange
    }
}

/// 探索の出来事 1 件(原作 `ExplorationEventDatabase.ExploreEvent`)。新しい区画・POI に入ったとき、
/// その場の候補から重み(原作の発生 %)で 1 件を引く。id は EventID の "explore.*"(来歴の subject は .event)。
public struct ExploreEventDef: ContentDef, Equatable {
    public var id: EventID
    /// どの場の表か(nil = 汎用。どの場でも候補になる)。
    public var field: FieldID?
    /// 重み(原作の ChancePercent)。
    public var weight: Int
    /// 探索範囲がこれ以上で候補になる。
    public var minRange: Int?
    /// 一度きり(原作 RequiresOnce)。
    public var once: Bool?
    /// 候補になる条件(遺品で危険が下がった後の表を分けるなど)。
    public var when: Condition?
    /// 得られる物(拠点の蓄えに入る)。
    public var yields: [Yield]?
    /// 世界を変える効果(戦闘・事実・人に会う…)。
    public var effects: [Effect]?
    /// 足元カードの 1 行(文字列表)。
    public var text: TextID?
    /// 添え物の場面。
    public var scene: SceneID?
    /// 来歴に付ける印。
    public var tags: [ProvenanceTag]?

    public init(id: EventID, field: FieldID?, weight: Int, minRange: Int? = nil, once: Bool? = nil,
                when: Condition? = nil, yields: [Yield]? = nil, effects: [Effect]? = nil, text: TextID? = nil,
                scene: SceneID? = nil, tags: [ProvenanceTag]? = nil) {
        self.id = id
        self.field = field
        self.weight = weight
        self.minRange = minRange
        self.once = once
        self.when = when
        self.yields = yields
        self.effects = effects
        self.text = text
        self.scene = scene
        self.tags = tags
    }
}

/// 探索の設定(1 つだけ。どの項目も nil なら既定値)。
public struct ExplorationDef: Codable, Equatable, Sendable {
    /// 出来事を引く区画の一辺(マス。既定 8)。新しい区画に入るたびに 1 回引く。
    public var regionSize: Int?
    /// 探索範囲の 1 段の距離(拠点の中心からのマス。既定 8)。範囲 = 1 + 最遠の距離 ÷ これ。
    public var rangeStep: Int?
    /// 探索範囲の上限(既定 11。原作のマイルストーン)。
    public var maxRange: Int?
    /// 「何もなかった」の重み(既定 0 = 候補があれば必ず何か起きる。原作どおり)。
    public var nothingWeight: Int?
    /// 拠点の範囲の中では出来事を引かないか(既定 true)。
    public var quietInBase: Bool?

    public init(regionSize: Int? = nil, rangeStep: Int? = nil, maxRange: Int? = nil, nothingWeight: Int? = nil,
                quietInBase: Bool? = nil) {
        self.regionSize = regionSize
        self.rangeStep = rangeStep
        self.maxRange = maxRange
        self.nothingWeight = nothingWeight
        self.quietInBase = quietInBase
    }
}

/// 拠点の設定(1 つだけ)。
/// 拠点の段階 1 段。
public struct BaseGradeDef: Codable, Equatable, Sendable {
    public var grade: Int
    public var when: Condition

    public init(grade: Int, when: Condition) {
        self.grade = grade
        self.when = when
    }
}

public struct BaseDef: Codable, Equatable, Sendable {
    /// 生存者を迎えるのに拠点の蓄えに要る物(「食料と寝床」の食料)。
    public var welcomeRequires: [Ingredient]?
    /// 迎えるときにそれを使う(渡す)か(既定 true)。
    public var welcomeConsumes: Bool?
    /// 収容のタグ(既定 "housing")。迎えられる人数 = 完成した建造物のこの値の合計。
    public var housingTag: String?
    /// 拠点の段階(低い順。段階 n は、それより下の条件も全部成り立つときに付く)。条件 baseGrade が読む。
    public var grades: [BaseGradeDef]?
    /// 拠点の範囲の建設が進むのに要る火のタグ(例 "fire")。このタグを provides する建造物が効いている間だけ進む
    /// (火床なら whenLit の段以上)。拠点の外に建てる物と、自分がこのタグを出す物(焚き火台)は火を見ない。
    /// nil は火を見ない。持ち主: U21(W-02c)
    public var constructionFireTag: String?

    public init(welcomeRequires: [Ingredient]? = nil, welcomeConsumes: Bool? = nil, housingTag: String? = nil) {
        self.welcomeRequires = welcomeRequires
        self.welcomeConsumes = welcomeConsumes
        self.housingTag = housingTag
    }
}

/// 有限の部品(残骸の区画など)に対する操作。どの部品かは part か、行為を向けたマス
/// (POI の定義の parts[i] ↔ 占めるマスの i 番目)で決まる。マスに当たる部品が無ければ、
/// from に合う最初の部品。
public struct PartOp: Codable, Equatable, Sendable {
    /// 決まった部品(nil = マスで決める)。
    public var part: String?
    /// この状態の部品にだけできる(nil = 何でも)。
    public var from: [PartStateName]?
    /// 終わったら部品をこの状態にする(取り外し・解体・作り直し)。
    public var to: PartStateName?
    /// 修理の段階をこの値にする(今の段階が 1 つ前のときだけできる。解体した部品は直せない)。
    public var repairTo: Int?
    /// 部品ごとの得られる物(InteractionDef.yields の代わり)。
    public var partYields: [String: [Yield]]?

    public init(part: String? = nil, from: [PartStateName]? = nil, to: PartStateName? = nil, repairTo: Int? = nil,
                partYields: [String: [Yield]]? = nil) {
        self.part = part
        self.from = from
        self.to = to
        self.repairTo = repairTo
        self.partYields = partYields
    }
}

extension Yield {
    /// 物の得られ方(確率は万分率。nil は必ず)。
    public static func of(_ item: ItemID, _ min: Int, _ max: Int, basisPoints: Int? = nil, unique: Bool? = nil,
                          durability: Int? = nil) -> Yield {
        Yield(item: item, matter: nil, min: min, max: max, basisPoints: basisPoints, unique: unique, durability: durability)
    }

    public static func of(_ matter: Matter, _ min: Int, _ max: Int, basisPoints: Int? = nil) -> Yield {
        Yield(item: nil, matter: matter, min: min, max: max, basisPoints: basisPoints, unique: nil, durability: nil)
    }
}

extension InteractionDef {
    /// 行為の定義(テスト・コードから作るとき)。
    public static func make(id: InteractionID, target: Target, seconds: Int, hold: Bool = false, when: Condition? = nil,
                            allowedPhases: [DayPhase]? = nil, limit: Int? = nil, yields: [Yield] = [],
                            effects: [Effect]? = nil, tags: [ProvenanceTag]? = nil, cost: [Ingredient]? = nil,
                            partOp: PartOp? = nil, cooldownDays: Int? = nil, requiredPeople: Int? = nil) -> InteractionDef {
        InteractionDef(id: id, target: target, seconds: seconds, hold: hold, when: when, allowedPhases: allowedPhases,
                       limit: limit, yields: yields, effects: effects, tags: tags, cost: cost, partOp: partOp,
                       cooldownDays: cooldownDays, requiredPeople: requiredPeople)
    }
}

extension StructureDef {
    /// 建造物の定義(テスト・コードから作るとき)。
    public static func make(id: StructureKindID, cost: [Ingredient], footprint: [GridPoint]? = nil, buildSeconds: Int,
                            provides: [String: Int], auras: [AuraKindID]? = nil, requiresBaseArea: Bool? = nil,
                            placement: PlacementRule? = nil, specialty: String? = nil) -> StructureDef {
        StructureDef(id: id, cost: cost, footprint: footprint, buildSeconds: buildSeconds, provides: provides,
                     auras: auras, parameters: nil, requiresBaseArea: requiresBaseArea, placement: placement,
                     specialty: specialty)
    }
}
