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

/// 材料・費用 1 つ。item(薪・木炭…)か matter(鉄板など。条件で絞る)のどちらか。
public struct Ingredient: Codable, Hashable, Sendable {
    public var item: ItemID?
    public var matter: MatterMatch?
    public var quantity: Int
    /// 品の属性の一致(条件 has で使う。例 "owner": 遺品の持ち主)。費用・消費では使わない。
    public var attributes: [String: String]?

    public init(item: ItemID? = nil, matter: MatterMatch? = nil, quantity: Int,
                attributes: [String: String]? = nil) {
        self.attributes = attributes
        self.item = item
        self.matter = matter
        self.quantity = quantity
    }
}

/// 物質の条件(nil は問わない)。「純度 45% 以上の鉄の板」など。
public struct MatterMatch: Codable, Hashable, Sendable {
    public var substance: SubstanceID?
    public var stage: MatterStage?
    public var shapes: [Shape]?
    public var minPurity: Purity?
    public var tempers: [Temper]?

    public init(substance: SubstanceID? = nil, stage: MatterStage? = nil, shapes: [Shape]? = nil,
                minPurity: Purity? = nil, tempers: [Temper]? = nil) {
        self.substance = substance
        self.stage = stage
        self.shapes = shapes
        self.minPurity = minPurity
        self.tempers = tempers
    }

    public func matches(_ m: Matter) -> Bool {
        if let s = substance, m.substance != s { return false }
        if let s = stage, m.stage != s { return false }
        if let s = shapes, !s.contains(m.shape) { return false }
        if let p = minPurity, m.purity < p { return false }
        if let t = tempers, !t.contains(m.temper) { return false }
        return true
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

/// 手作業(押し続けて 1 単位。原作 HandCraft)。工程 1 つを手でやる(石臼の代わりに石で砕く、など)。
public struct HandworkDef: ContentDef, Equatable {
    public var id: HandworkID
    /// 手でやる工程(RFMatter の規則の表で計算する)。工程でない手作業(枝を拾う等)は nil で yields を使う。
    public var step: ProcessStep?
    public var yields: [Yield]?
    /// 押し続ける回数(粉 5 / 塊 8 / 板 16 など)。
    public var presses: Int
    /// どこでできるか(建造物の種類。nil はどこでも)。
    public var station: StructureKindID?
    public var parameters: Value?
    // 以下は U7(生産)が足した。どれも省略可能。
    /// 足元(ノアのいるマスか隣)の鉱脈を 1 回掘る手作業(採掘口の手の版)。1 単位 = 鉱脈 1 回ぶん。
    public var onDeposit: Bool?
    /// 1 回押すのにかかるゲーム秒(既定 160 = 昼の実時間 1 秒)。押し続けている間、この速さで進む。
    public var pressSeconds: Int?
    /// できる時間帯(既定は昼だけ。夜にもできるものは夜作業の 1 単位ずつ、押す回数 × pressSeconds の時間がかかる)。
    public var allowedPhases: [DayPhase]?
    /// この手作業を任意にする T1 のモジュール(どれかが動いていれば、手作業は「任意」と表示する)。
    public var promotedBy: [ModuleKindID]?

    public init(id: HandworkID, step: ProcessStep? = nil, yields: [Yield]? = nil, presses: Int,
                station: StructureKindID? = nil, parameters: Value? = nil, onDeposit: Bool? = nil,
                pressSeconds: Int? = nil, allowedPhases: [DayPhase]? = nil, promotedBy: [ModuleKindID]? = nil) {
        self.id = id
        self.step = step
        self.yields = yields
        self.presses = presses
        self.station = station
        self.parameters = parameters
        self.onDeposit = onDeposit
        self.pressSeconds = pressSeconds
        self.allowedPhases = allowedPhases
        self.promotedBy = promotedBy
    }
}

/// 運搬の数(最上位キー "hauling"。どれも省略でき、無ければ R1 の仮の値 = RFLogistics.HaulRules の既定)。
public struct HaulingDef: Codable, Equatable, Sendable {
    /// 1 人 1 日(昼の長さのゲーム時間)に運べる数。既定 10。
    public var perPersonPerDay: Int?
    /// ここまでは落ちない距離(マス)。既定 8。
    public var freeDistance: Int?
    /// この距離ごとに落ちる(マス)。既定 5。
    public var stepDistance: Int?
    /// 1 段で残る割合(千分率。掛け算で重ねる)。既定 800。
    public var keepPermille: Int?

    public init(perPersonPerDay: Int? = nil, freeDistance: Int? = nil, stepDistance: Int? = nil, keepPermille: Int? = nil) {
        self.perPersonPerDay = perPersonPerDay
        self.freeDistance = freeDistance
        self.stepDistance = stepDistance
        self.keepPermille = keepPermille
    }
}

/// 有限の品(減ったら戻らない品。旧文明系の刃など)をモジュールに使うときの定義(ModuleDef.finite)。
public struct FiniteUseDef: Codable, Equatable, Sendable {
    /// 使える物。
    public var items: [ItemID]
    /// 使っている間の速さ(千分率。2000 = 2 倍)。
    public var speedPermille: Int
    /// 1 回の処理ごとに減る残り(千分率。残りは 1000 から始まる)。
    public var wearPerCycle: Int

    public init(items: [ItemID], speedPermille: Int, wearPerCycle: Int) {
        self.items = items
        self.speedPermille = speedPermille
        self.wearPerCycle = wearPerCycle
    }
}

/// 地図に置く生産モジュール。
public struct ModuleDef: ContentDef, Equatable {
    /// モジュールの種類 = 工程の種類(RFMatter の RuleBook のキー)。
    public var id: ModuleKindID
    public var cost: [Ingredient]
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
    /// この工程の段を試作で使うのに要る条件(省略時は RFInvention の既定: 炉は置いた炉、水槽は置いた水槽か水辺)。
    public var trial: TrialRequirement?
    // 以下は U7(生産)が足した。どれも省略可能。
    /// 1 回の処理で通す数(既定 1)。採掘口は 1 回 = 鉱脈を 1 回掘る(1 回で 2〜3 個)。
    public var batch: Int?
    /// 工程の無い T1(採集所・井戸など)が 1 回の処理で出す物。
    public var produces: [Yield]?
    /// 1 回の処理で使う物(煮沸場の生水と薪など。工程の段に入れる物とは別)。
    public var consumes: [Ingredient]?
    /// 入口・出口に溜めておける数(既定 12)。
    public var buffer: Int?
    /// 有限の品を使えるか(使うと速いが、減ったら戻らない)。
    public var finite: FiniteUseDef?
    /// 電力(U16。原作の Generator・PowerDraw)。output > 0 なら発電機、draw > 0 なら電力を使うモジュール。
    public var power: PowerDef?
    /// 壊れた物(Placement.destroyedBy がある)を片付けたときに戻る、払った材料の割合(千分率・端数は切り捨て)。
    /// 既定 500。壊れていない物は全部戻る。
    public var refundPermilleBroken: Int?
    /// 火床(炉の熱。U22 が W-03 で使う。形は U21 の HearthDef)。
    public var hearth: HearthDef?

    public init(id: ModuleKindID, cost: [Ingredient], placement: PlacementRule, ports: [PortDef], cycleSeconds: Int,
                specialty: String? = nil, auras: [AuraKindID]? = nil, parameters: Value? = nil,
                trial: TrialRequirement? = nil, batch: Int? = nil, produces: [Yield]? = nil,
                consumes: [Ingredient]? = nil, buffer: Int? = nil, finite: FiniteUseDef? = nil) {
        self.id = id
        self.cost = cost
        self.placement = placement
        self.ports = ports
        self.cycleSeconds = cycleSeconds
        self.specialty = specialty
        self.auras = auras
        self.parameters = parameters
        self.trial = trial
        self.batch = batch
        self.produces = produces
        self.consumes = consumes
        self.buffer = buffer
        self.finite = finite
    }
}

/// 電力の性質(U16。原作 Power/Generator.cs と PlacedModule.PowerDraw)。
/// 供給 = 動いている発電機の output の合計(needsWorker なら付いている人の速さの千分率を掛ける。手回し・発電の名手)。
/// 使う側: 供給が 0 なら止まる。需要(draw の合計)が供給を上回れば速さが半分(原作 IsPowerShortage の 0.5 倍)。
public struct PowerDef: Codable, Equatable, Sendable {
    /// 出す電力(W)。
    public var output: Int?
    /// 使う電力(W)。
    public var draw: Int?
    /// 人が付いている間だけ出す(原作 RequiresManualWork)。
    public var needsWorker: Bool?
    /// 燃料(原作 FuelId)。入口に届いた物を、1 日あたり fuelPerDay 個ずつ燃やす。無くなれば止まる。
    public var fuel: ItemID?
    public var fuelPerDay: Int?

    public init(output: Int? = nil, draw: Int? = nil, needsWorker: Bool? = nil, fuel: ItemID? = nil,
                fuelPerDay: Int? = nil) {
        self.output = output
        self.draw = draw
        self.needsWorker = needsWorker
        self.fuel = fuel
        self.fuelPerDay = fuelPerDay
    }
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

    public init(requiresDeposit: Bool? = nil, requiresWaterAdjacent: Bool? = nil, terrainTags: [String]? = nil,
                reasonIfBlocked: TextID? = nil) {
        self.requiresDeposit = requiresDeposit
        self.requiresWaterAdjacent = requiresWaterAdjacent
        self.terrainTags = terrainTags
        self.reasonIfBlocked = reasonIfBlocked
    }
}

public struct PortDef: Codable, Equatable, Sendable {
    public enum Flow: String, Codable, Sendable { case input, output }
    /// 向き(north = モジュールの正面)を基準にした辺。
    public var side: Direction
    public var flow: Flow
    /// 運ぶ物の種類(R2: 溶けた金属・液体・気体のパイプ)。nil は普通の物。U7 が足した(省略可能)。
    public var transport: String?

    public init(side: Direction, flow: Flow, transport: String? = nil) {
        self.side = side
        self.flow = flow
        self.transport = transport
    }
}

/// 建造物(シェルター・焚き火台・柵・保管・炭焼き窯・研究机…)。
public struct StructureDef: ContentDef, Equatable {
    public var id: StructureKindID
    public var cost: [Ingredient]
    public var footprint: [GridPoint]?
    /// 建てるのにかかるゲーム秒(仲間が手伝うと速い)。
    public var buildSeconds: Int
    /// 効果のタグと値(shelter: 精神力の回復、light: 灯りの半径、storage: 容量、housing: 収容…)。
    public var provides: [String: Int]
    public var auras: [AuraKindID]?
    public var parameters: Value?
    /// 拠点の範囲(整地)の中にだけ建てられるか(既定 true)。柵など外に建てる物は false。持ち主: U8
    public var requiresBaseArea: Bool?
    /// 置ける地形などの制約(nil は問わない)。持ち主: U8
    public var placement: PlacementRule?
    /// 付くと速く建つ専門(タグ)。持ち主: U8
    public var specialty: String?
    /// 火床(燃料で燃え、放っておけば消える。焚き火台)。持ち主: U21
    public var hearth: HearthDef?
    /// provides と auras が効く火床の段の下限(nil は常に効く)。焚き火台は smoldering。持ち主: U21
    public var whenLit: HearthLevel?
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
    // 以下は U8(探索)が足した省略可能な項目。RFContent/Schema/Exploration.swift に説明。
    /// 使う材料(作り直し・修理など)。始めるときに拠点の蓄えから取る。
    public var cost: [Ingredient]?
    /// 有限の部品(残骸の区画など)に対する操作。
    public var partOp: PartOp?
    /// 同じマスでもう一度できるまでの日数(採集のクールダウン。nil・0 は無制限)。
    public var cooldownDays: Int?
    /// 対象のそばに何人いないと進まないか(大きすぎる扉や設備。既定 1)。
    public var requiredPeople: Int?
    /// 手が先(INV-O8)で数える行為の種類(序盤の設計 v0.4 の W-04)。同じ種類の行為を 1 度手でやれば、
    /// その種類の行為を仲間に頼める。nil なら行為 ID が種類。例 "family.scavenge"(漁る)・"family.stoke"(くべる)。
    public var handFamily: HandFamilyID?
    /// 木を伐る行為か(獣の縄張りの入力。RaidLureDef.territory)。持ち主: U21
    public var felling: Bool?
}

/// 得られる物(item か matter のどちらか)。確率は万分率(nil は必ず)。
public struct Yield: Codable, Equatable, Sendable {
    public var item: ItemID?
    public var matter: Matter?
    public var min: Int
    public var max: Int
    public var basisPoints: Int?
    public var unique: Bool?
    /// 減ったら戻らない品の残り(千分率の raw。旧文明系の品など)。持ち主: U8
    public var durability: Int?
    /// 品そのものに持たせる属性(例 "owner": 遺品の持ち主の PersonID)。
    public var attributes: [String: String]?
}

// MARK: - 人

public struct PersonDef: ContentDef, Equatable {
    public var id: PersonID
    /// 名前の見出し(認識の表)。
    public var name: SubjectID
    public var specialties: [String]
    public var ideology: [IdeologyAxisID: Int]
    /// 人が持つ範囲の効果(R3 の声・そばの人の精神力の戻りを早めるなど)。
    public var auras: [AuraKindID]?
    public var parameters: Value?
    /// 得意分野の振る舞い(能力ではなく、配属の効きの範囲。見張りで間に出る、など)。持ち主: U5。
    public var behaviors: [CrewBehavior]?
    /// 初めに属している集団(勢力)。nil = どこにも属さない。
    public var group: GroupID?
    /// 居場所(U16): まだ会っていない間、この種類の POI(EntityID の昇順で最初のもの)にいる。
    /// プレイヤーが歩いて行けば、条件 at・hook "entered" で出来事が起きる(砦のキーパーソンなど)。
    public var home: POIKindID?
    /// 距離の縛り(U16): この人から radius マスより遠くにいる間は働けない(作業の速さ 0)。
    public var tether: Tether?
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
    /// 同じ一言を次に言えるまでのゲーム時間(既定: 直近に言った 3 つとは重ねない)。
    public var cooldownHours: Int?
}

/// 推理の手がかり(端末の断片・仲間の知識・手が知っていた手順・図鑑の空欄の命名の手がかり)。
/// 条件が成り立つとノートに出典つきで載る(RFInvention)。出典は中立の見出し("source:hand" など)で、
/// 見え方は認識の層が引く(後で「誰の・何の知識だったか」の見え方が変わる)。
public struct HintDef: ContentDef, Equatable {
    public var id: HintID
    public var from: PersonID?
    /// 載る条件(乱数 chance は使わない: 評価は乱数を引かない evaluatePure で、chance は成り立たない扱い)。
    public var when: Condition
    public var about: SubjectID
    public var text: TextID
    /// 出典(認識の表の見出し)。
    public var source: SubjectID
    /// 何を言っているか(機械が読める形。RFContent/Schema/Invention.swift)。省略可。
    public var claims: [HintClaim]?
    /// 図鑑の空欄(命名からの類推)に付く手がかりなら、その名前。載ると図鑑に影の行が出る。省略可。
    public var target: MatterName?

    public init(id: HintID, from: PersonID? = nil, when: Condition, about: SubjectID, text: TextID, source: SubjectID,
                claims: [HintClaim]? = nil, target: MatterName? = nil) {
        self.id = id
        self.from = from
        self.when = when
        self.about = about
        self.text = text
        self.source = source
        self.claims = claims
        self.target = target
    }
}

// MARK: - 研究・力・敵

/// 研究パッケージ(原作 ResearchPackage)。研究机に付いた人が進める。完了で解禁と効果。
/// 追加した項目はどれも省略可能(U10)。補助の型は Schema/Research.swift。
public struct ResearchDef: ContentDef, Equatable {
    public var id: ResearchID
    /// 必要な研究の点の合計(nodes があれば nodes の点の合計が優先)。
    public var points: Int
    /// 選べる条件(前提のパッケージは researchDone で書く)。
    public var requires: Condition?
    /// この種類の建造物でしか進まない(nil は研究の建造物ならどれでも)。
    public var station: StructureKindID?
    /// 完了で解禁するもの。
    public var unlocks: [UnlockTarget]
    public var effects: [Effect]?
    /// 中の段(原作のノード。木炭焼成・叩き板金…)。順に進み、段ごとに解禁と効果がある。
    public var nodes: [ResearchNodeDef]?
    /// 一覧に出る条件(存在を伏せる研究)。nil は常に出る。名前を伏せるのは認識の表(research:<id>)。
    public var visibleWhen: Condition?
    /// 進む時間帯(既定は昼だけ。天体の観測のような夜の研究は nightWork を入れる)。
    public var phases: [DayPhase]?
    /// 選んだときに使う物(部品を組んで調べる研究など)。
    public var cost: [Ingredient]?
}

/// 研究パッケージの中の段。
public struct ResearchNodeDef: Codable, Equatable, Sendable {
    /// 段の名前の見出し(認識の表。名前は文字列表)。
    public var id: String
    public var points: Int
    public var unlocks: [UnlockTarget]?
    public var effects: [Effect]?

    public init(id: String, points: Int, unlocks: [UnlockTarget]? = nil, effects: [Effect]? = nil) {
        self.id = id
        self.points = points
        self.unlocks = unlocks
        self.effects = effects
    }
}

/// スキル(人の技能。道筋を増やす選択)。習得には時間がかかり、その間は「学ぶ時期」(BEAT-15)。
public struct SkillDef: ContentDef, Equatable {
    public var id: SkillID
    /// 選べる条件(研究の完了など)。
    public var requires: Condition?
    public var unlocks: [UnlockTarget]?
    public var parameters: Value?
    /// 習得にかかるゲーム時間(nil・0 はすぐ)。
    public var hours: Int?
    /// この種類の建造物に付いている間だけ進む(nil はどこでも・いつでも進む)。
    public var station: StructureKindID?
    /// 身につけた人の作業への効き(成功率・速さ・量)。
    public var modifiers: [WorkModifier]?
    public var effects: [Effect]?
    /// 一覧に出る条件(nil は常に)。
    public var visibleWhen: Condition?
}

/// 特別な力(代償型)。名前・説明は認識の表(ability:<id>)で、解禁の事実まで出さない。
/// 力は配属の効き(passives)と、使う行為(effects + cost)の 2 つの形を持てる。
public struct AbilityDef: ContentDef, Equatable {
    public var id: AbilityID
    public var parameters: Value?
    /// 生まれつき持っている人。
    public var holders: [PersonID]?
    /// 存在が見えてよい条件(nil は見せない = R1 の伏線の力)。見えない力は使えず、画面にも出ない。
    public var visibleWhen: Condition?
    /// 一員でいる間の作業への効き(配属の効き。BEAT-25)。
    public var passives: [WorkModifier]?
    /// 一員でいる間、その人を中心に付く範囲の効果(獣が寄らない、など)。
    public var auras: [AbilityAura]?
    /// 使ったときに世界に起きること(場所は PlaceSelector.trigger = 使った場所)。
    public var effects: [Effect]?
    /// 使う代償。
    public var cost: AbilityCost?
    /// 次に使えるまでのゲーム時間。
    public var cooldownHours: Int?
    /// 力の元の最大(夜明けに満ちる。足りない分は体で払う)。
    public var reserveMax: Int?
}

// EnemyDef(敵)は Schema/Combat.swift(持ち主 U9)。

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
        /// 拠点全体の数値への寄与(上積み)。
        case statPerHour(stat: StatID, amount: Int)
    }

    public var id: AuraKindID
    public var modifiers: [Modifier]
    /// 誰に効くか(nil は全員。ただし drawTowardSource はノアと中心の人には、ここで名指ししない限り効かない)。
    public var affects: [PersonID]?
    /// 置いた物・人の定義から付くときの半径(マス)。効果 addAura で半径を書かないときもこれ。
    public var radius: Int?
    /// 距離で効きが変わる(U16): 範囲の中心がこの人から radius マスより離れている間は、範囲が効かない
    /// (ある人の静けさは、その人がノアのそばにいる間だけ獣を寄せない、など)。
    public var requiresNear: Tether?
}

/// ある人からの距離の縛り(チェビシェフ距離。同じ層)。範囲の効果(AuraDef.requiresNear)と人(PersonDef.tether)が使う。
public struct Tether: Codable, Equatable, Sendable {
    public var person: PersonID
    public var radius: Int

    public init(person: PersonID, radius: Int) {
        self.person = person
        self.radius = radius
    }
}

/// 拠点全体の数値(内訳と合計・暦…)。見せない値もここ。見せ方は認識の表。
public struct StatDef: ContentDef, Equatable {
    public var id: StatID
    public var initial: Int
    /// 1 日あたりの基礎の増減(千分率)。内訳を別の数値に分けて持てる(基礎 + 採掘の上積み = 合計)。
    public var perDay: Int?
    /// 合計として他の数値を足し合わせる(内訳を内部に持ち、開示で内訳を見せる)。
    public var sumOf: [StatID]?
    /// この値を越えたら(上りでも下りでも)出来事 statCrossed を出す(警告・期限の引き金。raw)。
    public var marks: [Int]?
    /// 回る値(暦など): この値で割った余りにする(raw)。
    public var wrap: Int?
    /// 画面で赤く出す範囲(raw。isAlert を使う)。
    public var alertBelow: Int?
    public var alertAtLeast: Int?
    /// 掘った量で上がる項(U16。OPEN-S2・BEAT-18)。鉱脈の減った回数を数え、per 回ごとに amount(raw)を足す。
    /// perDay・範囲の上積みとは別の項。掘らなければ 0 なので、他の進み方を変えない。
    public var mined: MinedTerm?

    /// 掘った量の項。ores = 鉱脈の種類(DepositCategory の名前)か、組成の物質(MineralID)のどれかに合う鉱脈を数える。
    public struct MinedTerm: Codable, Equatable, Sendable {
        public var ores: [String]
        /// 何回掘るごとに(既定 1)。
        public var per: Int?
        public var amount: Int

        public init(ores: [String], per: Int? = nil, amount: Int) {
            self.ores = ores
            self.per = per
            self.amount = amount
        }
    }

    public init(id: StatID, initial: Int, perDay: Int? = nil, sumOf: [StatID]? = nil, marks: [Int]? = nil,
                wrap: Int? = nil, alertBelow: Int? = nil, alertAtLeast: Int? = nil, mined: MinedTerm? = nil) {
        self.mined = mined
        self.id = id
        self.initial = initial
        self.perDay = perDay
        self.sumOf = sumOf
        self.marks = marks
        self.wrap = wrap
        self.alertBelow = alertBelow
        self.alertAtLeast = alertAtLeast
    }
}

/// 失敗の規則。期限は日数でなく値で判定する。
public struct FailureRuleDef: ContentDef, Equatable {
    public var id: FailureRuleID
    public var when: Condition
    public var cause: TextID
    /// 「失って続ける」を選んだとき、この原因を解く効果(飢えの日数を戻す・数値を下げる…)。
    /// 適用しても失敗の規則がまだ成り立つなら「失って続ける」は選べない(すぐ同じ失敗に戻らないように)。
    public var onContinue: [Effect]?
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
        /// 条件が成り立っていたゲーム分(毎ステップ判定)。
        case minutesWhere(condition: Condition)
        /// 拠点の中心から最も遠くまで行ったマス数(チェビシェフ距離の最大。person が nil なら一員の誰か)。探索の届いた範囲。
        case farthestFromBase(person: PersonID?)
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
        /// どの DomainEvent の後に調べるか(hook の名前)。nil なら夜明けと毎時("hour")。
        /// 空の配列なら自分からは起きない(効果 fire / schedule でだけ起きる)。
        public var on: [String]?
        public var when: Condition
    }

    public enum Repeat: Codable, Equatable, Sendable {
        case once
        /// 前に起きてから hours ゲーム時間たてば、また起きる。
        case cooldown(hours: Int)
        /// 1 日(夜明けから次の夜明けまで)に 1 回まで。
        case oncePerDay
        case always
    }

    public var id: EventID
    public var trigger: Trigger
    public var repeats: Repeat?
    /// 同じ hook で複数が成り立つとき、大きい方から調べる(既定 0。同じなら ID 順)。
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
        /// 行の名前(答えを置く行を指す。answer があるときは必須)。
        public var id: String?
        /// この行に、プレイヤー自身の来歴から「答え」を 1 つ置ける(BEAT-07)。
        public var answer: AnswerSlotDef?
        /// 行の横に並べる数(鍛えた量・最高の純度・失った人数など。来歴から数える)。
        public var measure: SheetMeasure?

        public init(subject: SubjectID, note: TextID? = nil, when: Condition? = nil, id: String? = nil,
                    answer: AnswerSlotDef? = nil, measure: SheetMeasure? = nil) {
            self.subject = subject
            self.note = note
            self.when = when
            self.id = id
            self.answer = answer
            self.measure = measure
        }
    }

    public var id: SheetID
    public var title: SubjectID
    public var rows: [Row]
    /// 開けるようになる条件。
    public var when: Condition
    /// 記録の並びの席の数(1...slots)。entries に無い番号は「空いた席」として並び、数えられる(BEAT-05)。
    public var slots: Int?
    /// 記録の 1 件ずつ(席の番号・名前・人)。開くとプレイヤーの試作と同じ形の工程表になる。
    public var entries: [SheetEntryDef]?
    /// 記録の 1 件を開いたときの既定の行。entry.rows があればそちら。
    public var entryRows: [Row]?
    /// この表の装置で、人に技能を書き足せる(BEAT-06)。
    public var imprint: ImprintDef?
    /// この表は乗る人の名簿(BEAT-29)。
    public var manifest: ManifestDef?
}

/// 記録の並びの 1 件。
public struct SheetEntryDef: Codable, Equatable, Sendable {
    /// 席の番号(1 から)。
    public var slot: Int
    /// 名前(認識の表)。
    public var subject: SubjectID
    /// 世界の人(仲間の記録が見つかる、など)。
    public var person: PersonID?
    public var rows: [SheetDef.Row]?
    /// 並びに出る条件(既定: いつも)。
    public var when: Condition?
}

/// 答えの席: 置ける来歴の問い合わせ(どれかに合えば置ける)。
public struct AnswerSlotDef: Codable, Equatable, Sendable {
    public var accepts: [ProvenanceQuery]
}

/// 行の横の数。
public enum SheetMeasure: Codable, Hashable, Sendable {
    /// 合う来歴の count の合計。
    case count(query: ProvenanceQuery)
    /// 合う来歴の detail[key](整数)の最大。純度など。
    case maxDetail(query: ProvenanceQuery, key: String)
}

/// 装置で技能を書き足す(習得の日数を飛ばす)。使うかどうかは一人ずつプレイヤーが決め、本人が拒むこともある。
public struct ImprintDef: Codable, Equatable, Sendable {
    /// 書き足せる技能。
    public var skills: [SkillID]
    /// 使える条件(装置を直した、など)。
    public var when: Condition?
    /// 書き足せる人(一員で生きている人のうち、全部に合う人)。
    public var targets: [PersonTest]?
    /// 本人が拒む条件(全部に合えば拒む。思想・関係・記憶で書く)。
    public var refuseWhen: [PersonTest]?
    /// 使った記録に付ける印(仲間の思想がこれで賛否を言う)。
    public var tags: [ProvenanceTag]?
    /// 使わなかった記録に付ける印。
    public var declineTags: [ProvenanceTag]?
}

/// 乗る人の名簿。仲間は自分で「乗る / 残る」を言う。
public struct ManifestDef: Codable, Equatable, Sendable {
    /// 名簿が開く条件(コンテンツが決める)。
    public var when: Condition?
    /// 乗れる人数(ノアを含む)。
    public var capacity: Int?
    /// 仲間の言い分。上から順に、tests に全部合う最初のものを言う。どれにも合わない人は何も言わない。
    public var leanings: [LeaningDef]
}

public struct LeaningDef: Codable, Equatable, Sendable {
    public var tests: [PersonTest]
    /// 乗る(true)/ 残る(false)。
    public var aboard: Bool
    /// 譲らない(プレイヤーが逆にできない)。
    public var firm: Bool?
    /// 言うときの一言の文脈(LineDef.context。無ければ "boarding.aboard" / "boarding.stay")。
    public var line: String?
}

public struct ObjectiveDef: ContentDef, Equatable {
    public var id: ObjectiveID
    public var text: TextID
    public var completeWhen: Condition
    public var effects: [Effect]?
    /// これが成り立てば失敗(達成より先に調べない。達成が先)。
    public var failWhen: Condition?
}

public struct ChapterDef: ContentDef, Equatable {
    public var id: ChapterID
    public var title: TextID
}

public struct EndingDef: ContentDef, Equatable {
    public var id: EndingID
    /// 自分から届く条件(効果 ending で直接届くこともある)。
    public var when: Condition
    public var scene: SceneID?
    /// 届いたときの効果(帰る人・残る人が分かれる、など)。
    public var effects: [Effect]?
}

/// 所見(RFMatter の FindingID)の文。引数(燃料の名前など)は {0} {1} で埋める。
public struct FindingDef: ContentDef, Equatable {
    public var id: FindingID
    public var text: TextID
}

/// 始まりの世界。
public struct StartDef: Codable, Equatable, Sendable {
    /// 最初からいる一員(ノアを含む)。
    public var members: [PersonID]
    /// 存在だけを内部に持つ人(まだ会っていない)。
    public var unmet: [PersonID]?
    public var items: [Yield]
    public var facts: [FactID]
    public var unlocks: [UnlockTarget]
    public var objectives: [ObjectiveID]?
    public var chapter: ChapterID?
    /// 始めに起こす出来事(目覚めの場面など)。
    public var events: [EventID]?

    public init(members: [PersonID], unmet: [PersonID]? = nil, items: [Yield] = [], facts: [FactID] = [],
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
