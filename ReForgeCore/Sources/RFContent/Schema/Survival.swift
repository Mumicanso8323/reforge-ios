import RFKernel

// 生存の規則(CORE-07)。持ち主: U4(RFSurvival)。JSON の最上位キー "survival"(単一の設定。後の層が勝つ)。
//
// 単位の約束(どれも整数):
//   - 体の値(BodyState の health・stamina・satiety・hydration・mind)は 0〜100 の Milli。
//     「1 時間あたり」の増減は Milli の raw(千分率)で書く(-250 = 1 時間に 0.25 減る)。
//   - 「1 日」はゲームの 1 日(昼 + 夜。ClockDef の dayGameHours + nightGameHours)。
//   - 千分率(permille)は 1000 = 普通。
//
// 体の規則は全員に共通(結合設計 REQ-S5: ノアだけを丈夫にしない)。だからこの定義には人ごとの項目を置かない。

/// 生存の規則の全部。nil の項目は既定値(order.md §5.6 の R1 の値)を使う。
public struct SurvivalDef: Codable, Equatable, Sendable {
    /// 食べ物・飲み物(並びの順に自動で減らす)。
    public var consumables: [ConsumableDef]
    /// 1 人 1 日の量(千分率。1000 = 1 個)。原作 GameState.cs:693-697。
    public var foodPerPersonPerDay: Int?
    public var waterPerPersonPerDay: Int?
    /// 空腹(食べられずにいる)間の作業の速さ(千分率)。R1 の仮値 500 = −50%。
    public var hungryWorkPermille: Int?
    /// 渇いている間の作業の速さ(千分率)。既定 500。
    public var thirstyWorkPermille: Int?

    /// 精神力: 外にいる間の 1 時間あたりの増減(raw)。既定 -250。
    public var mindOutsidePerHour: Int?
    /// 精神力: シェルターの中にいる間の 1 時間あたりの増減(raw)。既定 +2000。
    public var mindShelterPerHour: Int?
    /// シェルターとみなす建造物の provides のタグ。既定 "shelter"。
    public var shelterTag: String?
    /// 精神力がこの値(raw)を下回ると作業が遅くなる。既定 20000(= 20)。
    public var mindLowThreshold: Int?
    /// そのときの作業の速さ(千分率)。既定 750。
    public var mindLowWorkPermille: Int?

    /// スタミナ: 歩いた地形の moveCost 1 あたりの増減(raw)。既定 -5(平地 10 のマス 1 つで 0.05 減る)。
    /// 歩いたことは RFCrew の出来事 walked で受ける。
    public var staminaPerMoveCost: Int?
    /// スタミナの 1 時間あたりの回復(raw)。既定 +1500。
    public var staminaRegenPerHour: Int?
    /// スタミナがこの値(raw)を下回ると作業が遅くなる。既定 10000(= 10)。
    public var staminaLowThreshold: Int?
    /// そのときの作業の速さ(千分率)。既定 750。
    public var staminaLowWorkPermille: Int?

    /// 学ぶ時期(研究・スキルの習得)とみなす建造物の provides のタグ。既定 ["research"]。
    /// その建造物に付いている(配属か、いまの動作)人は「学んでいる」。
    public var studyTags: [String]?
    /// 学んでいる人の食料の消費(千分率)。BEAT-15(全員に共通の規則)。既定 1500。
    public var studyFoodPermille: Int?

    /// 体の状態(中毒・傷…)。conditions のキー = id。
    public var ailments: [AilmentDef]?
    /// 効果 injure(傷)で付く状態。既定 "ailment.wound"。
    public var woundAilment: StatID?
    /// 体力の自然な回復(1 時間あたり raw)。状態が無いときだけ。既定 +500。
    public var healthRegenPerHour: Int?

    /// 体と数値を進める区切り(ゲーム秒)。既定 300(5 ゲーム分)。ステップの幅(15 秒)の倍数にする。
    /// 空腹の作業の遅れ・精神力の増減・蓄えの日数などは、この区切りごとに変わる。
    public var tickSeconds: Int?

    /// 生存が書く拠点全体の値の名前(失敗の規則・画面はこの値を見る。日数は Milli の日数)。
    public var statNames: StatNames?

    public init(consumables: [ConsumableDef] = [], foodPerPersonPerDay: Int? = nil, waterPerPersonPerDay: Int? = nil,
                hungryWorkPermille: Int? = nil, thirstyWorkPermille: Int? = nil, mindOutsidePerHour: Int? = nil,
                mindShelterPerHour: Int? = nil, shelterTag: String? = nil, mindLowThreshold: Int? = nil,
                mindLowWorkPermille: Int? = nil, studyTags: [String]? = nil, studyFoodPermille: Int? = nil,
                ailments: [AilmentDef]? = nil, woundAilment: StatID? = nil, healthRegenPerHour: Int? = nil,
                statNames: StatNames? = nil) {
        self.consumables = consumables
        self.foodPerPersonPerDay = foodPerPersonPerDay
        self.waterPerPersonPerDay = waterPerPersonPerDay
        self.hungryWorkPermille = hungryWorkPermille
        self.thirstyWorkPermille = thirstyWorkPermille
        self.mindOutsidePerHour = mindOutsidePerHour
        self.mindShelterPerHour = mindShelterPerHour
        self.shelterTag = shelterTag
        self.mindLowThreshold = mindLowThreshold
        self.mindLowWorkPermille = mindLowWorkPermille
        self.studyTags = studyTags
        self.studyFoodPermille = studyFoodPermille
        self.ailments = ailments
        self.woundAilment = woundAilment
        self.healthRegenPerHour = healthRegenPerHour
        self.statNames = statNames
    }

    /// 生存が書く値の名前。
    public struct StatNames: Codable, Equatable, Sendable {
        /// 全員が食べられずにいる長さ(Milli の日数)。餓死の規則はこれで書く(原作: 5 日)。
        public var daysWithoutFood: StatID?
        /// 全員が飲めずにいる長さ(Milli の日数)。脱水の規則はこれで書く(原作: 3 日)。
        public var daysWithoutWater: StatID?
        /// 蓄えが何日もつか(Milli の日数。自動で減らす物だけ数える)。上の帯に出す。
        public var foodDays: StatID?
        public var waterDays: StatID?
        /// 暦(隠れた値。1 年の中の何日目か、Milli の日数)。値そのものはコンテンツの StatDef(perDay 1000・wrap)で進む。
        /// 季節(R2)はこの値から決める。ここは「どの値が暦か」の名前だけ。
        public var calendar: StatID?

        public init(daysWithoutFood: StatID? = nil, daysWithoutWater: StatID? = nil, foodDays: StatID? = nil,
                    waterDays: StatID? = nil, calendar: StatID? = nil) {
            self.calendar = calendar
            self.daysWithoutFood = daysWithoutFood
            self.daysWithoutWater = daysWithoutWater
            self.foodDays = foodDays
            self.waterDays = waterDays
        }
    }

    // MARK: 既定値を埋めた読み方

    public static let defaultTickSeconds: Int64 = 300
    public var tick: Int64 { tickSeconds.map { Int64(max(1, $0)) } ?? Self.defaultTickSeconds }
    public var foodPerDay: Int { foodPerPersonPerDay ?? 1000 }
    public var waterPerDay: Int { waterPerPersonPerDay ?? 1000 }
    public var hungryWork: Int { hungryWorkPermille ?? 500 }
    public var thirstyWork: Int { thirstyWorkPermille ?? 500 }
    public var mindOutside: Int { mindOutsidePerHour ?? -250 }
    public var mindShelter: Int { mindShelterPerHour ?? 2000 }
    public var shelter: String { shelterTag ?? "shelter" }
    public var mindLow: Int { mindLowThreshold ?? 20000 }
    public var mindLowWork: Int { mindLowWorkPermille ?? 750 }
    public var study: [String] { studyTags ?? ["research"] }
    public var staminaPerCost: Int { staminaPerMoveCost ?? -5 }
    public var staminaRegen: Int { staminaRegenPerHour ?? 1500 }
    public var staminaLow: Int { staminaLowThreshold ?? 10000 }
    public var staminaLowWork: Int { staminaLowWorkPermille ?? 750 }
    public var studyFood: Int { studyFoodPermille ?? 1500 }
    public var wound: StatID { woundAilment ?? "ailment.wound" }
    public var healthRegen: Int { healthRegenPerHour ?? 500 }
    public var daysWithoutFoodStat: StatID { statNames?.daysWithoutFood ?? "stat.days_without_food" }
    public var daysWithoutWaterStat: StatID { statNames?.daysWithoutWater ?? "stat.days_without_water" }
    public var foodDaysStat: StatID { statNames?.foodDays ?? "stat.food_days" }
    public var waterDaysStat: StatID { statNames?.waterDays ?? "stat.water_days" }
    public var calendarStat: StatID { statNames?.calendar ?? "stat.calendar" }

    public func consumable(_ item: ItemID) -> ConsumableDef? { consumables.first { $0.item == item } }
    public func ailment(_ id: StatID) -> AilmentDef? { ailments?.first { $0.id == id } }
}

/// 食べ物・飲み物 1 種。
public struct ConsumableDef: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case food, water }

    public var item: ItemID
    public var kind: Kind
    /// 1 個で何人分か(既定 1)。
    public var portions: Int?
    /// 自動で減らすか(既定 true)。生水のように危険な物は false にして、飲むかどうかをプレイヤーが選ぶ。
    public var auto: Bool?
    /// 口にしたときの危険(生水の中毒など)。煮沸した水には付けない。
    public var risk: RiskDef?

    public init(item: ItemID, kind: Kind, portions: Int? = nil, auto: Bool? = nil, risk: RiskDef? = nil) {
        self.item = item
        self.kind = kind
        self.portions = portions
        self.auto = auto
        self.risk = risk
    }

    public var isAuto: Bool { auto ?? true }
}

/// 口にしたときの危険。確率は万分率で、生存の乱数の流れで引く(決定的)。
public struct RiskDef: Codable, Equatable, Sendable {
    public var basisPoints: Int
    /// 当たったときに付く状態と重さ。
    public var ailment: StatID?
    public var severity: Int?
    /// 当たったときの体の値の変化(raw)。"mind": -2000 など。
    public var body: [String: Int]?

    public init(basisPoints: Int, ailment: StatID? = nil, severity: Int? = nil, body: [String: Int]? = nil) {
        self.basisPoints = basisPoints
        self.ailment = ailment
        self.severity = severity
        self.body = body
    }
}

/// 体の状態 1 種(中毒・傷…)。重さは整数(単位は定義ごと。回復と同じ単位)。
public struct AilmentDef: Codable, Equatable, Sendable {
    public var id: StatID
    /// この状態がある間の作業の速さ(千分率)。
    public var workPermille: Int?
    /// この状態がある間の体の値の 1 時間あたりの増減(raw)。
    public var bodyPerHour: [String: Int]?
    /// 1 日あたりに減る重さ(全員に共通。BEAT-15)。
    public var recoveryPerDay: Int
    /// 重さの上限(nil は無し)。
    public var maxSeverity: Int?

    public init(id: StatID, workPermille: Int? = nil, bodyPerHour: [String: Int]? = nil, recoveryPerDay: Int,
                maxSeverity: Int? = nil) {
        self.id = id
        self.workPermille = workPermille
        self.bodyPerHour = bodyPerHour
        self.recoveryPerDay = recoveryPerDay
        self.maxSeverity = maxSeverity
    }
}

extension StatDef {
    /// 画面で赤く出すか(alertBelow 未満・alertAtLeast 以上)。値は raw。
    public func isAlert(_ raw: Int64) -> Bool {
        if let b = alertBelow, raw < Int64(b) { return true }
        if let a = alertAtLeast, raw >= Int64(a) { return true }
        return false
    }
}
