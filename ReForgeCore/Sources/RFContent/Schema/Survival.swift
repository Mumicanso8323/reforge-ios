import RFKernel

/// 生存の規則(食べ物・飲み物・1 人 1 日の量・空腹の作業速度・精神力・状態の回復…)。
/// 持ち主: U4(時間と生存)。中身は U4 が足す(項目はすべて省略可能にする)。後の層が丸ごと勝つ。
public struct SurvivalDef: Codable, Equatable, Sendable {
    public init() {}
}
