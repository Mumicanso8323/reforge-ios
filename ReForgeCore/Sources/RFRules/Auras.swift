import RFContent
import RFKernel
import RFWorld

/// 範囲の効果の問い合わせと整理(REQ-S10)。持ち主: U11(付け外しは EffectApplier、毎ステップの整理は maintain)。
///
/// 各システムの読み方:
///   - RFCrew: 仲間の override(maintain が付け外しする)に従って歩く。範囲が消えれば override も消える。
///   - RFCombat: repelsEnemies(at:) の中には敵が入らない。
///   - RFSurvival: bodyPerHour(at:stat:) を体に、statPerHour(_:) を拠点全体の数値に、時間あたりで足す。
///   - RFProduction・RFBase・RFResearch: workSpeedPermille(at:) を作業の速さに掛ける。
/// 強さ(strength。千分率)は変化の量に掛かる(半分の範囲は半分だけ効く)。
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
    /// content を渡すと、距離の縛り(AuraDef.requiresNear)で今は効かない範囲も外す。
    public static func covering(_ pos: WorldPoint, in w: WorldState, kind: AuraKindID? = nil,
                                content: ContentDB? = nil) -> [Aura] {
        w.auras.active.values.sorted { $0.id < $1.id }.filter { a in
            if let kind, a.kind != kind { return false }
            guard a.strength > 0, let c = center(of: a, in: w), c.layer == pos.layer else { return false }
            if let u = a.until, w.clock.now >= u { return false }
            guard c.point.chebyshev(to: pos.point) <= a.radius else { return false }
            if let content, !tetherHolds(a, in: w, content: content) { return false }
            return true
        }
    }

    /// 距離の縛り(AuraDef.requiresNear)が成り立っているか(縛りが無ければ true)。
    /// 中心がその人から radius マスより遠い・別の層・どちらかが地図にいない間は効かない(U16)。
    public static func tetherHolds(_ a: Aura, in w: WorldState, content: ContentDB) -> Bool {
        guard let t = content.auras[a.kind]?.requiresNear else { return true }
        guard let c = center(of: a, in: w), let p = w.people[t.person]?.position, p.layer == c.layer else { return false }
        return c.point.chebyshev(to: p.point) <= t.radius
    }

    public static func active(at pos: WorldPoint?, kind: AuraKindID, in w: WorldState) -> Aura? {
        guard let pos else { return nil }
        return covering(pos, in: w, kind: kind).first
    }

    /// その場所に効く変化(強さつき)。
    public static func modifiers(at pos: WorldPoint, in w: WorldState, content: ContentDB)
        -> [(modifier: AuraDef.Modifier, strength: Int, aura: Aura)]
    {
        covering(pos, in: w, content: content).flatMap { a in
            (content.auras[a.kind]?.modifiers ?? []).map { ($0, a.strength, a) }
        }
    }

    // MARK: - 各システムが読む値

    /// 作業の速さの掛け率(千分率。1000 = そのまま)。重なれば掛け合わせる。強さ s の範囲は 1000 + (p - 1000) × s / 1000。
    public static func workSpeedPermille(at pos: WorldPoint, in w: WorldState, content: ContentDB) -> Int {
        var total = 1000
        for (m, s, _) in modifiers(at: pos, in: w, content: content) {
            guard case .workSpeed(let p) = m else { continue }
            let eff = 1000 + (p - 1000) * s / 1000
            total = total * max(0, eff) / 1000
        }
        return total
    }

    /// 敵が入ってこない場所か。
    public static func repelsEnemies(at pos: WorldPoint, in w: WorldState, content: ContentDB) -> Bool {
        modifiers(at: pos, in: w, content: content).contains { if case .repelEnemies = $0.modifier { true } else { false } }
    }

    /// その場所の人の体の数値(stat)が 1 時間あたり変わる量(強さを掛けた合計)。
    public static func bodyPerHour(at pos: WorldPoint, stat: String, in w: WorldState, content: ContentDB) -> Int {
        modifiers(at: pos, in: w, content: content).reduce(0) { acc, x in
            if case .bodyPerHour(let st, let amount) = x.modifier, st == stat { return acc + amount * x.strength / 1000 }
            return acc
        }
    }

    /// 拠点全体の数値への 1 時間あたりの寄与(場所によらず、今ある範囲すべての合計)。
    public static func statPerHour(_ stat: StatID, in w: WorldState, content: ContentDB) -> Int {
        w.auras.active.values.sorted { $0.id < $1.id }.reduce(0) { acc, a in
            if let u = a.until, w.clock.now >= u { return acc }
            if !tetherHolds(a, in: w, content: content) { return acc }
            return acc + (content.auras[a.kind]?.modifiers ?? []).reduce(0) { sum, m in
                if case .statPerHour(let st, let amount) = m, st == stat { return sum + amount * a.strength / 1000 }
                return sum
            }
        }
    }

    /// この人を中心へ引き寄せている範囲(あれば。ID 順で最初のもの)。
    public static func drawing(_ person: PersonID, in w: WorldState, content: ContentDB) -> Aura? {
        guard let ps = w.people[person], ps.presence.isAlive, let pos = ps.position else { return nil }
        return covering(pos, in: w, content: content).first { a in
            guard let def = content.auras[a.kind],
                  def.modifiers.contains(where: { if case .drawTowardSource = $0 { true } else { false } })
            else { return false }
            if case .person(let src) = a.source, src == person { return false }
            if let affects = def.affects { return affects.contains(person) }
            return person != .noah
        }
    }

    // MARK: - 毎ステップの整理

    /// 期限切れの範囲を消し、置いた物・人の定義から付く範囲を合わせ、範囲による配属の上書きを付け外しする。
    /// NarrativeSystem.step が毎ステップ呼ぶ。
    public static func maintain(_ ctx: inout StepContext) {
        expire(&ctx)
        syncFromDefinitions(&ctx)
        syncOverrides(&ctx)
    }

    static func expire(_ ctx: inout StepContext) {
        let now = ctx.world.clock.now
        let gone = ctx.world.auras.active.values.filter { a in a.until.map { now >= $0 } ?? false }.map(\.id)
        for id in gone.sorted() { ctx.world.auras.active[id] = nil }
        if !gone.isEmpty { ctx.changes.mark(.people) }
    }

    /// 置いた物(建造中でないもの)と、生きていて地図の上にいる人の定義の auras を、範囲として持つ。
    static func syncFromDefinitions(_ ctx: inout StepContext) {
        let w = ctx.world
        // 速い道: 置いた物が無く、定義から付いた範囲も無く、範囲を持つ人の定義も無い
        if w.placements.items.isEmpty, !w.auras.active.values.contains(where: { $0.fromDefinition == true }),
           !w.people.order.contains(where: { !(ctx.content.people[$0]?.auras ?? []).isEmpty }) { return }
        var want: [(kind: AuraKindID, source: Aura.Source, origin: ProvenanceID)] = []
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id] else { continue }
            if case .underConstruction = p.status { continue }
            if p.status == .broken { continue }  // 壊れた物は範囲を出さない(U16)
            if !Hearths.effectsActive(p, ctx.content) { continue }  // 火床が燃えていない間は出さない(W-02c)
            let kinds: [AuraKindID]
            switch p.kind {
            case .module(let k): kinds = ctx.content.modules[k]?.auras ?? []
            case .structure(let k): kinds = ctx.content.structures[k]?.auras ?? []
            }
            for k in kinds { want.append((k, .placement(id), p.origin)) }
        }
        for pid in w.people.order {
            guard let ps = w.people[pid], ps.presence.isAlive, ps.position != nil else { continue }
            for k in ctx.content.people[pid]?.auras ?? [] { want.append((k, .person(pid), ProvenanceLedger.unknownOrigin)) }
        }
        var changed = false
        // 要らなくなったものを消す
        for (id, a) in w.auras.active.sorted(by: { $0.key < $1.key }) where a.fromDefinition == true {
            if !want.contains(where: { $0.kind == a.kind && $0.source == a.source }) {
                ctx.world.auras.active[id] = nil
                changed = true
            }
        }
        // 足りないものを足す
        for x in want {
            let exists = ctx.world.auras.active.values.contains { $0.fromDefinition == true && $0.kind == x.kind && $0.source == x.source }
            if exists { continue }
            let scale = ctx.world.auras.kindScale[x.kind] ?? AuraScale()
            let radius = (ctx.content.auras[x.kind]?.radius ?? 0) * scale.radius / 1000
            let id = ctx.world.newEntityID()
            ctx.world.auras.active[id] = Aura(id: id, kind: x.kind, source: x.source, radius: radius,
                                              strength: scale.strength, origin: x.origin, fromDefinition: true)
            changed = true
        }
        if changed { ctx.changes.mark(.people) }
    }

    /// drawTowardSource の範囲の中にいる人は、配属に従わず中心へ歩く(override)。範囲を出れば・範囲が消えれば戻る。
    /// 出来事の上書き(aura が nil)は期限が来たら外す。
    static func syncOverrides(_ ctx: inout StepContext) {
        let now = ctx.world.clock.now
        let anyDrawing = ctx.world.auras.active.values.contains { a in
            ctx.content.auras[a.kind]?.modifiers.contains { if case .drawTowardSource = $0 { true } else { false } } ?? false
        }
        let snapshot = ctx.world.people
        for pid in snapshot.order {
            guard let ps = snapshot[pid] else { continue }
            if ps.override == nil, !anyDrawing { continue }
            if let o = ps.override, o.aura == nil {
                if let u = o.until, now >= u {
                    ctx.world.people[pid]?.override = nil
                    ctx.changes.mark(.people)
                }
                continue  // 出来事の上書きは範囲より強い
            }
            let drawing = drawing(pid, in: ctx.world, content: ctx.content)
            if let a = drawing {
                if ps.override?.aura == a.id { continue }
                let assignment: Assignment
                switch a.source {
                case .person(let src): assignment = .follow(person: src)
                default:
                    guard let c = center(of: a, in: ctx.world) else { continue }
                    assignment = .guardArea(center: c, radius: 1)
                }
                let rec = ctx.record(.overridden, .person(pid), place: ps.position, inputs: [a.origin])
                ctx.world.people[pid]?.override = AssignmentOverride(assignment: assignment, aura: a.id, until: a.until,
                                                                     origin: rec)
                ctx.emit(.assigned(person: pid, assignment: assignment))
                ctx.changes.mark(.people)
            } else if ps.override?.aura != nil {
                ctx.world.people[pid]?.override = nil
                ctx.emit(.assigned(person: pid, assignment: ps.assignment))
                ctx.changes.mark(.people)
            }
        }
    }
}
