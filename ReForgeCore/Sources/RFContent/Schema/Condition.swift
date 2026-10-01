import RFKernel
import RFMatter

/// 世界の状態を見る条件(出来事の引き金・選択肢の出る条件・研究の前提・目標の達成…)。
/// 宣言的なデータで、評価は RFRules.ConditionEvaluator。
///
/// JSON は Swift の列挙の既定の形(case 名がキー、ラベルが中のキー)。例:
///   {"all": {"of": [ {"known": {"expr": "fact.x"}}, {"hasItem": {"kind": "item.iron", "atLeast": 3}} ]}}
///   {"ledger": {"query": {"act": "placed", "module": "module.furnace"}, "atLeast": 1}}
/// 「日数」で引く条件(dayAtLeast)は持っているが、物語の引き金には使わない(検証で警告する)。
public indirect enum Condition: Codable, Hashable, Sendable {
    case always
    case all(of: [Condition])
    case any(of: [Condition])
    case not(that: Condition)

    /// 知っている事実(認識の層と同じ式)。
    case known(expr: FactExpr)
    /// 物を持っている(拠点の蓄え+ノアの持ち物)。
    case has(what: Ingredient)
    /// モジュール・建造物が動いている数。
    case placedCount(module: ModuleKindID?, structure: StructureKindID?, atLeast: Int)
    /// 来歴の問い合わせ(「炉を置いたことがある」「この印の付いた物を 10 個以上作った」)。
    case ledger(query: ProvenanceQuery, atLeast: Int)
    /// 「工業の初めて」: 引き金になった記録が、この問い合わせに合う最初の記録である。
    case firstTime(query: ProvenanceQuery)
    /// 有限の部品の状態(残骸の区画を解体したか、など)。
    case part(poiKind: POIKindID, part: String, state: PartStateName)
    /// 範囲の効果の中にいる。
    case inAura(person: PersonID, kind: AuraKindID)
    /// 人の状態。
    case person(id: PersonID, test: PersonTest)
    /// 一員の人数。
    case members(atLeast: Int)
    /// 拠点の外の集団との関係。
    case group(id: GroupID, relationAtLeast: Int)
    case counter(id: CounterID, cmp: Comparison, value: Int)
    /// 数値(大気など。千分率)。
    case stat(id: StatID, cmp: Comparison, value: Int)
    case phase(is: DayPhase)
    /// 日数(物語の引き金には使わない。仕組みの都合のときだけ)。
    case dayAtLeast(day: Int)
    case eventFired(id: EventID)
    case choiceMade(event: EventID, choice: ChoiceID)
    case researchDone(id: ResearchID)
    case unlocked(target: UnlockTarget)
    /// ノア(または誰か)がある場所にいる。
    case at(person: PersonID, place: PlaceSelector)
    /// 場所の近く(チェビシェフ距離 radius 以内)に、この印の地形がある。印 "water" は TerrainDef.isWater の地形にも当たる。
    /// 例: 冷やす段の試作は水辺に接していればできる(radius 1)。
    case nearTerrain(place: PlaceSelector, tag: String, radius: Int)
    /// POI の種類を見つけている。
    case discoveredPOI(kind: POIKindID)
    case objective(id: ObjectiveID, status: ObjectiveStatusName)
    /// 決定的な確率(物語の乱数の流れ)。
    case chance(basisPoints: Int)
    /// 何周目以降か(巻き戻しの後だけ起きる出来事)。
    case runAtLeast(index: Int)
}

/// 目標の状態の名前(RFWorld の ObjectiveStatus と同じ値。RFContent は RFWorld に依存しないので写しを持つ)。
public enum ObjectiveStatusName: String, Codable, Hashable, Sendable { case active, done, failed }

/// 人についての条件。
public enum PersonTest: Codable, Hashable, Sendable {
    case member
    case alive
    case dead
    case met
    case relationAtLeast(rank: Int)
    case ideologyAtLeast(axis: IdeologyAxisID, value: Int)
    case hasMemory(kind: MemoryKindID)
    case assignedToModule(kind: ModuleKindID?)
    case hasSkill(skill: SkillID)
}

/// 来歴の問い合わせ。指定した項目だけで絞る(nil は問わない)。
public struct ProvenanceQuery: Codable, Hashable, Sendable {
    public var act: ActKind?
    public var actor: PersonID?
    public var item: ItemID?
    public var module: ModuleKindID?
    public var structure: StructureKindID?
    public var person: PersonID?
    public var enemy: EnemyKindID?
    public var poi: POIKindID?
    public var event: EventID?
    public var tag: ProvenanceTag?
    /// 今の周回だけを見るか(既定 true。前の周回は RunState.pastLives を見る)。
    public var currentRunOnly: Bool?

    public init(act: ActKind? = nil, actor: PersonID? = nil, item: ItemID? = nil, module: ModuleKindID? = nil,
                structure: StructureKindID? = nil, person: PersonID? = nil, enemy: EnemyKindID? = nil,
                poi: POIKindID? = nil, event: EventID? = nil, tag: ProvenanceTag? = nil, currentRunOnly: Bool? = nil) {
        self.act = act
        self.actor = actor
        self.item = item
        self.module = module
        self.structure = structure
        self.person = person
        self.enemy = enemy
        self.poi = poi
        self.event = event
        self.tag = tag
        self.currentRunOnly = currentRunOnly
    }
}

/// 場所の指し方。
public enum PlaceSelector: Codable, Hashable, Sendable {
    /// 引き金の出来事の場所(来歴の place)。
    case trigger
    case person(id: PersonID)
    case poiKind(kind: POIKindID)
    case base
    case point(at: WorldPoint)
    /// 半径つき。
    indirect case near(place: PlaceSelector, radius: Int)
}

/// 解禁の対象。
public enum UnlockTarget: Codable, Hashable, Sendable {
    case module(id: ModuleKindID)
    case structure(id: StructureKindID)
    case handwork(id: HandworkID)
    case interaction(id: InteractionID)
    case research(id: ResearchID)
}
