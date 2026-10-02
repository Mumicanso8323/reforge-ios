import RFContent
import RFKernel
import RFRules
import RFWorld

/// 人ごとの能力(CORE-15)。画面に出す値はコンテンツが決める。
///
/// - R1: 定義は visibleWhen が成り立つまで使えず、範囲も付けず、問い合わせにも出ない。
/// - R2: 配属の効き(AbilityDef.passives の perceives・speed)を各システムが ContentDB.workModifiers で読む。
/// - R3: 後で解禁される能力を、配属の効き(passives)・持ち主のまわりの範囲(auras)・
///   使う行為(effects。場所は PlaceSelector.trigger = 使った場所)にする。
///
/// 書いてよい切れ端: abilities(と、力が付ける範囲の効果 auras.active の自分の分)。乱数の流れ: .abilities。
public struct AbilitiesSystem: SimSystem {
    public let name = "abilities"
    public init() {}

    // MARK: コマンド

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .abilities(.use(let p, let a, let target)) = command else { return .notMine }
        return use(p, a, target, &ctx)
    }

    private func use(_ p: PersonID, _ a: AbilityID, _ target: WorldPoint?, _ ctx: inout StepContext) -> CommandResult {
        let w = ctx.world
        // 見えない力・持っていない力は「知らない」と同じ理由で断る(存在を漏らさない)。
        guard let d = ctx.content.abilities[a], AbilityRules.isVisible(d, w, ctx.content),
              AbilityRules.holds(p, d, w), let ps = w.people[p], ps.presence.isMember,
              !(d.effects ?? []).isEmpty
        else { return .rejected(Rejection(AbilityReasons.unknown)) }
        if let until = w.abilities.cooldowns[p]?[a], w.clock.now < until {
            return .rejected(Rejection(AbilityReasons.cooldown))
        }
        let cost = d.cost ?? AbilityCost()
        // 触媒の物は、全部そろっているときだけ使う(拠点の蓄え → 使う人の持ち物)。
        let holders: [HolderID] = [.base, .person(p)]
        for ing in cost.items ?? [] {
            let have = holders.reduce(0) { acc, h in
                acc + w.inventory.entries(h).filter(ing.matches).reduce(0) { $0 + $1.quantity }
            }
            guard have >= ing.quantity else { return .rejected(Rejection(AbilityReasons.noCatalyst)) }
        }
        var inputs: [ProvenanceID] = []
        for ing in cost.items ?? [] {
            var left = ing.quantity
            for h in holders where left > 0 {
                let here = ctx.world.inventory.entries(h).filter(ing.matches).reduce(0) { $0 + $1.quantity }
                let k = min(left, here)
                guard k > 0, let took = ctx.takeStock(k, from: h, where: ing.matches) else { continue }
                inputs += took.keys.sorted()
                left -= k
            }
        }
        // 力の元。足りない分は傷で払う(原作: 枯渇時は出血で肩代わり)。
        let maxReserve = AbilityRules.reserveMax(p, w, ctx.content)
        let current = w.abilities.reserve[p] ?? maxReserve
        let need = Milli(cost.reserve ?? 0)
        let shortfall = max(Milli.zero, need - current)
        ctx.world.abilities.reserve[p] = max(Milli.zero, current - need)
        let perShort = cost.healthPerShortfall ?? AbilityRules.defaultHealthPerShortfall
        let wound = (cost.health ?? 0) + Int((shortfall.raw + 999) / 1000) * perShort

        var detail: [String: Value] = [:]
        if let m = cost.mind, m > 0 { detail["mind"] = .int(Int64(m)) }
        if wound > 0 { detail["wound"] = .int(Int64(wound)) }
        let rec = ctx.record(.used, .ability(a), actor: p, place: target ?? ps.position, inputs: inputs, detail: detail)
        var effects: [Effect] = []
        if wound > 0 { effects.append(.injure(person: p, amount: wound)) }
        effects += d.effects ?? []
        EffectApplier.apply(effects, &ctx, cause: rec)

        ctx.world.abilities.mastery[p, default: [:]][a, default: 0] += 1
        if let h = d.cooldownHours, h > 0 {
            ctx.world.abilities.cooldowns[p, default: [:]][a] = w.clock.now + .hours(h)
        }
        ctx.emit(.abilityUsed(person: p, ability: a, record: rec))
        ctx.changes.mark(.people)
        return .done
    }

    // MARK: ステップ

    public func step(_ ctx: inout StepContext) {
        syncAuras(&ctx)
    }

    /// 持ち主が一員で、力が見えている間だけ、持ち主のまわりに範囲の効果を付ける(獣が寄らない、など)。
    private func syncAuras(_ ctx: inout StepContext) {
        let c = ctx.content
        var want: [PersonID: [(AbilityID, AbilityAura)]] = [:]
        for a in c.abilities.keys.sorted() {
            guard let d = c.abilities[a], let auras = d.auras, !auras.isEmpty,
                  AbilityRules.isVisible(d, ctx.world, c)
            else { continue }
            for p in ctx.world.people.order where AbilityRules.holds(p, d, ctx.world) {
                guard let ps = ctx.world.people[p], ps.presence.isMember, ps.position != nil else { continue }
                want[p, default: []] += auras.map { (a, $0) }
            }
        }
        // 要らなくなった範囲を外す。
        for (p, ids) in ctx.world.abilities.auras.sorted(by: { $0.key < $1.key }) where want[p] == nil {
            for id in ids { ctx.world.auras.active[id] = nil }
            ctx.world.abilities.auras[p] = nil
            ctx.changes.mark([.people, .fog])
        }
        // 足りない範囲を付ける(人ごとに、定義の順で)。
        for p in want.keys.sorted() {
            let list = want[p] ?? []
            let have = (ctx.world.abilities.auras[p] ?? []).filter { ctx.world.auras.active[$0] != nil }
            guard have.count != list.count else { continue }
            for id in have { ctx.world.auras.active[id] = nil }
            var ids: [EntityID] = []
            for (a, aura) in list {
                let id = ctx.world.newEntityID()
                let rec = ctx.record(.used, .ability(a), actor: p, detail: ["passive": .bool(true)])
                ctx.world.auras.active[id] = Aura(id: id, kind: aura.kind, source: .person(p), radius: aura.radius,
                                                  origin: rec)
                ids.append(id)
            }
            ctx.world.abilities.auras[p] = ids
            ctx.changes.mark([.people, .fog])
        }
    }

    // MARK: 反応

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        guard case .dawn = event else { return }
        // 夜明けに力の元が満ちる(持っている人だけ)。
        for p in ctx.world.people.order {
            let m = AbilityRules.reserveMax(p, ctx.world, ctx.content)
            if m > .zero { ctx.world.abilities.reserve[p] = m } else { ctx.world.abilities.reserve[p] = nil }
        }
    }
}

/// 力の規則(状態を持たない関数)。
public enum AbilityRules {
    public static let defaultHealthPerShortfall = 5

    /// 存在が見えてよいか(visibleWhen が無い能力は見せない)。
    public static func isVisible(_ d: AbilityDef, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let v = d.visibleWhen else { return false }
        return ConditionEvaluator.evaluatePure(v, world: w, content: c) == true
    }

    /// その人が力を持っているか(生まれつき・または使ったことがある)。
    public static func holds(_ p: PersonID, _ d: AbilityDef, _ w: WorldState) -> Bool {
        d.holders?.contains(p) == true || w.abilities.mastery[p]?[d.id] != nil
    }

    /// 力の元の最大(持っている力の reserveMax の最大)。
    public static func reserveMax(_ p: PersonID, _ w: WorldState, _ c: ContentDB) -> Milli {
        let m = c.abilities.values.filter { holds(p, $0, w) }.compactMap(\.reserveMax).max() ?? 0
        return Milli(m)
    }

    /// 画面に出してよい能力(見えている能力で、その人が持つもの。ID 順)。
    public static func visibleAbilities(of p: PersonID, _ w: WorldState, _ c: ContentDB) -> [AbilityID] {
        c.abilities.keys.sorted().filter { a in
            guard let d = c.abilities[a] else { return false }
            return isVisible(d, w, c) && holds(p, d, w)
        }
    }
}

/// 断った理由(文字列表のキー)。
public enum AbilityReasons {
    public static let unknown: TextID = "reason.ability.unknown"
    public static let cooldown: TextID = "reason.ability.cooldown"
    public static let noCatalyst: TextID = "reason.ability.no_catalyst"
}
