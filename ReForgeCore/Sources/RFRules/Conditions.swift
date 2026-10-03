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
        case .has(let ing): return stockCount(ing, w) >= ing.quantity
        case .stock(let ing, let cmp, let perMember):
            let target = perMember == true ? ing.quantity * w.people.members.count : ing.quantity
            return cmp.test(Int64(stockCount(ing, w)), Int64(target))
        case .placedCount(let m, let s, let atLeast, let unfinished):
            let n = w.placements.items.values.filter { p in
                if unfinished != true, case .underConstruction = p.status { return false }
                switch p.kind {
                case .module(let k): return m == k || (m == nil && s == nil)
                case .structure(let k): return s == k || (m == nil && s == nil)
                }
            }.count
            return n >= atLeast
        case .ledger(let q, let atLeast): return ProvenanceQueries.count(q, in: w) >= atLeast
        case .firstTime(let q):
            guard let t = trigger, let r = w.ledger.record(t), ProvenanceQueries.matches(q, r) else {
                return false
            }
            return w.ledger.records.first { ProvenanceQueries.matches(q, $0) }?.id == t
        case .trigger(let q):
            guard let t = trigger, let r = w.ledger.record(t) else { return false }
            return ProvenanceQueries.matches(q, r)
        case .part(let kind, let part, let state):
            for (id, poi) in w.map.layers.values.flatMap(\.pois) where poi.kind == kind {
                let st = w.exploration.poi[id]?.parts[part] ?? .intact
                if st.name == state { return true }
            }
            return false
        case .poi(let kind, let test):
            for (id, poi) in w.map.layers.sorted(by: { $0.key < $1.key }).flatMap({ $0.value.pois.sorted { $0.key < $1.key } })
            where poi.kind == kind {
                let pr = w.exploration.poi[id] ?? POIProgress()
                switch test {
                case .visitsAtLeast(let n): if pr.visits >= n { return true }
                case .flag(let f): if pr.flags.contains(f) { return true }
                case .partsInState(let st, let n):
                    let names = content.pois[kind]?.parts ?? Array(pr.parts.keys)
                    if names.filter({ (pr.parts[$0] ?? .intact).name == st }).count >= n { return true }
                case .repairAtLeast(let part, let stage): if pr.repair[part, default: 0] >= stage { return true }
                }
            }
            return false
        case .inAura(let p, let kind):
            return Auras.active(at: w.people[p]?.position, kind: kind, in: w) != nil
        case .person(let id, let test): return testPerson(w.people[id], test, w, content)
        case .someone(let tests, let atLeast, let includeNonMembers):
            let pool = includeNonMembers == true ? w.people.order : w.people.members
            let n = pool.filter { id in tests.allSatisfy { testPerson(w.people[id], $0, w, content) } }.count
            return n >= (atLeast ?? 1)
        case .members(let n): return w.people.members.count >= n
        case .group(let id, let r): return (w.people.groups[id]?.relation ?? Int.min) >= r
        case .groupFlag(let id, let f): return w.people.groups[id]?.flags.contains(f) ?? false
        case .counter(let id, let cmp, let v): return cmp.test(Int64(w.narrative.counters[id] ?? 0), Int64(v))
        case .stat(let id, let cmp, let v): return cmp.test(w.survival.stats[id]?.raw ?? 0, Int64(v))
        case .phase(let ph): return w.clock.phase == ph
        case .dayAtLeast(let d): return w.clock.day >= d
        case .eventFired(let id): return w.narrative.fired[id] != nil
        case .sinceFired(let id, let h):
            guard let f = w.narrative.fired[id] else { return false }
            return (w.clock.now - f.lastAt) >= .hours(h)
        case .choiceMade(let e, let ch):
            return w.ledger.records.contains { $0.act == .chose && $0.subject == .choice(e, ch) }
        case .researchDone(let id): return w.research.completed.contains(id)
        case .unlocked(let t): return isUnlocked(t, w.research.unlocked)
        case .at(let person, let place):
            guard let pos = w.people[person]?.position else { return false }
            return Places.contains(place, pos, world: w, trigger: trigger)
        case .nearTerrain(let place, let tag, let radius):
            guard let c = Places.resolve(place, world: w, trigger: trigger), let layer = w.map[c.layer] else { return false }
            for dy in -radius...radius {
                for dx in -radius...radius {
                    guard let t = layer.terrain(at: GridPoint(c.point.x + dx, c.point.y + dy)) else { continue }
                    let def = content.terrains[t]
                    if def?.tags.contains(tag) == true || (tag == "water" && def?.isWater == true) { return true }
                }
            }
            return false
        case .discoveredPOI(let kind, let atLeast):
            let n = w.map.layers.values.reduce(0) { acc, layer in
                acc + layer.pois.filter { $0.value.kind == kind && w.knowledge.discovered.contains($0.key) }.count
            }
            return n >= (atLeast ?? 1)
        case .objective(let id, let st): return w.narrative.objectives[id]?.rawValue == st.rawValue
        case .runAtLeast(let i): return w.run.index >= i
        case .sheet(let id, let t): return SheetRules.test(t, w.narrative.sheet(id), w)
        case .baseGrade(let n): return BaseGrades.current(w, content) >= n
        case .hearthAtLeast(let l):
            return w.placements.items.values.contains { p in Hearths.level(of: p, content).map { $0 >= l } ?? false }
        case .stockTotal(let n): return w.inventory.entries(.base).reduce(0) { $0 + $1.quantity } >= n
        case .findings(let n): return w.notebook.notes.count >= n
        case .inspected(let t, let poi):
            if let t { return w.knowledge.inspected.contains(Subject.terrain(t)) }
            if let poi { return w.knowledge.inspected.contains(Subject.poi(poi)) }
            return false
        }
    }

    /// 拠点の蓄え+ノアの持ち物で、材料に合う物の数。
    public static func stockCount(_ ing: Ingredient, _ w: WorldState) -> Int {
        [HolderID.base, .person(.noah)].reduce(0) { acc, h in
            acc + w.inventory.entries(h).filter(ing.matches).reduce(0) { $0 + $1.quantity }
        }
    }

    public static func testPerson(_ p: PersonState?, _ t: PersonTest, _ w: WorldState, _ content: ContentDB) -> Bool {
        guard let p else { return false }
        switch t {
        case .member: return p.presence.isMember
        case .alive: return p.presence.isAlive
        case .dead: return !p.presence.isAlive
        case .met: if case .unmet = p.presence { return false } else { return true }
        case .away: if case .away = p.presence { return true } else { return false }
        case .body(let stat, let cmp, let v):
            let b = p.body
            let raw: Int64
            switch stat {
            case "health": raw = b.health.raw
            case "stamina": raw = b.stamina.raw
            case "satiety": raw = b.satiety.raw
            case "hydration": raw = b.hydration.raw
            case "mind": raw = b.mind.raw
            default: raw = Int64(b.conditions[StatID(stat)] ?? 0)
            }
            return cmp.test(raw, Int64(v))
        case .specialty(let tag): return content.people[p.id]?.specialties.contains(tag) ?? false
        case .near(let other, let r):
            guard let a = p.position, let b = w.people[other]?.position, a.layer == b.layer else { return false }
            return a.point.chebyshev(to: b.point) <= r
        case .working:
            switch p.activity {
            case .working, .carrying, .interacting: return true
            default: return false
            }
        case .inGroup(let g): return g.map { p.group == $0 } ?? (p.group != nil)
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
    /// 記録が問い合わせに合うか。周回では絞らない: 来歴(world.ledger)には今の時間軸の記録だけが入っている
    /// (巻き戻しは夜明けまでの記録を残し、その後の分は消して RunState.pastLives に写す)。だから夜明けより前に
    /// 置いた炉は、巻き戻した後も「置いたことがある」のまま(巻き戻しは物語の引き金を変えない)。
    public static func matches(_ q: ProvenanceQuery, _ r: ProvenanceRecord) -> Bool {
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
    /// currentRunOnly == false なら、前の周回で覚えておいた記録(pastLives.memorable。今の来歴に無いもの)も数える。
    public static func count(_ q: ProvenanceQuery, in w: WorldState) -> Int {
        var n = w.ledger.records.filter { matches(q, $0) }.reduce(0) { $0 + $1.count }
        if q.currentRunOnly == false {
            var seen = Set(w.ledger.records.map(\.id))
            for life in w.run.pastLives {
                for r in life.memorable where !seen.contains(r.id) && matches(q, r) {
                    seen.insert(r.id)
                    n += r.count
                }
            }
        }
        return n
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
        case .openingSite(let kind):
            let layer = w.map[.surface]
            if let site = kind == .firstFire ? layer?.firstFireSite : layer?.dawnFindSite {
                return WorldPoint(.surface, site)
            }
            return resolve(.base, world: w, trigger: trigger)   // 置き場が無い(古い保存): 今の探し方
        case .placement(let m, let s):
            return placement(m, s, in: w).flatMap { w.placements.items[$0]?.at }
        case .near(let inner, _): return resolve(inner, world: w, trigger: trigger)
        }
    }

    /// その種類の置いた物のうち最も早く置いたもの(両方 nil なら何でも)。
    public static func placement(_ module: ModuleKindID?, _ structure: StructureKindID?, in w: WorldState) -> EntityID? {
        w.placements.sortedIDs.first { id in
            switch w.placements.items[id]?.kind {
            case .module(let k)?: module == k || (module == nil && structure == nil)
            case .structure(let k)?: structure == k || (module == nil && structure == nil)
            case nil: false
            }
        }
    }

    /// 引き金の記録が置いた物を指していれば、その置いた物(まだあるときだけ)。引き金が出来事の発火・選択の記録なら、
    /// その引き金(inputs の先頭)をたどる(効果の cause は発火の記録で、その inputs が工業の行為の記録)。
    public static func triggerPlacement(_ trigger: ProvenanceID?, in w: WorldState) -> EntityID? {
        var next = trigger
        for _ in 0..<4 {
            guard let t = next, let r = w.ledger.record(t) else { return nil }
            switch r.subject {
            case .module(_, let e?), .structure(_, let e?), .entity(let e): return w.placements.items[e] != nil ? e : nil
            case .event, .choice: next = r.inputs.first
            default: return nil
            }
        }
        return nil
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
