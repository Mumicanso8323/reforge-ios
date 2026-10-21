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
    /// Deferred work at the optional trial boundary.  Missing keys in older saves decode as the default.
    public var trial: TrialState?

    enum CodingKeys: String, CodingKey {
        case rng, ids, clock, map, people, placements, inventory, invention, notebook, logistics, knowledge, ledger
        case survival, exploration, base, combat, research, auras, abilities, narrative, run, trial
    }

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
        trial = nil
    }

    /// Keep pre-boundary save bytes stable: `trial` is omitted until it has
    /// actual deferred state, while old saves decode as an empty boundary.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rng = try c.decode(RandomStreams.self, forKey: .rng); ids = try c.decode(IDAllocator.self, forKey: .ids)
        clock = try c.decode(ClockState.self, forKey: .clock); map = try c.decode(MapState.self, forKey: .map)
        people = try c.decode(PeopleState.self, forKey: .people); placements = try c.decode(PlacementsState.self, forKey: .placements)
        inventory = try c.decode(InventoryState.self, forKey: .inventory); invention = try c.decode(InventionState.self, forKey: .invention)
        notebook = try c.decode(NotebookState.self, forKey: .notebook); logistics = try c.decode(LogisticsState.self, forKey: .logistics)
        knowledge = try c.decode(KnowledgeState.self, forKey: .knowledge); ledger = try c.decode(ProvenanceLedger.self, forKey: .ledger)
        survival = try c.decode(SurvivalState.self, forKey: .survival); exploration = try c.decode(ExplorationState.self, forKey: .exploration)
        base = try c.decode(BaseState.self, forKey: .base); combat = try c.decode(CombatState.self, forKey: .combat)
        research = try c.decode(ResearchState.self, forKey: .research); auras = try c.decode(AuraState.self, forKey: .auras)
        abilities = try c.decode(AbilitiesState.self, forKey: .abilities); narrative = try c.decode(NarrativeState.self, forKey: .narrative)
        run = try c.decode(RunState.self, forKey: .run); trial = try c.decodeIfPresent(TrialState.self, forKey: .trial)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rng, forKey: .rng); try c.encode(ids, forKey: .ids); try c.encode(clock, forKey: .clock); try c.encode(map, forKey: .map)
        try c.encode(people, forKey: .people); try c.encode(placements, forKey: .placements); try c.encode(inventory, forKey: .inventory)
        try c.encode(invention, forKey: .invention); try c.encode(notebook, forKey: .notebook); try c.encode(logistics, forKey: .logistics)
        try c.encode(knowledge, forKey: .knowledge); try c.encode(ledger, forKey: .ledger); try c.encode(survival, forKey: .survival)
        try c.encode(exploration, forKey: .exploration); try c.encode(base, forKey: .base); try c.encode(combat, forKey: .combat)
        try c.encode(research, forKey: .research); try c.encode(auras, forKey: .auras); try c.encode(abilities, forKey: .abilities)
        try c.encode(narrative, forKey: .narrative); try c.encode(run, forKey: .run)
        try c.encodeIfPresent(trial, forKey: .trial)
    }

    public var seed: UInt64 { rng.seed }

    /// 新しい実体の ID。
    public mutating func newEntityID() -> EntityID { EntityID(ids.next()) }
}
