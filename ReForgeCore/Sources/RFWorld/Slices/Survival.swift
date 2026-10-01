import RFKernel

/// 拠点全体の生存の圧と環境。持ち主: RFSurvival。個人の体は PersonState.body。
public struct SurvivalState: Codable, Equatable, Sendable {
    /// 拠点全体の数値。どれを持つか・どう見せるかはコンテンツ(StatDef と認識の表)。
    public var stats: [StatID: Milli] = [:]
    /// 食料・水が尽きてからの日数(餓死・脱水の判定)。
    public var daysWithoutFood: Int = 0
    public var daysWithoutWater: Int = 0
    /// 天候・季節(R2)。
    public var environment: EnvironmentState = EnvironmentState()

    public init() {}
}

public struct EnvironmentState: Codable, Equatable, Sendable {
    /// いまの天候(コンテンツの ID 文字列。R2)。
    public var weather: String?
    /// 季節の進み(日数)。R2。
    public var seasonDay: Int = 0

    public init() {}
}
