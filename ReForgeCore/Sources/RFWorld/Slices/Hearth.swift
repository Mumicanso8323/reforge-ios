import RFKernel

/// 火床の動き(焚き火台の StructureRuntime.hearth・炉の ModuleRuntime.hearth)。持ち主: U21(炉の熱は U22 が足す)
/// 番をする人はここに持たない(仲間の配属が正本。RFRules の Hearths.isTended)。
public struct HearthState: Codable, Equatable, Sendable {
    /// 残りの燃える時間(ゲーム秒 × 1000)。
    public var fuel: Int = 0
    /// 火が点いているか(燃料が尽きると false。燃料を足しても点かない。点けるのは点け直し)。
    public var lit: Bool = false
    /// 埋めてあるか(減りが少なく、灯りは小さい)。
    public var banked: Bool = false
    /// 薪の山(火のそばに積んだ燃料の数。番がくべる)。
    public var pile: Int = 0
    /// 日没から今まで一度も消えていないか(夜明けに夜の数を数える)。
    public var litSinceDusk: Bool = false
    /// 炉の熱(℃ × 1000。炉だけ。nil は冷えている)。持ち主: U22
    public var heat: Int?
    /// 予熱の残り(ゲーム秒。nil は予熱していない)。
    public var preheatLeft: Int?
    /// 燃料の使いかけ(百万分の 1 個)。
    public var burnCarry: Int?
    /// いま燃えている燃料。
    public var fuelItem: ItemID?

    public init(fuel: Int = 0, lit: Bool = false, banked: Bool = false, pile: Int = 0, litSinceDusk: Bool = false) {
        self.fuel = fuel
        self.lit = lit
        self.banked = banked
        self.pile = pile
        self.litSinceDusk = litSinceDusk
    }

    enum CodingKeys: String, CodingKey { case fuel, lit, banked, pile, litSinceDusk, heat, preheatLeft, burnCarry, fuelItem }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        fuel = try c.decodeIfPresent(Int.self, forKey: .fuel) ?? 0
        lit = try c.decodeIfPresent(Bool.self, forKey: .lit) ?? false
        banked = try c.decodeIfPresent(Bool.self, forKey: .banked) ?? false
        pile = try c.decodeIfPresent(Int.self, forKey: .pile) ?? 0
        litSinceDusk = try c.decodeIfPresent(Bool.self, forKey: .litSinceDusk) ?? false
        heat = try c.decodeIfPresent(Int.self, forKey: .heat)
        preheatLeft = try c.decodeIfPresent(Int.self, forKey: .preheatLeft)
        burnCarry = try c.decodeIfPresent(Int.self, forKey: .burnCarry)
        fuelItem = try c.decodeIfPresent(ItemID.self, forKey: .fuelItem)
    }
}

/// 火床への操作(プレイヤーが直接する分。BaseCommand.hearth)。
public enum HearthOp: Codable, Equatable, Sendable {
    /// 拠点の蓄えから燃料を 1 つくべる。
    case stoke(item: ItemID)
    /// 拠点の蓄えから薪の山に積む。
    case stack(item: ItemID, count: Int)
    /// 点け直す(from: 火を移す元の燃えている火床。nil は定義が火種を要らないときだけ)。
    case ignite(from: EntityID?)
    /// 火を埋める。
    case bank
    /// 冷えた炉の予熱を始める(炉の入口か拠点の蓄えから予熱の燃料を払う。W-03)。
    case preheat
}
