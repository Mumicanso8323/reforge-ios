import RFKernel
import RFMap
import RFMatter

/// 読み込んだコンテンツの全部(不変)。公開の層と非公開の層を重ねたもの(E-content.md)。
/// 本体・認識の層・画面はこれだけを見る。JSON を直接読まない。
public struct ContentDB: Equatable, Sendable {
    /// 重ねた層(順番どおり)。セーブに版を残すのに使う。
    public var layers: [LayerManifest] = []

    // 1 つだけの設定(後の層が勝つ)
    public var clock = ClockDef()
    public var mapGen = MapGenConfig(size: GridSize(width: 96, height: 96))
    public var start = StartDef(members: [PersonID.noahID])
    public var rewind = RewindDef()
    /// 生存の規則(消費・空腹・精神力・状態)。nil = 規則なし(公開の試験用の層は持たない)。持ち主: U4
    public var survival: SurvivalDef?
    /// 発明の規則の表(RFMatter)。コンテンツに無ければ R1 の表。
    public var ruleBook: RuleBook = .r1

    // ID で引く定義
    public var terrains: [TerrainID: TerrainDef] = [:]
    public var biomes: [BiomeID: BiomeDef] = [:]
    public var pois: [POIKindID: POIDef] = [:]
    public var handwork: [HandworkID: HandworkDef] = [:]
    public var modules: [ModuleKindID: ModuleDef] = [:]
    public var structures: [StructureKindID: StructureDef] = [:]
    public var interactions: [InteractionID: InteractionDef] = [:]
    public var people: [PersonID: PersonDef] = [:]
    public var ideologyAxes: [IdeologyAxisID: IdeologyAxisDef] = [:]
    public var memoryKinds: [MemoryKindID: MemoryKindDef] = [:]
    public var lines: [LineID: LineDef] = [:]
    public var hints: [HintID: HintDef] = [:]
    public var research: [ResearchID: ResearchDef] = [:]
    public var skills: [SkillID: SkillDef] = [:]
    public var abilities: [AbilityID: AbilityDef] = [:]
    public var enemies: [EnemyKindID: EnemyDef] = [:]
    public var auras: [AuraKindID: AuraDef] = [:]
    public var stats: [StatID: StatDef] = [:]
    public var failureRules: [FailureRuleID: FailureRuleDef] = [:]
    public var trackers: [CounterID: TrackerDef] = [:]
    public var facts: [FactID: FactDef] = [:]
    public var events: [EventID: EventDef] = [:]
    public var scenes: [SceneID: SceneDef] = [:]
    public var sheets: [SheetID: SheetDef] = [:]
    /// 記録から開ける資料。
    public var documents: [DocumentID: DocumentDef] = [:]
    public var objectives: [ObjectiveID: ObjectiveDef] = [:]
    public var chapters: [ChapterID: ChapterDef] = [:]
    public var endings: [EndingID: EndingDef] = [:]
    public var findings: [FindingID: FindingDef] = [:]

    // 探索と拠点(持ち主: U8。RFContent/Schema/Exploration.swift)
    /// 探索の場(地形・POI → 出来事の表)。
    public var fields: [FieldID: FieldDef] = [:]
    /// 探索の出来事の表(原作 ExplorationEventDatabase)。
    public var exploreEvents: [EventID: ExploreEventDef] = [:]
    /// 探索の設定(区画の大きさ・探索範囲の段)。
    public var exploration = ExplorationDef()
    /// 拠点の設定(生存者を迎える条件など)。
    public var base = BaseDef()

    // 認識の層
    public var perception: [SubjectID: SubjectDef] = [:]
    public var forbidden: [ForbiddenRule] = []
    public var auditStages: [AuditStage] = []
    public var textGates: [TextID: TextGate] = [:]
    /// 文字列表(日本語)。本文の大半は非公開の層にある。
    public var texts: [TextID: String] = [:]
    /// 地図の文字(見出し → 1 文字)。認識の表の glyph が優先。
    public var glyphs: [SubjectID: String] = [:]
    /// 画面に出してよいラテン文字の語(固有名・題名など)。英語の ID の検査はこの語を除いてから判定する。
    /// 層をまたいで足し合わせる。語がネタバレなら非公開の層に置き、禁止語の規則で until まで伏せる。
    public var latinAllowed: [String] = []

    public init() {}
}

extension PersonID {
    /// ContentDB の既定値用(RFWorld の PersonID.noah と同じ値。RFContent は RFWorld に依存しないので写し)。
    public static let noahID: PersonID = "person.noah"
}

/// 層 1 枚の名札(bundle.json)。
public struct LayerManifest: Codable, Equatable, Sendable {
    public enum Visibility: String, Codable, Sendable { case `public`, `private` }

    public var id: String
    public var visibility: Visibility
    /// 版(コンテンツのリポジトリのコミットなど)。セーブに残し、移行の判断に使う。
    public var version: String
    /// 見張りの文字列(非公開の層だけ。本文ではない無意味な文字列)。CI が、封をした ipa の中に平文で
    /// 現れないことを確かめるのに使う(E-content.md §4.5)。画面には出さない。
    public var canary: String?

    public init(id: String, visibility: Visibility, version: String, canary: String? = nil) {
        self.id = id
        self.visibility = visibility
        self.version = version
        self.canary = canary
    }
}
