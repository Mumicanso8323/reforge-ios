import RFContent
import RFKernel
import RFMap
import RFWorld

/// 条件の評価(出来事・選択肢・研究の前提・目標・失敗の規則・追跡カウンタが共通に使う)。
/// 持ち主: RFNarrative の担当(新しい条件の case を足したら、ここに評価を足す)。
public enum ConditionEvaluator {
    /// 評価する。chance は物語の乱数の流れを進める(だから inout)。trigger は引き金の来歴。
    public static func evaluate(_ c: Condition, _ ctx: inout StepContext, trigger: ProvenanceID? = nil) -> Bool {
        if case .chance(let bp) = c { return ctx.random(.narrative) { $0.chance(basisPoints: bp) } }
        switch c {
        case .all(let xs): return xs.allSatisfy { evaluate($0, &ctx, trigger: trigger) }
        case .any(let xs): return xs.contains { evaluate($0, &ctx, trigger: trigger) }
        case .not(let x): return !evaluate(x, &ctx, trigger: trigger)
        default: return evaluatePure(c, world: ctx.world, content: ctx.content, trigger: trigger) ?? false
        }
    }

    /// 乱数を使わない評価(画面の「選べるか」の表示など)。chance は nil(分からない)。
    public static func evaluatePure(_ c: Condition, world w: WorldState, content: ContentDB,
                                    trigger: ProvenanceID? = nil) -> Bool?
    {
        switch c {
        case .always: return true
        case .all(let xs):
            var unknown = false
            for x in xs {
                switch evaluatePure(x, world: w, content: content, trigger: trigger) {
                case false?: return false
                case nil: unknown = true
                default: break
                }
            }
            return unknown ? nil : true
        case .any(let xs):
            var unknown = false
            for x in xs {
                switch evaluatePure(x, world: w, content: content, trigger: trigger) {
                case true?: return true
                case nil: unknown = true
                default: break
                }
            }
            return unknown ? nil : false
        case .not(let x): return evaluatePure(x, world: w, content: content, trigger: trigger).map { !$0 }
        case .chance: return nil
        case .known(let e): return e.evaluate(w.knowledge.factSet)
        case .has(let ing):
            let n = [HolderID.base, .person(.noah)].reduce(0) { acc, h in
                acc + w.inventory.entries(h).filter(ing.matches).reduce(0) { $0 + $1.quantity }
            }
            return n >= ing.quantity
        case .placedCount(let m, let s, let atLeast):
            let n = w.placements.items.values.filter { p in
                switch p.kind {
                case .module(let k): m == k || (m == nil && s == nil)
                case .structure(let k): s == k || (m == nil && s == nil)
                }
            }.count
            return n >= atLeast
        case .ledger(let q, let atLeast): return ProvenanceQueries.count(q, in: w) >= atLeast
        case .firstTime(let q):
            guard let t = trigger, let r = w.ledger.record(t), ProvenanceQueries.matches(q, r, run: w.run.index) else {
                return false
            }
            return w.ledger.records.first { ProvenanceQueries.matches(q, $0, run: w.run.index) }?.id == t
        case .part(let kind, let part, let state):
            for (id, poi) in w.map.layers.values.flatMap(\.pois) where poi.kind == kind {
                let st = w.exploration.poi[id]?.parts[part] ?? .intact
                if st.name == state { return true }
            }
            return false
        case .inAura(let p, let kind):
            return Auras.active(at: w.people[p]?.position, kind: kind, in: w) != nil
        case .person(let id, let test): return testPerson(w.people[id], test, w)
        case .members(let n): return w.people.members.count >= n
        case .group(let id, let r): return (w.people.groups[id]?.relation ?? Int.min) >= r
        case .counter(let id, let cmp, let v): return cmp.test(Int64(w.narrative.counters[id] ?? 0), Int64(v))
        case .stat(let id, let cmp, let v): return cmp.test(w.survival.stats[id]?.raw ?? 0, Int64(v))
        case .phase(let ph): return w.clock.phase == ph
        case .dayAtLeast(let d): return w.clock.day >= d
        case .eventFired(let id): return w.narrative.fired[id] != nil
        case .choiceMade(let e, let ch):
            return w.ledger.records.contains { $0.act == .chose && $0.subject == .choice(e, ch) }
        case .researchDone(let id): return w.research.completed.contains(id)
        case .unlocked(let t): return isUnlocked(t, w.research.unlocked)
        case .at(let person, let place):
            guard let pos = w.people[person]?.position else { return false }
            return Places.contains(place, pos, world: w, trigger: trigger)
        case .discoveredPOI(let kind):
            return w.map.layers.values.contains { layer in
                layer.pois.contains { $0.value.kind == kind && w.knowledge.discovered.contains($0.key) }
            }
        case .objective(let id, let st): return w.narrative.objectives[id]?.rawValue == st.rawValue
        case .runAtLeast(let i): return w.run.index >= i
        }
    }

    static func testPerson(_ p: PersonState?, _ t: PersonTest, _ w: WorldState) -> Bool {
        guard let p else { return false }
        switch t {
        case .member: return p.presence.isMember
        case .alive: return p.presence.isAlive
        case .dead: return !p.presence.isAlive
        case .met: if case .unmet = p.presence { return false } else { return true }
        case .relationAtLeast(let r): return p.relation.rank >= r
        case .ideologyAtLeast(let a, let v): return (p.ideology[a] ?? 0) >= v
        case .hasMemory(let k): return p.memories.contains { $0.kind == k }
        case .assignedToModule(let kind):
            guard case .operate(let e) = p.assignment, let pl = w.placements.items[e] else { return false }
            if let kind { return pl.kind == .module(kind) }
            if case .module = pl.kind { return true }
            return false
        case .hasSkill(let s): return p.skills.contains(s)
        }
    }

    static func isUnlocked(_ t: UnlockTarget, _ u: UnlockSet) -> Bool {
        switch t {
        case .module(let id): u.modules.contains(id)
        case .structure(let id): u.structures.contains(id)
        case .handwork(let id): u.handwork.contains(id)
        case .interaction(let id): u.interactions.contains(id)
        case .research(let id): u.research.contains(id)
        }
    }
}

extension PartState {
    public var name: PartStateName {
        switch self {
        case .intact: .intact
        case .salvaged: .salvaged
        case .dismantled: .dismantled
        case .rebuilt: .rebuilt
        }
    }
}

/// 来歴の問い合わせ。
public enum ProvenanceQueries {
    public static func matches(_ q: ProvenanceQuery, _ r: ProvenanceRecord, run: Int) -> Bool {
        if q.currentRunOnly ?? true, r.run != run { return false }
        if let a = q.act, r.act != a { return false }
        if let a = q.actor, r.actor != a { return false }
        if let t = q.tag, !r.tags.contains(t) { return false }
        switch r.subject {
        case .item(let i): if let x = q.item, x != i { return false }
        case .module(let k, _): if let x = q.module, x != k { return false }
        case .structure(let k, _): if let x = q.structure, x != k { return false }
        case .person(let p): if let x = q.person, x != p { return false }
        case .enemy(let k, _): if let x = q.enemy, x != k { return false }
        case .poi(let k, _): if let x = q.poi, x != k { return false }
        case .event(let e), .choice(let e, _): if let x = q.event, x != e { return false }
        default: break
        }
        // 対象を指定したのに対象の種類が違う記録は外す
        if q.item != nil, !isItem(r.subject) { return false }
        if q.module != nil, !isModule(r.subject) { return false }
        if q.structure != nil, !isStructure(r.subject) { return false }
        if q.person != nil, !isPerson(r.subject) { return false }
        if q.enemy != nil, !isEnemy(r.subject) { return false }
        if q.poi != nil, !isPOI(r.subject) { return false }
        return true
    }

    /// 合う記録の count の合計(ラインの生産は 1 記録に数がまとまっている)。
    public static func count(_ q: ProvenanceQuery, in w: WorldState) -> Int {
        w.ledger.records.filter { matches(q, $0, run: w.run.index) }.reduce(0) { $0 + $1.count }
    }

    private static func isItem(_ s: SubjectRef) -> Bool { if case .item = s { true } else { false } }
    private static func isModule(_ s: SubjectRef) -> Bool { if case .module = s { true } else { false } }
    private static func isStructure(_ s: SubjectRef) -> Bool { if case .structure = s { true } else { false } }
    private static func isPerson(_ s: SubjectRef) -> Bool { if case .person = s { true } else { false } }
    private static func isEnemy(_ s: SubjectRef) -> Bool { if case .enemy = s { true } else { false } }
    private static func isPOI(_ s: SubjectRef) -> Bool { if case .poi = s { true } else { false } }
}

/// 場所の指し方の解決。
public enum Places {
    /// 指す場所の中心(見つからなければ nil)。
    public static func resolve(_ p: PlaceSelector, world w: WorldState, trigger: ProvenanceID?) -> WorldPoint? {
        switch p {
        case .trigger: return trigger.flatMap { w.ledger.record($0)?.place }
        case .person(let id): return w.people[id]?.position
        case .poiKind(let kind):
            for (lid, layer) in w.map.layers.sorted(by: { $0.key < $1.key }) {
                if let (_, poi) = layer.pois.sorted(by: { $0.key < $1.key }).first(where: { $0.value.kind == kind }) {
                    return WorldPoint(lid, poi.at)
                }
            }
            return nil
        case .base:
            return w.base.area.map { WorldPoint(.surface, GridPoint($0.origin.x + $0.size.width / 2, $0.origin.y + $0.size.height / 2)) }
        case .point(let at): return at
        case .near(let inner, _): return resolve(inner, world: w, trigger: trigger)
        }
    }

    public static func contains(_ p: PlaceSelector, _ pos: WorldPoint, world w: WorldState, trigger: ProvenanceID?) -> Bool {
        if case .near(let inner, let r) = p {
            guard let c = resolve(inner, world: w, trigger: trigger), c.layer == pos.layer else { return false }
            return c.point.chebyshev(to: pos.point) <= r
        }
        if case .base = p, let a = w.base.area { return pos.layer == .surface && a.contains(pos.point) }
        return resolve(p, world: w, trigger: trigger) == pos
    }
}
