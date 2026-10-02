import RFKernel
import RFMap
import RFMatter

/// 世界状態の全体(B-data-model.md が正本)。値型・Codable・決定的。
///
/// - 切れ端(slice)ごとに持ち主のシステムが 1 つ決まっている。書き込むのは持ち主だけ
///   (他のシステムは読むだけ。書き換えたいときはコマンドか出来事を出す)。例外は StepContext の共通操作
///   (来歴の記録・事実を知る・在庫の出し入れ)で、これは誰でも使ってよい。
/// - 名前・文章は持たない。持つのは真実の ID と数だけ。見え方は RFPerception が knowledge から引く。
/// - 浮動小数を持たない(Purity・Milli・GameTime の整数)。
/// - この型の項目を足す・消すのは統合担当だけ(各切れ端の中身は持ち主が自由に足してよい)。
public struct WorldState: Codable, Equatable, Sendable {
    /// 乱数(システムごとの流れ)。持ち主: 全システム(自分の流れだけ使う)
    public var rng: RandomStreams
    /// 実体の ID の発行。持ち主: 共通
    public var ids: IDAllocator
    /// 時計。持ち主: RFTime
    public var clock: ClockState
    /// 地図(地形・鉱脈・POI)。持ち主: RFMap の計算を使う各システム(鉱脈の残り = RFProduction/RFExploration)
    public var map: MapState
    /// ノア・仲間・まだ会っていない人(地図上の実体)。持ち主: RFCrew
    public var people: PeopleState
    /// 置いた物(モジュール・建造物)。持ち主: RFProduction(モジュール)と RFBase(建造物)
    public var placements: PlacementsState
    /// 物の在り処(拠点の蓄え・持ち物・保管庫)。持ち主: 共通(StepContext の在庫操作を使う)
    public var inventory: InventoryState
    /// ライン札と試作。持ち主: RFInvention
    public var invention: InventionState
    /// 実験ノート・図鑑・聞いたヒント。持ち主: RFInvention(巻き戻しで持ち越す)
    public var notebook: NotebookState
    /// 運搬の経路と流量(電力は R2)。持ち主: RFLogistics
    public var logistics: LogisticsState
    /// 知っている事実・地図の既知・発見。持ち主: 共通(StepContext.learn)。巻き戻しで持ち越す
    public var knowledge: KnowledgeState
    /// 来歴(誰が・いつ・何を・どこで)。持ち主: 共通(StepContext.record)
    public var ledger: ProvenanceLedger
    /// 拠点全体の生存の圧・数値・天候・季節。持ち主: RFSurvival
    public var survival: SurvivalState
    /// POI を調べた進み具合・道筋。持ち主: RFExploration
    public var exploration: ExplorationState
    /// 拠点のグレード・範囲。持ち主: RFBase
    public var base: BaseState
    /// 地図上の脅威・戦闘。持ち主: RFCombat
    public var combat: CombatState
    /// 研究・スキル・解禁。持ち主: RFResearch(解禁は出来事の効果からも足される)
    public var research: ResearchState
    /// 範囲の効果。持ち主: 共通(付け外しは効果と定義から)
    public var auras: AuraState
    /// 人ごとの能力。持ち主: RFAbilities
    public var abilities: AbilitiesState
    /// 出来事・決断待ち・カウンタ・目標・章・結末。持ち主: RFNarrative
    public var narrative: NarrativeState
    /// 周回・巻き戻し・失敗。持ち主: RFFailure
    public var run: RunState

    public init(seed: UInt64, map: MapState) {
        rng = RandomStreams(seed: seed)
        ids = IDAllocator()
        clock = ClockState()
        self.map = map
        people = PeopleState()
        placements = PlacementsState()
        inventory = InventoryState()
        invention = InventionState()
        notebook = NotebookState()
        logistics = LogisticsState()
        knowledge = KnowledgeState()
        ledger = ProvenanceLedger()
        survival = SurvivalState()
        exploration = ExplorationState()
        base = BaseState()
        combat = CombatState()
        research = ResearchState()
        auras = AuraState()
        abilities = AbilitiesState()
        narrative = NarrativeState()
        run = RunState()
    }

    public var seed: UInt64 { rng.seed }

    /// 新しい実体の ID。
    public mutating func newEntityID() -> EntityID { EntityID(ids.next()) }
}
