import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld

/// 手作業(原作 HandCraft: 押し続けて進捗バーを満たすと 1 単位)。序盤の味で、その資源の T1 が動くと任意になる。
///
/// - 工程の手作業(粉 5 / 塊 8 / 板 16 回): 手元の物質 1 つに RuleBook の 1 段を当てる。燃料などは規則が使う分だけ。
/// - 採掘の手作業(onDeposit): 足元か隣の鉱脈を 1 回掘る(採掘口と同じ規則・同じ有限の鉱脈)。
/// - 拾う手作業(yields): 定義の物を得る。
/// できた物はノアの手元(持ち物)に入る(熱いまま次の手作業に使える)。入力は手元か、拠点の中なら蓄えから。
/// 昼は押している間だけリアルタイムで進む(1 回 = pressSeconds)。夜にできる手作業は 1 単位ずつ時間を使う。
enum Handwork {
    static func pressSeconds(_ def: HandworkDef) -> Int64 { Int64(max(1, def.pressSeconds ?? ProductionRules.defaultPressSeconds)) }

    static func handle(_ id: HandworkID, input: StockSelector?, holding: Bool, person p: PersonID,
                       _ ctx: inout StepContext) -> CommandResult {
        guard let def = ctx.content.handwork[id] else { return .rejected(Rejection(ProductionText.handworkUnknown)) }
        if !holding {
            if ctx.world.placements.handwork[p]?.id == id { ctx.world.placements.handwork[p]?.holding = false }
            return .done
        }
        let prepared: HandworkSession
        switch prepare(def, input: input, person: p, ctx.world, ctx.content) {
        case .failure(let r): return .rejected(r)
        case .success(let s): prepared = s
        }
        var s = prepared
        if let old = ctx.world.placements.handwork[p], old.id == id, old.input == s.input, old.deposit == s.deposit {
            s.progress = old.progress
            s.done = old.done
        }
        if ctx.world.clock.phase != .day {
            // 夜にできる手作業: 1 単位をまとめて行い、その時間を返す
            ctx.world.placements.handwork[p] = nil
            guard complete(def, s, person: p, &ctx) else { return .rejected(Rejection(ProductionText.handworkNoInput)) }
            let left = Int64(def.presses) * pressSeconds(def) - s.progress / 1000
            return .accepted(time: GameDuration(seconds: max(SimStep.gameSeconds, left)))
        }
        ctx.world.placements.handwork[p] = s
        ctx.changes.mark(.placements)
        return .done
    }

    /// 始められるか確かめて、途中の状態を作る。
    static func prepare(_ def: HandworkDef, input: StockSelector?, person p: PersonID, _ w: WorldState,
                        _ content: ContentDB) -> Result<HandworkSession, Rejection> {
        guard w.research.unlocked.handwork.contains(def.id) else { return .failure(Rejection(ProductionText.handworkLocked)) }
        guard (def.allowedPhases ?? [.day]).contains(w.clock.phase) else {
            return .failure(Rejection(ProductionText.handworkNotNow))
        }
        guard let ps = w.people[p], ps.presence.isAlive, let pos = ps.position else {
            return .failure(Rejection(ProductionText.handworkNoActor))
        }
        if let st = def.station {
            let near = w.placements.items.values.contains {
                $0.kind == .structure(st) && $0.at.layer == pos.layer && $0.at.point.chebyshev(to: pos.point) <= 1
            }
            if !near { return .failure(Rejection(ProductionText.handworkNeedsStation)) }
        }
        var s = HandworkSession(id: def.id, input: nil, holding: true, at: pos)
        if def.onDeposit == true {
            guard let d = depositNear(pos, w) else { return .failure(Rejection(ProductionText.handworkNeedsDeposit)) }
            if let dep = w.map[pos.layer]?.deposits[d], let r = MiningRules.check(dep, world: w, content: content) {
                return .failure(r)
            }
            s.deposit = d
            return .success(s)
        }
        guard let step = def.step else { return .success(s) }
        guard let sel = input ?? autoInput(p, pos, w) else { return .failure(Rejection(ProductionText.handworkNoInput)) }
        if let r = checkInput(sel, step: step, person: p, pos: pos, w, content) { return .failure(r) }
        s.input = sel
        return .success(s)
    }

    /// 足元か隣の、枯れていない鉱脈(足元 → 上下左右 → 斜めの順)。
    static func depositNear(_ pos: WorldPoint, _ w: WorldState) -> DepositID? {
        guard let l = w.map[pos.layer] else { return nil }
        for q in [pos.point] + pos.point.neighbors8 {
            if let d = l.deposits.deposit(at: q), !d.isDepleted { return d.id }
        }
        return nil
    }

    /// 手が届く在り処(手元。拠点の中なら蓄えも)。
    static func reachable(_ h: HolderID, person p: PersonID, pos: WorldPoint, _ w: WorldState) -> Bool {
        h == .person(p) || (h == .base && ModuleTopology.isInBase(pos, in: w))
    }

    static func autoInput(_ p: PersonID, _ pos: WorldPoint, _ w: WorldState) -> StockSelector? {
        for h in [HolderID.person(p), .base] where reachable(h, person: p, pos: pos, w) {
            if let e = w.inventory.entries(h).first(where: { if case .matter = $0.stuff { true } else { false } }) {
                return StockSelector(holder: h, stuff: e.stuff, unique: e.unique)
            }
        }
        return nil
    }

    static func checkInput(_ sel: StockSelector, step: ProcessStep, person p: PersonID, pos: WorldPoint,
                           _ w: WorldState, _ content: ContentDB) -> Rejection? {
        guard reachable(sel.holder, person: p, pos: pos, w) else { return Rejection(ProductionText.handworkOutOfReach) }
        guard w.inventory.entries(sel.holder).contains(where: { $0.stuff == sel.stuff && $0.unique == sel.unique }),
              case .matter(let m) = sel.stuff else { return Rejection(ProductionText.handworkNoInput) }
        let o = ProcessChain.advance(m, through: step, at: 1, rules: content.ruleBook)
        if o.matter == m {
            return Rejection(ProductionText.handworkNoEffect,
                             detail: ["finding": .string(o.findings.first?.id.rawValue ?? "")])
        }
        // 炉の工程を手でやる(手で溶かす P-06)は、隣の炉が熱いときだけ。燃料は炉で燃えている(W-03)
        let fuels: Set<ItemID>
        switch furnaceFuels(step, pos, w, content) {
        case .failure(let r): return r
        case .success(let f): fuels = f
        }
        for a in o.consumed where (a.item != .water || !touchesWater(pos, w, content)) && !fuels.contains(a.item) {
            let have = auxHolders(p, pos, w).reduce(0) { $0 + w.inventory.quantity(a.item, in: $1) }
            if have < a.quantity { return Rejection(ProductionText.handworkNoAux, detail: ["item": .string(a.item.rawValue)]) }
        }
        return nil
    }

    /// 工程の炉が熱を持つ炉なら、手の届く(隣の)熱い炉を探し、その燃料を返す。熱い炉が無ければ理由。
    /// 熱を持たない工程なら空。
    static func furnaceFuels(_ step: ProcessStep, _ pos: WorldPoint, _ w: WorldState, _ content: ContentDB)
        -> Result<Set<ItemID>, Rejection>
    {
        guard content.modules[step.module]?.hearth?.furnace != nil else { return .success([]) }
        for id in w.placements.moduleIDs {
            guard let p = w.placements.items[id], p.kind == .module(step.module), p.at.layer == pos.layer,
                  p.footprint.contains(where: { (p.at.point + $0).chebyshev(to: pos.point) <= 1 }),
                  FurnaceHeat.isHot(p, content) else { continue }
            return .success(FurnaceHeat.fuels(p, content))
        }
        return .failure(Rejection(FurnaceHeat.furnaceCold))
    }

    static func auxHolders(_ p: PersonID, _ pos: WorldPoint, _ w: WorldState) -> [HolderID] {
        [HolderID.person(p), .base].filter { reachable($0, person: p, pos: pos, w) }
    }

    static func touchesWater(_ pos: WorldPoint, _ w: WorldState, _ content: ContentDB) -> Bool {
        guard let l = w.map[pos.layer] else { return false }
        return PlacementCheck.touchesWater(pos.point, layer: l, content: content)
            || PlacementCheck.isWater(pos.point, layer: l, content: content)
    }

    // MARK: 進める

    static func step(_ ctx: inout StepContext) {
        guard !ctx.world.placements.handwork.isEmpty else { return }
        for p in ctx.world.placements.handwork.keys.sorted() {
            guard var s = ctx.world.placements.handwork[p], s.holding else { continue }
            guard ctx.world.clock.phase == .day, let def = ctx.content.handwork[s.id],
                  let ps = ctx.world.people[p], ps.presence.isAlive else {
                ctx.world.placements.handwork[p]?.holding = false
                continue
            }
            // 歩いている間・場所を離れたら進まない
            guard ps.motion == nil, ps.position == s.at else { continue }
            s.progress += SimStep.gameSeconds * 1000 * Int64(ProductionRules.workSpeed(p, ctx.world)) / 1000
            let need = Int64(def.presses) * pressSeconds(def) * 1000
            var go = true
            while go && s.progress >= need {
                s.progress -= need
                if complete(def, s, person: p, &ctx) {
                    s.done += 1
                    go = canContinue(def, s, person: p, ctx.world, ctx.content)
                } else {
                    go = false
                }
            }
            if !go {
                s.holding = false
                s.progress = 0
            }
            ctx.world.placements.handwork[p] = s
            ctx.changes.mark(.placements)
        }
    }

    static func canContinue(_ def: HandworkDef, _ s: HandworkSession, person p: PersonID, _ w: WorldState,
                            _ content: ContentDB) -> Bool {
        if def.onDeposit == true {
            guard let d = s.deposit, let pos = w.people[p]?.position else { return false }
            return w.map[pos.layer]?.deposits[d]?.isDepleted == false
        }
        guard let step = def.step else { return true }
        guard let sel = s.input, let pos = w.people[p]?.position else { return false }
        return checkInput(sel, step: step, person: p, pos: pos, w, content) == nil
    }

    /// 1 単位を仕上げる。できなければ false。
    static func complete(_ def: HandworkDef, _ s: HandworkSession, person p: PersonID, _ ctx: inout StepContext) -> Bool {
        guard let pos = ctx.world.people[p]?.position else { return false }
        let hand = HolderID.person(p)
        if def.onDeposit == true {
            guard let dep = s.deposit, let (yields, purity) = Mining.extract(dep, layer: pos.layer, &ctx) else { return false }
            let place = ctx.world.map[pos.layer]?.deposits[dep].map { WorldPoint(pos.layer, $0.position) }
            let first = yields.first?.item ?? .ironOre
            let rec = ctx.record(.mined, .item(first), actor: p, place: place,
                                 detail: ["deposit": .string(dep.rawValue), "handwork": .string(def.id.rawValue)])
            let n = yields.reduce(0) { $0 + $1.quantity }
            if n > 1 { ctx.world.ledger.update(rec) { $0.count = n } }
            for y in yields { ctx.addStock(Mining.stuff(for: y, depositPurity: purity), y.quantity, to: hand, origin: rec) }
            if let pl = place { ctx.changes.markTile(pl, .terrain) }
            return true
        }
        if let step = def.step {
            guard let sel = s.input, checkInput(sel, step: step, person: p, pos: pos, ctx.world, ctx.content) == nil,
                  case .matter(let m) = sel.stuff else { return false }
            let o = ProcessChain.advance(m, through: step, at: 1, rules: ctx.content.ruleBook)
            guard let taken = ctx.takeStock(1, from: sel.holder, where: { $0.stuff == sel.stuff && $0.unique == sel.unique })
            else { return false }
            var inputs = Array(taken.keys)
            let water = touchesWater(pos, ctx.world, ctx.content)
            let fuels = (try? furnaceFuels(step, pos, ctx.world, ctx.content).get()) ?? []
            for a in o.consumed where (a.item != .water || !water) && !fuels.contains(a.item) {
                var left = a.quantity
                for h in auxHolders(p, pos, ctx.world) where left > 0 {
                    let k = min(left, ctx.world.inventory.quantity(a.item, in: h))
                    guard k > 0, let t = ctx.takeStock(k, from: h, where: { $0.stuff == .item(a.item) && $0.unique == nil })
                    else { continue }
                    left -= k
                    inputs += t.keys
                }
            }
            let ins = Array(Set(inputs.filter { $0 != ProvenanceLedger.unknownOrigin })).sorted()
            let name = NameGenerator.name(for: o.matter)
            let rec = ctx.record(.crafted, .matter(name), actor: p, place: pos, inputs: ins,
                                 detail: ["handwork": .string(def.id.rawValue), "module": .string(step.module.rawValue)])
            ctx.addStock(.matter(o.matter), 1, to: hand, origin: rec)
            ctx.emit(.crafted(quantity: 1, record: rec))
            return true
        }
        // 拾う手作業
        var got: [(Stuff, Int)] = []
        for y in def.yields ?? [] {
            let n = ctx.random(.production) { rng -> Int in
                if let bp = y.basisPoints, !rng.chance(basisPoints: bp) { return 0 }
                return y.max > y.min ? rng.int(in: y.min...y.max) : y.min
            }
            guard n > 0, let stuff: Stuff = y.matter.map({ .matter($0) }) ?? y.item.map({ .item($0) }) else { continue }
            got.append((stuff, n))
        }
        let rec = ctx.record(.gathered, .none, actor: p, place: pos, detail: ["handwork": .string(def.id.rawValue)])
        for (stuff, n) in got { ctx.addStock(stuff, n, to: hand, origin: rec) }
        return true
    }
}
