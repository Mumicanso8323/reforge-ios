import RFKernel
import RFMap
import RFMatter

/// 読み込んだコンテンツの全部(不変)。公開の層と非公開の層を重ねたもの(E-content.md)。
/// 本体・認識の層・画面はこれだけを見る。JSON を直接読まない。
public struct ContentDB: Sendable {
    /// 重ねた層(順番どおり)。セーブに版を残すのに使う。
    public var layers: [LayerManifest] = []

    // 1 つだけの設定(後の層が勝つ)
    public var clock = ClockDef()
    public var mapGen = MapGenConfig(size: GridSize(width: 96, height: 96))
    public var start = StartDef(members: [PersonID.noahID])
    public var rewind = RewindDef()
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
    public var objectives: [ObjectiveID: ObjectiveDef] = [:]
    public var chapters: [ChapterID: ChapterDef] = [:]
    public var endings: [EndingID: EndingDef] = [:]
    public var findings: [FindingID: FindingDef] = [:]

    // 認識の層
    public var perception: [SubjectID: SubjectDef] = [:]
    public var forbidden: [ForbiddenRule] = []
    public var auditStages: [AuditStage] = []
    public var textGates: [TextID: TextGate] = [:]
    /// 文字列表(日本語)。本文の大半は非公開の層にある。
    public var texts: [TextID: String] = [:]
    /// 地図の文字(見出し → 1 文字)。認識の表の glyph が優先。
    public var glyphs: [SubjectID: String] = [:]

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

    public init(id: String, visibility: Visibility, version: String) {
        self.id = id
        self.visibility = visibility
        self.version = version
    }
}
