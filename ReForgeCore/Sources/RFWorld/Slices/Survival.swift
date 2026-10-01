import RFKernel

/// 拠点全体の生存の圧と環境。持ち主: RFSurvival。個人の見える体は PersonState.body(これも RFSurvival が書く)。
///
/// 隠れた値(REQ-S11)は stats に入れる: 内訳(基礎の上昇・上積み)と合計(StatDef.sumOf)、暦(StatDef.wrap)、
/// 餓死・脱水の判定に使う日数(Milli の日数)、蓄えが何日もつか。見せ方は認識の表の StatDisplay が決める。
/// 失敗・期限は日数でなくこの値で判定する(FailureRuleDef.when の stat 条件)。
public struct SurvivalState: Codable, Equatable, Sendable {
    /// 拠点全体の数値(raw = 千分率)。どれを持つか・どう見せるかはコンテンツ(StatDef と認識の表)。
    public var stats: [StatID: Milli] = [:]
    /// 1 日・1 時間あたりの増減を固定ステップに割ったときの端数(整数で繰り越す。刻みによらず一致させるため)。
    public var statCarry: [StatID: Int64] = [:]
    /// しきい値(StatDef.marks)を越えたかを調べるための、前に見た値。
    public var marksSeen: [StatID: Milli] = [:]
    /// 人ごとの内部の値(食事の進み・空腹の始まり・端数)。見える値は PersonState.body。
    public var vitals: [PersonID: Vitals] = [:]
    /// 人ごとの作業の速さ(千分率。1000 = 普通は持たない)。他のシステムは workPermille(for:) で読む。
    public var work: [PersonID: Int] = [:]
    /// 全員が食べられずにいる・飲めずにいる日数(整数。表示と古い読み手のため。判定は stats の Milli の日数)。
    public var daysWithoutFood: Int = 0
    public var daysWithoutWater: Int = 0
    /// 天候(R2)。季節は暦(stats の wrap つきの値)から進む。
    public var environment: EnvironmentState = EnvironmentState()

    public init() {}

    /// その人の作業の速さ(千分率。空腹・渇き・状態・精神力の低さを掛け合わせたもの)。範囲の効果の workSpeed は別に掛ける。
    public func workPermille(for person: PersonID) -> Int { work[person] ?? 1000 }

    public func stat(_ id: StatID) -> Milli { stats[id] ?? .zero }
}

/// 人ごとの内部の値。
public struct Vitals: Codable, Equatable, Sendable {
    /// 次の 1 食までの進み(単位: 秒 × 千分率。1 日の秒 × 1000 で 1 食)。
    public var foodProgress: Int64 = 0
    public var waterProgress: Int64 = 0
    /// 食べられずにいる始まり(食べれば消える)。
    public var hungrySince: GameTime?
    public var thirstySince: GameTime?
    /// 先に口にした分(次の 1 回の消費に充てる。最大 1 回分)。
    public var foodCredit: Int = 0
    public var waterCredit: Int = 0
    /// 体の値・状態の回復の端数(名前 → 端数)。
    public var carry: [String: Int64] = [:]

    public init() {}
}

public struct EnvironmentState: Codable, Equatable, Sendable {
    /// いまの天候(コンテンツの ID 文字列。R2)。
    public var weather: String?

    public init() {}
}
