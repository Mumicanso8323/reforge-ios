import RFContent
import RFKernel
import RFMatter
import RFWorld

/// 武器の強さ = 素材の純度と硬さ(発明が戦闘に返る)。
///
/// - 硬さは RFMatter の規則の表の指数(0〜100。剛 85・柔 40・叩いた 60…)。割れ(粘り 0)は半分。
/// - 上積み = 硬さ × 純度 × 純度の効き(ナイン方式)÷ CombatDef.weaponDivisor。
///   純度 45% の鉄の板(硬さ 60)で +5、純度 70% の剛鉄の棒(硬さ 85)で +12。
/// - 間合いは形で決まる(棒は槍 1...2、板は刃 0...1、それ以外は殴る 0...0)。
/// - 計算は整数だけ(対数は表で引く。端末で末位がずれて走行が分かれないように)。
public struct WeaponProfile: Equatable, Sendable {
    public var bonus: Int
    public var reachMin: Int
    public var reachMax: Int
    /// 武器の山の来歴(あれば)。
    public var origin: ProvenanceID?

    public static let unarmed = WeaponProfile(bonus: 0, reachMin: 0, reachMax: 0, origin: nil)
}

public enum Weapons {
    /// 装備から武器の強さと間合いを出す。物質でない品(R2 の武器の定義)は今は素手と同じ。
    public static func profile(_ item: EquippedItem?, def: CombatDef, ruleBook: RuleBook) -> WeaponProfile {
        guard let item, case .matter(let m) = item.stuff else { return .unarmed }
        let reach = def.reach[m.shape.rawValue] ?? ReachDef(min: 0, max: 0)
        return WeaponProfile(bonus: power(of: m, def: def, ruleBook: ruleBook), reachMin: reach.min,
                             reachMax: max(reach.min, reach.max), origin: item.origin)
    }

    /// 物質の武器としての上積み。
    public static func power(of m: Matter, def: CombatDef = CombatDef(), ruleBook: RuleBook = .r1) -> Int {
        let r = ProcessChain.run([], input: m, rules: ruleBook)
        var hardness = max(0, r.hardness)
        if r.toughness <= 0 { hardness /= 2 }  // 割れ: 硬くても欠ける
        let bp = Int64(m.purity.basisPoints)
        let eff = Int64(purityEffectPermille(m.purity))
        return Int(Int64(hardness) * bp * eff / (10_000 * 1000 * Int64(def.divisor)))
    }

    /// 純度の効き(千分率)= 1000 + 100 × ナイン数²。90% → 1100、99% → 1400(RFMatter の PurityMath.effect の整数版)。
    public static func purityEffectPermille(_ p: Purity) -> Int {
        let n = ninesMilli(p)
        return 1000 + n * n / 10_000
    }

    /// ナイン数 × 1000 = 1000 × log10(100 / (100 − 純度))。100% は 6000 で頭打ち。
    public static func ninesMilli(_ p: Purity) -> Int {
        let bp = p.basisPoints
        if bp >= 10_000 { return 6000 }
        if bp <= 0 { return 0 }
        let u = 10_000 - bp  // 1...9999
        var d = 0
        var pow10 = 1
        while u / (pow10 * 10) >= 1 { d += 1; pow10 *= 10 }
        let m = u * 1000 / pow10  // 1000...9999(仮数 × 1000)
        let i = m / 100  // 10...99
        let frac = m % 100
        let lo = log10Table[i - 10], hi = log10Table[i - 9]
        let logU = d * 1000 + lo + (hi - lo) * frac / 100
        return min(6000, 4000 - logU)
    }

    /// 1000 × log10(k / 10)、k = 10...100。
    static let log10Table: [Int] = [
        0, 41, 79, 114, 146, 176, 204, 230, 255, 279, 301, 322, 342, 362, 380, 398, 415, 431, 447, 462, 477, 491, 505,
        519, 531, 544, 556, 568, 580, 591, 602, 613, 623, 633, 643, 653, 663, 672, 681, 690, 699, 708, 716, 724, 732,
        740, 748, 756, 763, 771, 778, 785, 792, 799, 806, 813, 820, 826, 833, 839, 845, 851, 857, 863, 869, 875, 881,
        886, 892, 898, 903, 908, 914, 919, 924, 929, 934, 940, 944, 949, 954, 959, 964, 968, 973, 978, 982, 987, 991,
        996, 1000,
    ]
}
