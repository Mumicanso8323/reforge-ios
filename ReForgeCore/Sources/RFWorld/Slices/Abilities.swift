import RFKernel

/// 特別な力。持ち主: RFAbilities。R1 は伏線(ノアの手ざわりで純度の見当が付く)だけ。
/// 名前・説明は認識の層が引く(この層の存在そのものを画面で名指ししない)。
public struct AbilitiesState: Codable, Equatable, Sendable {
    /// 人 → 力 → 熟達(点)。
    public var mastery: [PersonID: [AbilityID: Int]] = [:]
    /// 人 → 力の元になる値(R3)。
    public var reserve: [PersonID: Milli] = [:]

    public init() {}
}
