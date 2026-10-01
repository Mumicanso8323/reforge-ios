import RFKernel

/// 特別な力。持ち主: RFAbilities。R1 は伏線(ノアの手ざわりで純度の見当が付く)だけ。
/// 名前・説明は認識の層が引く(この層の存在そのものを画面で名指ししない)。
///
/// ここの値は画面の Frame に出さない(REQ-S5: ノアだけの数値を比べられる形にしない)。
/// 見せるのは、力が見えてよい段階(AbilityDef.visibleWhen)になってから、認識の層を通したものだけ。
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
