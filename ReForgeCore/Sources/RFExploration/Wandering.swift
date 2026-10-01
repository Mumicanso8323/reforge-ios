import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 歩いて探す(原作の一発の「探索」を、地図を歩くことに置き換えたもの)。
///
/// - 一員が POI のそばに来たら「入った」(訪れた回数・発見・`entered`)。ノアが初めて入った POI では、その POI の場の表を引く。
/// - ノアが区画(regionSize 四方)の中で、まだ引いていない場(足元と周り 8 マスの地形の場)に触れたら、その場の表を引く
///   (区画 × 場ごとに 1 回。1 ステップに 1 回まで。拠点の範囲の中は引かない)。川べりを歩けば川辺の表、森の縁なら森の表も引く。
/// - 表の引き方は原作 `ExplorationEventDatabase.RollEvent`: 場の表 + 汎用の表から、探索範囲(minRange)と一度きりで絞り、
///   重みで 1 件。乱数は探索の流れ。候補の条件(when)は乱数を使わない評価だけ(chance は使えない)。
/// - 探索範囲 = 1 + 拠点の中心から最も遠くまで行った距離 ÷ rangeStep(上限 maxRange)。
enum Wandering {
    static func track(_ ctx: inout StepContext) {
        for pid in ctx.world.people.members {
            guard let pos = ctx.world.people[pid]?.position else { continue }
            let last = ctx.world.exploration.lastPositions[pid]
            guard last != pos else { continue }
            ctx.world.exploration.lastPositions[pid] = pos
            updateRange(pos, &ctx)
            let firstVisit = enterPOI(pid, pos, &ctx)
            guard pid == .noah else { continue }
            if let (poi, kind) = firstVisit, let field = field(forPOI: kind, ctx.content) {
                roll(field: field, person: pid, at: pos, poi: poi, &ctx)
            } else if let f = newRegionField(pos, &ctx) {
                roll(field: f, person: pid, at: pos, poi: nil, &ctx)
            }
        }
    }

    // MARK: 探索範囲

    static func baseCenter(_ w: WorldState) -> GridPoint? {
        w.base.area.map { GridPoint($0.origin.x + $0.size.width / 2, $0.origin.y + $0.size.height / 2) }
    }

    static func updateRange(_ pos: WorldPoint, _ ctx: inout StepContext) {
        guard pos.layer == .surface, let c = baseCenter(ctx.world) else { return }
        let d = c.chebyshev(to: pos.point)
        guard d > ctx.world.exploration.farthest else { return }
        ctx.world.exploration.farthest = d
        let cfg = ctx.content.exploration
        let r = min(cfg.maxRange ?? 11, 1 + d / max(1, cfg.rangeStep ?? 8))
        if r > ctx.world.exploration.range {
            ctx.world.exploration.range = r
            ctx.changes.mark(.narrative)
        }
    }

    // MARK: POI

    /// POI のそばに来たら入ったことにする。ノアが初めて訪れた POI を返す。
    static func enterPOI(_ pid: PersonID, _ pos: WorldPoint, _ ctx: inout StepContext) -> (EntityID, POIKindID)? {
        guard let layer = ctx.world.map[pos.layer] else { return nil }
        var near: (EntityID, POIState)?
        for (e, poi) in layer.pois.sorted(by: { $0.key < $1.key }) {
            if poi.footprint.contains(where: { (poi.at + $0).chebyshev(to: pos.point) <= Interactions.reach }) {
                near = (e, poi)
                break
            }
        }
        let prev = ctx.world.exploration.nearPOI[pid]
        guard near?.0 != prev else { return nil }
        ctx.world.exploration.nearPOI[pid] = near?.0
        guard let (e, poi) = near else { return nil }
        var prog = ctx.world.exploration.poi[e] ?? POIProgress()
        prog.visits += 1
        ctx.world.exploration.poi[e] = prog
        if !ctx.world.knowledge.discovered.contains(e) {
            ctx.world.knowledge.discovered.insert(e)
            let rec = ctx.record(.discovered, .poi(poi.kind, e), actor: pid, place: WorldPoint(pos.layer, poi.at))
            ctx.emit(.discovered(entity: e, record: rec))
        }
        ctx.emit(.entered(person: pid, poi: e))
        ctx.changes.mark(.narrative)
        return pid == .noah && prog.visits == 1 ? (e, poi.kind) : nil
    }

    // MARK: 区画

    /// 足元と周りの場のうち、この区画でまだ引いていない最初の場(足元が先)。引く場に印を付けて返す。
    /// 場の無い地形だけなら汎用の表のために "-" を 1 回。
    static func newRegionField(_ pos: WorldPoint, _ ctx: inout StepContext) -> FieldID?? {
        let cfg = ctx.content.exploration
        if cfg.quietInBase ?? true, pos.layer == .surface, ctx.world.base.area?.contains(pos.point) == true { return nil }
        guard let layer = ctx.world.map[pos.layer] else { return nil }
        let rs = max(1, cfg.regionSize ?? 8)
        let size = GridSize(width: (layer.size.width + rs - 1) / rs, height: (layer.size.height + rs - 1) / rs)
        let r = GridPoint(pos.point.x / rs, pos.point.y / rs)
        guard size.contains(r) else { return nil }
        var seen: [FieldID?] = []
        for p in [pos.point] + pos.point.neighbors8 where layer.size.contains(p) {
            let f = field(at: WorldPoint(pos.layer, p), ctx)
            if !seen.contains(f) { seen.append(f) }
        }
        if seen.count > 1 { seen.removeAll { $0 == nil } }
        for f in seen {
            let key = ExplorationState.regionKey(pos.layer, field: f?.rawValue)
            var bits = ctx.world.exploration.exploredRegions[key] ?? GridBitset(size: size)
            guard !bits[r] else { continue }
            bits[r] = true
            ctx.world.exploration.exploredRegions[key] = bits
            return .some(f)
        }
        return nil
    }

    // MARK: 場と表

    static func field(at pos: WorldPoint, _ ctx: StepContext) -> FieldID? {
        guard let t = ctx.world.map[pos.layer]?.terrain(at: pos.point) else { return nil }
        return ctx.content.fields.values.sorted { $0.id < $1.id }.first { $0.terrains?.contains(t) == true }?.id
    }

    static func field(forPOI kind: POIKindID, _ content: ContentDB) -> FieldID? {
        content.fields.values.sorted { $0.id < $1.id }.first { $0.pois?.contains(kind) == true }?.id
    }

    /// その場の候補(引く前に絞ったもの。ID 順)。
    static func candidates(field: FieldID?, _ ctx: StepContext) -> [ExploreEventDef] {
        let w = ctx.world
        let range = w.exploration.range
        var f = field
        if let id = f, let def = ctx.content.fields[id], (def.minRange ?? 0) > range { f = nil }
        return ctx.content.exploreEvents.values.sorted { $0.id < $1.id }.filter { e in
            guard e.weight > 0, e.field == nil || e.field == f, (e.minRange ?? 0) <= range else { return false }
            if e.once == true, w.exploration.exploreFired[e.id] != nil { return false }
            if let c = e.when, ConditionEvaluator.evaluatePure(c, world: w, content: ctx.content) != true { return false }
            return true
        }
    }

    static func roll(field: FieldID?, person: PersonID, at pos: WorldPoint, poi: EntityID?, _ ctx: inout StepContext) {
        let list = candidates(field: field, ctx)
        let nothing = max(0, ctx.content.exploration.nothingWeight ?? 0)
        let total = list.reduce(0) { $0 + $1.weight } + nothing
        guard !list.isEmpty, total > 0 else { return }
        var roll = ctx.random(.exploration) { $0.int(below: total) }
        for e in list {
            if roll < e.weight {
                fire(e, person: person, at: pos, &ctx)
                return
            }
            roll -= e.weight
        }
    }

    static func fire(_ e: ExploreEventDef, person: PersonID, at pos: WorldPoint, _ ctx: inout StepContext) {
        var detail: [String: Value] = [:]
        if let f = e.field { detail["field"] = .string(f.rawValue) }
        if let t = e.text { detail["text"] = .string(t.rawValue) }
        let rec = ctx.record(.discovered, .event(e.id), actor: person, place: pos, tags: Set(e.tags ?? []),
                             detail: detail)
        ctx.world.exploration.exploreFired[e.id, default: 0] += 1
        Loot.give(e.yields ?? [], origin: rec, &ctx)
        var effects = e.effects ?? []
        if let s = e.scene { effects.append(.startScene(scene: s)) }
        if !effects.isEmpty { EffectApplier.apply(effects, &ctx, cause: rec) }
        ctx.emit(.explored(person: person, event: e.id, record: rec))
        ctx.changes.mark(.narrative)
    }
}
