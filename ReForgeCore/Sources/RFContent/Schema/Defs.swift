import RFKernel
import RFMap
import RFMatter

// コンテンツの定義(E-content.md が正本)。どれも Codable で、JSON の 1 要素が 1 つの定義。
// 名前・説明・台詞の本文は持たない(TextID か認識の表の SubjectID で指す)。本文は文字列表(非公開)にある。
// 各定義の中身は、そのシステムの担当が足してよい(項目を足すときは省略可能にして、古いコンテンツが読めるように)。

/// ID で引ける定義。
public protocol ContentDef: Codable, Sendable {
    associatedtype Key: Hashable & Comparable & Codable & Sendable
    var id: Key { get }
}

extension TerrainDef: ContentDef {}
extension MaterialKindDef: ContentDef {}
extension ProcessDef: ContentDef {}

/// 物の数(費用・材料)。
public struct ItemCost: Codable, Hashable, Sendable {
    public var kind: ItemKindID
    public var quantity: Int
    public var minPurity: Purity?

    public init(kind: ItemKindID, quantity: Int, minPurity: Purity? = nil) {
        self.kind = kind
        self.quantity = quantity
        self.minPurity = minPurity
    }
}

// MARK: - 時間・地図

/// 時計の設定。
public struct ClockDef: Codable, Equatable, Sendable {
    /// 昼の実秒(既定 180)。
    public var dayRealSeconds: Int
    /// 昼のゲーム時間(既定 8)。
    public var dayGameHours: Int
    /// 夜のゲーム時間(既定 18)。1 日 = 昼 + 夜(内部では 26 時間。画面には時間数を出さない)。
    public var nightGameHours: Int

    public init(dayRealSeconds: Int = 180, dayGameHours: Int = 8, nightGameHours: Int = 18) {
        self.dayRealSeconds = dayRealSeconds
        self.dayGameHours = dayGameHours
        self.nightGameHours = nightGameHours
    }

    public var dayGameSeconds: Int64 { Int64(dayGameHours) * 3600 }
    public var nightGameSeconds: Int64 { Int64(nightGameHours) * 3600 }
}

public struct BiomeDef: ContentDef, Equatable {
    public var id: BiomeID
    public var parameters: Value
}

public struct POIDef: ContentDef, Equatable {
    public var id: POIKindID
    /// 有限の部品の名前(残骸の区画など)。
    public var parts: [String]?
    public var parameters: Value
}

// MARK: - 作る・置く

/// 手作業・固定の作り方(押し続けて 1 単位)。
public struct RecipeDef: ContentDef, Equatable {
    public var id: RecipeID
    public var inputs: [ItemCost]
    public var output: ItemCost
    public var form: FormID?
    /// 押し続ける回数(粉 5 / 塊 8 / 板 16 など)。
    public var presses: Int
    /// どこでできるか(建造物の種類。nil はどこでも)。
    public var station: StructureKindID?
    public var parameters: Value?
}

/// 地図に置く生産モジュール。
public struct ModuleDef: ContentDef, Equatable {
    public var id: ModuleKindID
    /// 受け持つ工程(採掘口のように工程でないものは nil)。
    public var process: ProcessID?
    public var cost: [ItemCost]
    public var placement: PlacementRule
    /// 入出口(向き基準の相対の辺)。
    public var ports: [PortDef]
    /// 1 回の処理のゲーム秒(既定 60 実秒相当)。
    public var cycleSeconds: Int
    /// 付くと速くなる専門(タグ)。
    public var specialty: String?
    /// 置いている間に周りに出す範囲の効果(炉の排気など)。
    public var auras: [AuraKindID]?
    public var parameters: Value?
}

public struct PlacementRule: Codable, Equatable, Sendable {
    /// 鉱脈の上でないと置けない。
    public var requiresDeposit: Bool?
    /// 水に接していないと置けない。
    public var requiresWaterAdjacent: Bool?
    /// 置ける地形のタグ(nil はどこでも)。
    public var terrainTags: [String]?
    /// 置けないときの理由(文字列表のキー)。
    public var reasonIfBlocked: TextID?
}

public struct PortDef: Codable, Equatable, Sendable {
    public enum Flow: String, Codable, Sendable { case input, output }
    /// 向き(north = モジュールの正面)を基準にした辺。
    public var side: Direction
    public var flow: Flow
}

/// 建造物(シェルター・焚き火台・柵・保管・炭焼き窯・研究机…)。
public struct StructureDef: ContentDef, Equatable {
    public var id: StructureKindID
    public var cost: [ItemCost]
    public var footprint: [GridPoint]?
    /// 建てるのにかかるゲーム秒(仲間が手伝うと速い)。
    public var buildSeconds: Int
    /// 効果のタグと値(shelter: 精神力の回復、light: 灯りの半径、storage: 容量、housing: 収容…)。
    public var provides: [String: Int]
    public var auras: [AuraKindID]?
    public var parameters: Value?
}

/// マス・POI・置いた物に対してできる行為(漁る・汲む・掘る・観測する…)。
public struct InteractionDef: ContentDef, Equatable {
    public enum Target: Codable, Equatable, Sendable {
        case terrain(tag: String)
        case poi(kind: POIKindID)
        case deposit
        case structure(kind: StructureKindID)
        case module(kind: ModuleKindID)
    }

    public var id: InteractionID
    public var target: Target
    /// かかるゲーム秒。hold なら押している間だけ進む。
    public var seconds: Int
    public var hold: Bool
    public var when: Condition?
    /// 昼だけ / 夜も可。
    public var allowedPhases: [DayPhase]?
    /// 回数の上限(残骸を漁る 10 回など)。
    public var limit: Int?
    /// 得られる物(確率は万分率)。
    public var yields: [Yield]
    public var effects: [Effect]?
    /// 来歴に付ける印。
    public var tags: [ProvenanceTag]?
}

public struct Yield: Codable, Equatable, Sendable {
    public var kind: ItemKindID
    public var min: Int
    public var max: Int
    public var basisPoints: Int?
    public var purity: Purity?
    public var form: FormID?
    public var unique: Bool?
}

// MARK: - 人

public struct PersonDef: ContentDef, Equatable {
    public var id: PersonID
    /// 名前の見出し(認識の表)。
    public var name: SubjectID
    public var specialties: [String]
    public var ideology: [IdeologyAxisID: Int]
    /// 人が持つ範囲の効果(R3 の声など)。
    public var auras: [AuraKindID]?
    public var parameters: Value?
}

public struct IdeologyAxisDef: ContentDef, Equatable {
    public var id: IdeologyAxisID
    /// どの行為のタグがこの軸にどう効くか(来歴の印 → 賛否の重み)。
    public var weights: [ProvenanceTag: Int]
}

public struct MemoryKindDef: ContentDef, Equatable {
    public var id: MemoryKindID
    /// 既定で巻き戻しをまたいで残るか。
    public var persistsAcrossRewind: Bool
}

/// 仲間の一言(定型文)。振る舞いに付く一言だけにする。どれを言うかは条件と文脈で選ぶ。
public struct LineDef: ContentDef, Equatable {
    public var id: LineID
    public var speaker: PersonID
    /// 文脈("campfire", "opinion.approve", "assigned.module", "rewind.deja_vu" など)。
    public var context: String
    public var when: Condition?
    public var text: TextID
    public var weight: Int?
}

public struct HintDef: ContentDef, Equatable {
    public var id: HintID
    public var from: PersonID?
    public var when: Condition
    public var about: SubjectID
    public var text: TextID
    /// 出典(認識の表の見出し)。
    public var source: SubjectID
}

// MARK: - 研究・力・敵

public struct ResearchDef: ContentDef, Equatable {
    public var id: ResearchID
    public var points: Int
    public var requires: Condition?
    public var station: StructureKindID?
    public var unlocks: [UnlockTarget]
    public var effects: [Effect]?
}

public struct SkillDef: ContentDef, Equatable {
    public var id: SkillID
    public var requires: Condition?
    public var unlocks: [UnlockTarget]?
    public var parameters: Value?
}

public struct AbilityDef: ContentDef, Equatable {
    public var id: AbilityID
    public var parameters: Value?
}

public struct EnemyDef: ContentDef, Equatable {
    public var id: EnemyKindID
    public var health: Int
    public var attack: Int
    public var drops: [Yield]
    public var parameters: Value?
}

// MARK: - 範囲の効果・隠れた値・失敗

/// 範囲の効果の中身。中にいる人・物・敵に何が起きるか。
public struct AuraDef: ContentDef, Equatable {
    public enum Modifier: Codable, Equatable, Sendable {
        /// 数値が 1 時間あたり変わる(精神力が減るなど)。
        case bodyPerHour(stat: String, amount: Int)
        /// 作業の速さ(千分率で掛ける)。
        case workSpeed(permille: Int)
        /// 仲間がプレイヤーの配属に従わず、中心へ歩く。
        case drawTowardSource
        /// 敵が入ってこない。
        case repelEnemies
        /// 拠点全体の数値への寄与(大気への上積みなど)。
        case statPerHour(stat: StatID, amount: Int)
    }

    public var id: AuraKindID
    public var modifiers: [Modifier]
    /// 誰に効くか(nil は全員)。
    public var affects: [PersonID]?
}

/// 拠点全体の数値(大気・季節の暦…)。開示まで見せない値もここ。見せ方は認識の表。
public struct StatDef: ContentDef, Equatable {
    public var id: StatID
    public var initial: Int
    /// 1 日あたりの基礎の増減(千分率)。内訳を別の数値に分けて持てる(基礎 + 採掘の上積み = 合計)。
    public var perDay: Int?
    /// 合計として他の数値を足し合わせる(内訳を内部に持ち、開示で内訳を見せる)。
    public var sumOf: [StatID]?
}

/// 失敗の規則。期限は日数でなく値で判定する。
public struct FailureRuleDef: ContentDef, Equatable {
    public var id: FailureRuleID
    public var when: Condition
    public var cause: TextID
}

/// 追跡カウンタ(観測した夜の数・ある仲間がノアの近くで働いた時間など)。毎ステップ、本体が数える。
public struct TrackerDef: ContentDef, Equatable {
    public enum Kind: Codable, Equatable, Sendable {
        /// 2 人が半径 r 以内にいたゲーム秒(分に繰り上げて counters に入れる)。
        case proximityMinutes(a: PersonID, b: PersonID, radius: Int, whileWorking: Bool)
        /// 条件が成り立っていた夜の数(夜明けに判定)。
        case nightsWhere(condition: Condition)
        /// 来歴の数(問い合わせに合う記録の count の合計)。
        case ledgerCount(query: ProvenanceQuery)
    }

    public var id: CounterID
    public var kind: Kind
}

// MARK: - 事実・認識・出来事

/// 事実の定義。
public struct FactDef: ContentDef, Equatable {
    public enum Scope: String, Codable, Sendable {
        /// プレイヤーの記憶: 巻き戻しても残る(既定)。
        case memory
        /// その時間軸だけ: 巻き戻すと消える。
        case timeline
    }

    public var id: FactID
    public var scope: Scope?
    /// 知ると同時に知ること。
    public var implies: [FactID]?
}

/// 出来事。日数でなく、行動(hook)と世界の状態(when)で起きる。
public struct EventDef: ContentDef, Equatable {
    public struct Trigger: Codable, Equatable, Sendable {
        /// どの DomainEvent の後に調べるか(hook の名前)。nil なら夜明けと毎時。
        public var on: [String]?
        public var when: Condition
    }

    public enum Repeat: Codable, Equatable, Sendable {
        case once
        case cooldown(hours: Int)
        case always
    }

    public var id: EventID
    public var trigger: Trigger
    public var repeats: Repeat?
    public var priority: Int?
    public var effects: [Effect]
    /// 添え物の場面(下の帯に 3 行まで)。
    public var scene: SceneID?
    /// 決断(選択肢)。あれば PendingDecision を出す。
    public var choices: [ChoiceDef]?
    /// 決めるまで時計を止めるか(既定 false)。
    public var blocking: Bool?
    /// 来歴に付ける印。
    public var tags: [ProvenanceTag]?
}

public struct ChoiceDef: Codable, Equatable, Sendable {
    public var id: ChoiceID
    public var label: TextID
    public var when: Condition?
    public var effects: [Effect]
    /// 選んだことに付ける印(仲間の思想が賛否をこれで判断する)。
    public var tags: [ProvenanceTag]?
}

/// 場面: 定型文の並び。地図の上に 3 行まで。長い本文は資料(SheetDef / ノート)に置く。
public struct SceneDef: ContentDef, Equatable {
    public struct Line: Codable, Equatable, Sendable {
        public var speaker: PersonID?
        public var text: TextID
        public var when: Condition?
    }

    public var id: SceneID
    public var lines: [Line]
}

/// 工程表(設計画面と同じ部品で開ける表)。ライン札・試作のほか、ある装置の記録なども表として開ける。
public struct SheetDef: ContentDef, Equatable {
    public struct Row: Codable, Equatable, Sendable {
        /// 行の見出し(認識の表)。
        public var subject: SubjectID
        public var note: TextID?
        public var when: Condition?
    }

    public var id: SheetID
    public var title: SubjectID
    public var rows: [Row]
    /// 開けるようになる条件。
    public var when: Condition
}

public struct ObjectiveDef: ContentDef, Equatable {
    public var id: ObjectiveID
    public var text: TextID
    public var completeWhen: Condition
    public var effects: [Effect]?
}

public struct ChapterDef: ContentDef, Equatable {
    public var id: ChapterID
    public var title: TextID
}

public struct EndingDef: ContentDef, Equatable {
    public var id: EndingID
    public var when: Condition
    public var scene: SceneID?
}

public struct ObservationDef: ContentDef, Equatable {
    public var id: ObservationID
    public var text: TextID
}

/// 始まりの世界。
public struct StartDef: Codable, Equatable, Sendable {
    /// 最初からいる一員(ノアを含む)。
    public var members: [PersonID]
    /// 存在だけを内部に持つ人(まだ会っていない)。
    public var unmet: [PersonID]?
    public var items: [ItemCost]
    public var facts: [FactID]
    public var unlocks: [UnlockTarget]
    public var objectives: [ObjectiveID]?
    public var chapter: ChapterID?
    /// 始めに起こす出来事(目覚めの場面など)。
    public var events: [EventID]?

    public init(members: [PersonID], unmet: [PersonID]? = nil, items: [ItemCost] = [], facts: [FactID] = [],
                unlocks: [UnlockTarget] = [], objectives: [ObjectiveID]? = nil, chapter: ChapterID? = nil,
                events: [EventID]? = nil) {
        self.members = members
        self.unmet = unmet
        self.items = items
        self.facts = facts
        self.unlocks = unlocks
        self.objectives = objectives
        self.chapter = chapter
        self.events = events
    }
}
