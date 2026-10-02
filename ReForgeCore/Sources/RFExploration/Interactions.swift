import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld

/// 行為の対象を解決したもの。
struct ResolvedTarget: Equatable {
    var poi: EntityID?
    var poiKind: POIKindID?
    var poiAt: GridPoint?
    var poiFootprint: [GridPoint] = []
    var deposit: DepositID?
    var placement: EntityID?
    /// 行為を向けられるマス(このどれかから 1 マス以内にいれば届く)。
    var cells: [GridPoint]
    var layer: LayerID
}

/// マス・POI・置いた物に対する行為(漁る・汲む・掘る・解体する・作り直す・直す)。
///
/// - 昼: 始めると exploration.active に入り、固定ステップごとに進む(押し続ける行為は押している間だけ)。
///   終わると得られる物が拠点の蓄えに入り、来歴が残る。届かない所へ動いたら取りやめ(使った材料は戻る)。
/// - 夜作業: その場で終わり、かかった時間を返す(本体がその分のステップを進める)。
/// - 回数: POI の残りの回数(残骸を漁る 10 回・遺跡のスクラップ)と、定義の limit。採集はクールダウンの日数。
/// - 有限の部品: PartOp(取り外し・解体・作り直し・修理の段階)。状態は exploration.poi[POI].parts に来歴つきで残る。
enum Interactions {
    /// 手の届く距離(マス。チェビシェフ)。
    static let reach = 1

    // MARK: コマンド

    static func command(_ id: InteractionID, at: WorldPoint, holding: Bool, actor: PersonID,
                        _ ctx: inout StepContext) -> CommandResult {
        guard let def = ctx.content.interactions[id] else { return .rejected(Rejection("reason.explore.unknown")) }
        if def.continues == true, let r = continueSignal(def, at: at, holding: holding, actor: actor, &ctx) { return r }
        // 進行中の同じ行為への合図(押すのをやめた・取りやめ・押し直し)
        if let a = ctx.world.exploration.active[actor], a.interaction == id, a.at == at {
            if holds(def) {
                ctx.world.exploration.active[actor]?.holding = holding
                ctx.changes.mark(.people)
                return .done
            }
            if !holding {
                cancel(actor, &ctx)
                return .done
            }
            return .done
        }
        switch start(def, at: at, holding: holding, actor: actor, &ctx) {
        case .failure(let r): return .rejected(r)
        case .success(let t): return .accepted(time: t)
        }
    }

    /// 押している間だけ進む行為か(押し続ける行為と、続けて採る行為)。
    static func holds(_ def: InteractionDef) -> Bool { def.hold || def.continues == true }

    /// 続けて採る行為への押す・離すの合図。進行中の行為の場所が押した場所と違っても(次のマスへ移っている)、
    /// 同じ行為なら 1 つの流れとして扱う。扱ったら結果を返す。
    private static func continueSignal(_ def: InteractionDef, at: WorldPoint, holding: Bool, actor: PersonID,
                                       _ ctx: inout StepContext) -> CommandResult? {
        guard let a = ctx.world.exploration.active[actor], a.interaction == def.id else {
            // 進行中でない離した合図は、何もしない(離した後に別の場所で始め直さない)
            return holding ? nil : .done
        }
        if holding {
            // 離している間に作りかけの単位があり、まだ届くなら、押し直しは続きから(INV-B1-2)
            guard a.at != at, !a.holding, a.progress > 0,
                  let pos = ctx.world.people[actor]?.position,
                  case .success(let t) = resolve(def, at: a.at, world: ctx.world, content: ctx.content),
                  inReach(pos, t) else { return nil }
            ctx.world.exploration.active[actor]?.holding = true
            ctx.changes.mark(.people)
            return .done
        }
        ctx.world.exploration.active[actor]?.holding = false
        // 歩いている途中で離したら歩きを止める
        if actor == .noah, ctx.world.people[actor]?.motion != nil, let pos = ctx.world.people[actor]?.position {
            let near: Bool = {
                guard case .success(let t) = resolve(def, at: a.at, world: ctx.world, content: ctx.content) else { return false }
                return inReach(pos, t)
            }()
            if !near { ctx.queue(.crew(.stop)) }
        }
        ctx.changes.mark(.people)
        return .done
    }

    /// 行為を始める。夜作業ならその場で終え、かかった時間を返す。
    /// requireReach を false にすると、手の届かない所でも始める(続けて採るで、歩いて次のマスへ移るとき)。
    static func start(_ def: InteractionDef, at: WorldPoint, holding: Bool, actor: PersonID,
                      requireReach: Bool = true, _ ctx: inout StepContext) -> Result<GameDuration?, Rejection> {
        let w = ctx.world
        guard let person = w.people[actor], person.presence.isMember, let pos = person.position else {
            return .failure(Rejection("reason.explore.no_actor"))
        }
        let phases = def.allowedPhases ?? [.day, .nightWork]
        guard phases.contains(w.clock.phase) else { return .failure(Rejection("reason.explore.phase")) }
        let target: ResolvedTarget
        switch resolve(def, at: at, world: w, content: ctx.content) {
        case .failure(let r): return .failure(r)
        case .success(let t): target = t
        }
        guard !requireReach || inReach(pos, target) else { return .failure(Rejection("reason.explore.too_far")) }
        if let c = def.when, ConditionEvaluator.evaluatePure(c, world: w, content: ctx.content) != true {
            return .failure(Rejection("reason.explore.not_yet"))
        }
        if let r = checkLimits(def, at: at, target: target, world: w) { return .failure(r) }
        var part: String?
        if let op = def.partOp {
            switch choosePart(op, at: at, target: target, world: w, content: ctx.content) {
            case .failure(let r): return .failure(r)
            case .success(let p): part = p
            }
        }
        // 夜作業は 1 人でやるので、何人も要る行為はその場の人数で判定する
        if let need = def.requiredPeople, need > 1, helpers(target, world: w) < need {
            return .failure(Rejection("reason.explore.need_more_people", detail: ["count": .int(Int64(need))]))
        }
        guard let spent = takeCost(def.cost ?? [], &ctx) else {
            return .failure(Rejection("reason.explore.missing_cost"))
        }
        // 前の行為は取りやめ(使った材料は戻す)
        if ctx.world.exploration.active[actor] != nil { cancel(actor, &ctx) }
        if actor == .noah, ctx.world.exploration.continueStop != nil { ctx.world.exploration.continueStop = nil }
        let active = ActiveInteraction(interaction: def.id, at: at, poi: target.poi, part: part, holding: holding,
                                       spent: spent, startedAt: w.clock.now)
        if w.clock.phase == .nightWork || def.seconds <= 0 {
            complete(def, active, actor: actor, target: target, &ctx)
            return .success(w.clock.phase == .nightWork && def.seconds > 0 ? GameDuration(seconds: Int64(def.seconds)) : nil)
        }
        ctx.world.exploration.active[actor] = active
        ctx.changes.mark(.people)
        return .success(nil)
    }

    /// 取りやめる。使った材料は同じ来歴で戻す。
    static func cancel(_ actor: PersonID, _ ctx: inout StepContext) {
        guard let a = ctx.world.exploration.active.removeValue(forKey: actor) else { return }
        for lot in a.spent {
            for (o, n) in lot.origins.sorted(by: { $0.key < $1.key }) { ctx.addStock(lot.stuff, n, to: .base, origin: o) }
        }
        ctx.changes.mark(.people)
    }

    // MARK: ステップ

    /// 進行中の行為を 1 ステップ進める(昼だけ)。
    static func advance(_ ctx: inout StepContext) {
        guard ctx.world.clock.phase == .day else { return }
        for actor in ctx.world.exploration.active.keys.sorted() {
            guard let a = ctx.world.exploration.active[actor] else { continue }
            guard let def = ctx.content.interactions[a.interaction],
                  case .success(let target) = resolve(def, at: a.at, world: ctx.world, content: ctx.content),
                  let p = ctx.world.people[actor], p.presence.isAlive, let pos = p.position
            else {
                cancel(actor, &ctx)
                continue
            }
            if !inReach(pos, target) {
                // 続けて採るで次のマスへ歩いている間は、着くまで待つ
                if def.continues == true, a.holding, p.motion != nil { continue }
                cancel(actor, &ctx)
                continue
            }
            if holds(def) && !a.holding { continue }
            if p.motion != nil { continue }
            if let need = def.requiredPeople, need > 1, helpers(target, world: ctx.world) < need { continue }
            // 人の速さ(仲間の採取はノアの 0.6 倍。W-04)
            let speed = workSpeed(at: pos, ctx) * CrewWork.gatherPermille(actor, ctx.world, ctx.content) / 1000
            ctx.world.exploration.active[actor]?.progress += SimStep.gameSeconds * Int64(speed) / 1000
            if (ctx.world.exploration.active[actor]?.progress ?? 0) >= Int64(def.seconds) {
                let done = ctx.world.exploration.active.removeValue(forKey: actor)!
                complete(def, done, actor: actor, target: target, &ctx)
                if def.continues == true, done.holding, actor == .noah { continueNoah(def, from: done, &ctx) }
            }
        }
    }

    /// 「採取を続ける」配属の仲間が届く所にいれば、行為を始める(終わればまた始める)。
    static func startAssignedGathering(_ ctx: inout StepContext) {
        guard ctx.world.clock.phase == .day else { return }
        let allowed = CrewWork.working(ctx.world, ctx.content)
        for pid in ctx.world.people.members where pid != .noah {
            guard let p = ctx.world.people[pid], ctx.world.exploration.active[pid] == nil, p.motion == nil else { continue }
            let a = p.override?.assignment ?? p.assignment
            guard case .gather(let iid, let at) = a, let def = ctx.content.interactions[iid] else { continue }
            if let allowed, !allowed.contains(pid) { continue }   // 働ける人数の外(INV-O10)
            if case .failure(let r) = start(def, at: at, holding: true, actor: pid, &ctx), def.continues == true,
               r.reason == "reason.explore.exhausted" || r.reason == "reason.explore.cooldown" {
                hopCompanion(pid, def, at: at, position: p.position, &ctx)
            }
        }
    }

    // MARK: 続けて採る(PT-B1)

    /// ノアの 1 単位ができた後。次の場所へ(同じマス・届く所・歩いて半径の中)。無ければ止まって印を残す。
    static func continueNoah(_ def: InteractionDef, from done: ActiveInteraction, _ ctx: inout StepContext) {
        guard let pos = ctx.world.people[.noah]?.position else { return }
        guard let next = ContinueRules.next(interaction: def, from: pos, world: ctx.world, content: ctx.content,
                                            current: done.at, standing: pos),
              case .success = start(def, at: next, holding: true, actor: .noah, requireReach: false, &ctx)
        else {
            ctx.world.exploration.continueStop = ContinueStop(interaction: def.id, at: done.at)
            ctx.changes.mark(.people)
            return
        }
        if ctx.world.exploration.active[.noah] != nil, !reaches(.noah, next, def, ctx) {
            ctx.queue(.crew(.walk(to: next)))
        }
    }

    private static func reaches(_ actor: PersonID, _ at: WorldPoint, _ def: InteractionDef, _ ctx: StepContext) -> Bool {
        guard let pos = ctx.world.people[actor]?.position,
              case .success(let t) = resolve(def, at: at, world: ctx.world, content: ctx.content) else { return false }
        return inReach(pos, t)
    }

    /// 仲間の配属のマスで採れなくなった。配属の時の場所から半径の中の次のマスへ配属を移す(同じ選び方)。
    /// 半径の外へは出ない。無ければそのまま(配属のマスに居続ける)。
    static func hopCompanion(_ pid: PersonID, _ def: InteractionDef, at: WorldPoint, position: WorldPoint?,
                             _ ctx: inout StepContext) {
        let origin: WorldPoint = {
            if let h = ctx.world.exploration.continueHome?[pid], h.cell == at { return h.origin }
            return at
        }()
        guard let next = ContinueRules.next(interaction: def, from: origin, world: ctx.world, content: ctx.content,
                                            current: at, standing: position ?? origin), next != at else { return }
        let new = Assignment.gather(interaction: def.id, at: next)
        if ctx.world.people[pid]?.override?.assignment != nil {
            ctx.world.people[pid]?.override?.assignment = new
        } else {
            ctx.world.people[pid]?.assignment = new
        }
        var homes = ctx.world.exploration.continueHome ?? [:]
        homes[pid] = ContinueHome(origin: origin, cell: next)
        ctx.world.exploration.continueHome = homes
        ctx.changes.mark(.people)
    }

    // MARK: 終わる

    static func complete(_ def: InteractionDef, _ a: ActiveInteraction, actor: PersonID, target: ResolvedTarget,
                         _ ctx: inout StepContext) {
        let at = a.at
        let inputs = a.spent.flatMap { $0.origins.keys }.filter { $0 != ProvenanceLedger.unknownOrigin }
        let uniqInputs = Array(Set(inputs)).sorted()
        let act: ActKind
        let subject: SubjectRef
        if let op = def.partOp, let poi = target.poi, let part = a.part {
            subject = .part(poi, part)
            if op.repairTo != nil { act = .repaired } else if op.to == .rebuilt { act = .rebuiltPart } else { act = .salvagedPart }
        } else if let poi = target.poi, let kind = target.poiKind {
            act = .scavenged
            subject = .poi(kind, poi)
        } else if target.deposit != nil {
            act = .mined
            subject = .interaction(def.id)
        } else if target.placement != nil {
            act = .used
            subject = .interaction(def.id)
        } else {
            act = .gathered
            subject = .interaction(def.id)
        }
        var detail: [String: Value] = ["interaction": .string(def.id.rawValue)]
        if let part = a.part { detail["part"] = .string(part) }
        let rec = ctx.record(act, subject, actor: actor, place: at, inputs: uniqInputs, tags: Set(def.tags ?? []),
                             detail: detail)

        // 得られる物
        let yields = def.partOp.flatMap { op in a.part.flatMap { op.partYields?[$0] } } ?? def.yields
        // 行き先(P-12): 置いた物に対する行為で yieldsTo = site なら、その置いた物の中に溜める
        let holder: HolderID = def.yieldsTo == .site ? target.placement.map { HolderID.placement($0) } ?? .base : .base
        Loot.give(yields, origin: rec, to: holder, &ctx)
        if let dep = target.deposit {
            var map = ctx.world.map
            let ores = ctx.random(.exploration) { rng in map.extract(dep, layer: target.layer, rng: &rng) } ?? []
            ctx.world.map = map
            for o in ores { ctx.addStock(Loot.stuff(for: o), o.quantity, to: .base, origin: rec) }
            ctx.changes.markTile(at)
        }

        // 有限の部品
        if let op = def.partOp, let poi = target.poi, let part = a.part {
            var prog = ctx.world.exploration.poi[poi] ?? POIProgress()
            if let to = op.to {
                switch to {
                case .intact: prog.parts[part] = .intact
                case .salvaged: prog.parts[part] = .salvaged(record: rec)
                case .dismantled: prog.parts[part] = .dismantled(record: rec)
                case .rebuilt: prog.parts[part] = .rebuilt(record: rec)
                }
            }
            if let r = op.repairTo { prog.repair[part] = r }
            ctx.world.exploration.poi[poi] = prog
            ctx.emit(.partChanged(poi: poi, part: part, record: rec))
            if let pa = target.poiAt {
                let off = PlacementPartIndex.offset(of: part, footprint: target.poiFootprint,
                                                    parts: ctx.content.pois[target.poiKind ?? ""]?.parts ?? [])
                ctx.changes.markTile(WorldPoint(target.layer, off.map { pa + $0 } ?? pa))
            }
        }

        // 回数・クールダウン
        if def.partOp == nil, let poi = target.poi, let pid = mapPlacementID(poi, layer: target.layer, ctx.world),
           ctx.world.map[target.layer]?.placements[pid]?.remainingUses != nil {
            ctx.world.map[target.layer]?.placements.update(pid) { $0.remainingUses = max(0, ($0.remainingUses ?? 0) - 1) }
            ctx.changes.markTile(at)
        }
        let key = ExplorationState.countKey(def.id, poi: target.poi, at: at)
        ctx.world.exploration.interactionCounts[key, default: 0] += 1
        if (def.cooldownDays ?? 0) > 0 { ctx.world.exploration.harvestedDay[key] = ctx.world.clock.day }

        // 手でやった(INV-O8。知識の側)
        if actor == .noah { CrewWork.noteHand(CrewWork.family(of: def), &ctx.world) }
        ctx.emit(.interacted(person: actor, interaction: def.id, at: at, record: rec))
        ctx.changes.mark([.people, .inventory])
        if let effects = def.effects, !effects.isEmpty { EffectApplier.apply(effects, &ctx, cause: rec) }
    }

    // MARK: 対象・条件

    static func resolve(_ def: InteractionDef, at: WorldPoint, world w: WorldState, content: ContentDB)
        -> Result<ResolvedTarget, Rejection>
    {
        guard let layer = w.map[at.layer], layer.size.contains(at.point) else {
            return .failure(Rejection("reason.explore.no_target"))
        }
        let none = Rejection("reason.explore.no_target")
        switch def.target {
        case .terrain(let tag):
            guard let t = layer.terrain(at: at.point) else { return .failure(none) }
            let tags = content.terrains[t]?.tags ?? [t.rawValue]
            guard tags.contains(tag) || t.rawValue == tag else { return .failure(none) }
            return .success(ResolvedTarget(cells: [at.point], layer: at.layer))
        case .poi(let kind):
            for (e, poi) in layer.pois.sorted(by: { $0.key < $1.key }) where poi.kind == kind {
                let cells = poi.footprint.map { poi.at + $0 }
                if cells.contains(at.point) {
                    return .success(ResolvedTarget(poi: e, poiKind: kind, poiAt: poi.at, poiFootprint: poi.footprint,
                                                   cells: cells, layer: at.layer))
                }
            }
            return .failure(none)
        case .deposit:
            guard let d = layer.deposits.deposit(at: at.point) else { return .failure(none) }
            if let cats = def.depositCategories, !cats.contains(d.category) { return .failure(none) }
            guard !d.isDepleted else { return .failure(Rejection("reason.explore.depleted")) }
            if let r = MiningRules.check(d, extra: def.bladeTier, world: w, content: content) { return .failure(r) }
            return .success(ResolvedTarget(deposit: d.id, cells: [at.point], layer: at.layer))
        case .structure(let kind):
            return placed(.structure(kind), at: at, world: w).map { .success($0) } ?? .failure(none)
        case .module(let kind):
            return placed(.module(kind), at: at, world: w).map { .success($0) } ?? .failure(none)
        }
    }

    private static func placed(_ kind: PlaceableKind, at: WorldPoint, world w: WorldState) -> ResolvedTarget? {
        for e in w.placements.at(at) {
            guard let p = w.placements.items[e], p.kind == kind, p.status == .running else { continue }
            return ResolvedTarget(placement: e, cells: p.footprint.map { p.at.point + $0 }, layer: at.layer)
        }
        return nil
    }

    static func inReach(_ pos: WorldPoint, _ t: ResolvedTarget) -> Bool {
        pos.layer == t.layer && t.cells.contains { $0.chebyshev(to: pos.point) <= reach }
    }

    /// 対象のそばで止まっている一員の数(大きすぎる扉や設備に何人付いているか)。
    static func helpers(_ t: ResolvedTarget, world w: WorldState) -> Int {
        w.people.members.filter { id in
            guard let p = w.people[id], p.motion == nil, let pos = p.position else { return false }
            return inReach(pos, t)
        }.count
    }

    static func checkLimits(_ def: InteractionDef, at: WorldPoint, target: ResolvedTarget, world w: WorldState) -> Rejection? {
        if def.partOp == nil, let poi = target.poi, let pid = mapPlacementID(poi, layer: target.layer, w),
           let left = w.map[target.layer]?.placements[pid]?.remainingUses, left <= 0 {
            return Rejection("reason.explore.exhausted")
        }
        let key = ExplorationState.countKey(def.id, poi: target.poi, at: at)
        if let limit = def.limit, w.exploration.interactionCounts[key, default: 0] >= limit {
            return Rejection("reason.explore.exhausted")
        }
        if let cd = def.cooldownDays, cd > 0, let last = w.exploration.harvestedDay[key], w.clock.day - last < cd {
            return Rejection("reason.explore.cooldown", detail: ["days": .int(Int64(cd - (w.clock.day - last)))])
        }
        return nil
    }

    static func choosePart(_ op: PartOp, at: WorldPoint, target: ResolvedTarget, world w: WorldState,
                           content: ContentDB) -> Result<String, Rejection> {
        guard let poi = target.poi, let kind = target.poiKind else { return .failure(Rejection("reason.explore.no_part")) }
        let parts = content.pois[kind]?.parts ?? []
        let prog = w.exploration.poi[poi] ?? POIProgress()
        func ok(_ name: String) -> Bool {
            let st = prog.part(name)
            if let from = op.from, !from.contains(st.name) { return false }
            if let r = op.repairTo {
                if case .dismantled = st { return false }
                if case .salvaged = st { return false }
                if prog.repair[name, default: 0] != r - 1 { return false }
            }
            return true
        }
        if let p = op.part { return ok(p) ? .success(p) : .failure(Rejection("reason.explore.part_state")) }
        if let pa = target.poiAt,
           let p = PlacementPartIndex.part(atOffset: at.point - pa, footprint: target.poiFootprint, parts: parts), ok(p) {
            return .success(p)
        }
        if let p = parts.first(where: ok) { return .success(p) }
        return .failure(Rejection("reason.explore.no_part"))
    }

    static func mapPlacementID(_ e: EntityID, layer: LayerID, _ w: WorldState) -> PlacementID? {
        w.map[layer]?.placements.all.first { $0.entity == e }?.id
    }

    /// 材料を拠点の蓄えから取る。足りなければ何も取らずに nil。
    static func takeCost(_ cost: [Ingredient], _ ctx: inout StepContext) -> [CostLot]? {
        for ing in cost {
            let have = ctx.world.inventory.entries(.base).filter(ing.matches).reduce(0) { $0 + $1.quantity }
            if have < ing.quantity { return nil }
        }
        var lots: [CostLot] = []
        for ing in cost {
            var left = ing.quantity
            for e in ctx.world.inventory.entries(.base) where left > 0 && ing.matches(e) && e.unique == nil {
                let k = min(left, e.quantity)
                if let took = ctx.takeStock(k, from: .base, where: { $0.stuff == e.stuff && $0.unique == nil }) {
                    lots.append(CostLot(stuff: e.stuff, origins: took))
                    left -= k
                }
            }
        }
        return lots
    }

    /// 範囲の効果の作業の速さ(千分率)。
    static func workSpeed(at pos: WorldPoint, _ ctx: StepContext) -> Int {
        var speed = 1000
        for (m, strength, _) in Auras.modifiers(at: pos, in: ctx.world, content: ctx.content) {
            if case .workSpeed(let p) = m { speed = speed * (1000 + (p - 1000) * strength / 1000) / 1000 }
        }
        return max(0, speed)
    }
}

/// 得られる物を在庫に入れる(探索の乱数の流れで数を決める)。
enum Loot {
    static func give(_ ys: [Yield], origin: ProvenanceID, to holder: HolderID = .base, _ ctx: inout StepContext) {
        for y in ys {
            let n = ctx.random(.exploration) { rng -> Int in
                if let bp = y.basisPoints, !rng.chance(basisPoints: bp) { return 0 }
                return y.max > y.min ? rng.int(in: y.min...y.max) : y.min
            }
            guard n > 0 else { continue }
            let stuff: Stuff
            if let m = y.matter { stuff = .matter(m) } else if let i = y.item { stuff = .item(i) } else {
                ctx.warnings.append("得られる物に item も matter も無い")
                continue
            }
            let durability = y.durability.map { Milli(raw: Int64($0)) }
            if y.unique == true {
                for _ in 0..<n {
                    ctx.addStock(stuff, 1, to: holder, origin: origin, unique: ctx.world.newEntityID(),
                                 durability: durability, attributes: y.attributes)
                }
            } else {
                ctx.addStock(stuff, n, to: holder, origin: origin, durability: durability, attributes: y.attributes)
            }
        }
    }

    /// 鉱脈から出た物を在庫の中身にする(鉄鉱石は純度つきの物質、それ以外は物の ID)。
    static func stuff(for o: OreYield) -> Stuff {
        if o.item == .ironOre { return .matter(.ironOre(purity: o.purity)) }
        return .item(o.item)
    }
}
