import RFKernel

/// 人ごとの能力。持ち主: RFAbilities。
/// 名前・説明と画面に出す値はコンテンツと認識の層が決める。
public struct AbilitiesState: Codable, Equatable, Sendable {
    /// 人 → 力 → 熟達(使った回数)。
    public var mastery: [PersonID: [AbilityID: Int]] = [:]
    /// 人 → 力の元(夜明けに最大まで満ちる。千分率の固定小数)。
    public var reserve: [PersonID: Milli] = [:]
    /// 人 → 力 → 次に使える時刻。
    public var cooldowns: [PersonID: [AbilityID: GameTime]] = [:]
    /// 力が付けている範囲の効果(人 → 範囲の実体)。持ち主が一員でなくなれば外す。
    public var auras: [PersonID: [EntityID]] = [:]

    public init() {}

    public func mastery(_ p: PersonID, _ a: AbilityID) -> Int { mastery[p]?[a] ?? 0 }
}
