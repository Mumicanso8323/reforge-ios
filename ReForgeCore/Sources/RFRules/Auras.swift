import RFContent
import RFKernel
import RFWorld

/// 範囲の効果の問い合わせ(各システムが読む)。持ち主: RFNarrative の担当(付け外しは EffectApplier)。
///
/// 使い方の例:
///   - RFCrew: 仲間の位置に drawTowardSource があれば、配属を上書きして中心へ歩かせる。
///   - RFCombat: repelEnemies の中には敵が入らない。
///   - RFSurvival: bodyPerHour / statPerHour を時間あたりで足す。
///   - RFProduction: workSpeed をモジュールの速さに掛ける。
public enum Auras {
    /// 範囲の中心の位置(人なら今いる所、置いた物ならその場所)。
    public static func center(of a: Aura, in w: WorldState) -> WorldPoint? {
        switch a.source {
        case .point(let p): p
        case .person(let id): w.people[id]?.position
        case .placement(let e): w.placements.items[e]?.at
        }
    }

    /// その場所に効いている範囲の効果(ID 順。kind を指定すればその種類だけ)。
    public static func covering(_ pos: WorldPoint, in w: WorldState, kind: AuraKindID? = nil) -> [Aura] {
        w.auras.active.values.sorted { $0.id < $1.id }.filter { a in
            if let kind, a.kind != kind { return false }
            guard a.strength > 0, let c = center(of: a, in: w), c.layer == pos.layer else { return false }
            if let u = a.until, w.clock.now >= u { return false }
            return c.point.chebyshev(to: pos.point) <= a.radius
        }
    }

    public static func active(at pos: WorldPoint?, kind: AuraKindID, in w: WorldState) -> Aura? {
        guard let pos else { return nil }
        return covering(pos, in: w, kind: kind).first
    }

    /// その場所に効く変化(強さつき)。
    public static func modifiers(at pos: WorldPoint, in w: WorldState, content: ContentDB)
        -> [(modifier: AuraDef.Modifier, strength: Int, aura: Aura)]
    {
        covering(pos, in: w).flatMap { a in
            (content.auras[a.kind]?.modifiers ?? []).map { ($0, a.strength, a) }
        }
    }
}
