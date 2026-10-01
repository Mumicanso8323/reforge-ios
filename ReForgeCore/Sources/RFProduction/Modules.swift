import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld

/// 置いたモジュールの 1 ステップ(昼のリアルタイムでも、夜の一括でも同じ)。
///
/// 1 回の処理 = RuleBook の 1 工程を `batch` 個に当てる(既定 1 回 = ゲーム 9600 秒 = 昼の実時間 60 秒)。
/// 採掘口は 1 回 = 鉱脈を 1 回掘る(有限。枯れたら止まる)。T1(採集所など)は定義の produces を出す。
/// 始められない(材料・燃料が来ない、出口が詰まった、鉱脈が枯れた)ときは止まり、理由を出す。
enum Modules {
    static func step(_ ctx: inout StepContext) {
        let ids = ctx.world.placements.moduleIDs
        for id in ids {
            refreshOperator(id, &ctx)
            if ModuleTopology.isInBase(id, in: ctx.world) { pullFromBase(id, &ctx) }
        }
        for id in ids { advance(id, &ctx) }
        for id in ids { pushOut(id, &ctx) }
    }

    /// 夜明けに 1 日の集計を回す。
    static func rollDay(_ ctx: inout StepContext) {
        for id in ctx.world.placements.moduleIDs {
            guard var m = ctx.world.placements.items[id]?.module else { continue }
            m.yesterday = m.today
            m.today = ThroughputTally()
            ctx.world.placements.items[id]?.module = m
        }
    }

    // MARK: 付いている仲間

    /// 配属が「このモジュールに付く」で、そばにいる(か、いまここで働いている)最初の一員。
    static func operatorOf(_ id: EntityID, _ w: WorldState) -> PersonID? {
        guard let p = w.placements.items[id] else { return nil }
        for pid in w.people.order {
            guard let ps = w.people[pid], ps.presence.isMember, pid != .noah else { continue }
            let a = ps.override?.assignment ?? ps.assignment
            guard a == .operate(placement: id) else { continue }
            if ps.activity == .working(at: id) { return pid }
            if let pos = ps.position, pos.layer == p.at.layer,
               pos.point.chebyshev(to: p.at.point) <= ProductionRules.operatorReach { return pid }
        }
        return nil
    }

    static func refreshOperator(_ id: EntityID, _ ctx: inout StepContext) {
        let op = operatorOf(id, ctx.world)
        if ctx.world.placements.items[id]?.module?.operatorID != op {
            ctx.world.placements.items[id]?.module?.operatorID = op
            ctx.changes.mark(.placements)
        }
    }

    /// 速さ(千分率)。付いている仲間(専門 +30%・関係ランク 3 以上 +10%。作業の速さが掛かる)、
    /// 有限の品、範囲の効果 workSpeed。
    static func speed(_ id: EntityID, _ w: WorldState, _ content: ContentDB) -> Int {
        guard let p = w.placements.items[id], let m = p.module, let kind = p.moduleKind else { return 1000 }
        var s = 1000
        if let op = m.operatorID ?? operatorOf(id, w), let ps = w.people[op] {
            var bonus = 0
            if let sp = content.modules[kind]?.specialty, content.people[op]?.specialties.contains(sp) == true {
                bonus += ProductionRules.specialtyBonusPermille
            }
            if ps.relation.rank >= ProductionRules.rankForBonus { bonus += ProductionRules.rankBonusPermille }
            s += bonus * ProductionRules.workSpeed(op, w) / 1000
        }
        if m.finite != nil, let f = content.modules[kind]?.finite { s = s * f.speedPermille / 1000 }
        for (mod, strength, _) in Auras.modifiers(at: p.at, in: w, content: content) {
            if case .workSpeed(let pm) = mod { s = s * (1000 + (pm - 1000) * strength / 1000) / 1000 }
        }
        return max(0, s)
    }

    // MARK: 蓄えとのやりとり(拠点の中)

    static func pullFromBase(_ id: EntityID, _ ctx: inout StepContext) {
        guard let m = ctx.world.placements.items[id]?.module else { return }
        for (item, missing) in m.auxShortfall {
            let have = ctx.world.inventory.quantity(item, in: .base)
            let k = min(have, missing)
            guard k > 0, let origins = ctx.takeStock(k, from: .base, where: { $0.unique == nil && $0.stuff == .item(item) })
            else { continue }
            ctx.world.placements.items[id]?.module?.today.received += k
            ModuleRuntime.put(StockEntry(stuff: .item(item), quantity: k, origins: origins),
                              into: &ctx.world.placements.items[id]!.module!.input)
        }
    }

    /// 出口の物を隣の直結へ渡す。直結も運搬の経路も無く、拠点の中なら蓄えへ入れる。
    static func pushOut(_ id: EntityID, _ ctx: inout StepContext) {
        guard let m = ctx.world.placements.items[id]?.module, !m.output.isEmpty else { return }
        if let down = ModuleTopology.directDownstream(of: id, in: ctx.world) {
            var moved = 0
            for e in m.output {
                guard let room = ctx.world.placements.items[down]?.module?.room(for: e.stuff), room > 0 else { continue }
                let pieces = ModuleRuntime.take(room, from: &ctx.world.placements.items[id]!.module!.output,
                                                where: { $0.stuff == e.stuff && $0.unique == e.unique })
                for piece in pieces {
                    ModuleRuntime.put(piece, into: &ctx.world.placements.items[down]!.module!.input)
                    moved += piece.quantity
                }
            }
            if moved > 0 {
                ctx.world.placements.items[id]?.module?.today.sent += moved
                ctx.world.placements.items[down]?.module?.today.received += moved
                ctx.changes.mark(.placements)
            }
            return
        }
        let routed = !ctx.world.logistics.routes(from: .placement(id)).isEmpty
        guard !routed, ModuleTopology.isInBase(id, in: ctx.world) else { return }
        let all = ctx.world.placements.items[id]!.module!.output
        ctx.world.placements.items[id]?.module?.output = []
        var n = 0
        for e in all {
            Placing.toBase(e, cool: true, &ctx)
            n += e.quantity
        }
        ctx.world.placements.items[id]?.module?.today.sent += n
        ctx.changes.mark(.placements)
    }

    // MARK: 1 回の処理

    enum Kind { case extract, produce, process, idle }

    static func kind(of m: ModuleRuntime, _ def: ModuleDef) -> Kind {
        if def.placement.requiresDeposit == true { return .extract }
        if def.produces != nil { return .produce }
        if m.takesMatter { return .process }
        return .idle
    }

    /// 始められない理由(始められるなら nil)と、来ていない物。
    static func blocker(_ id: EntityID, _ w: WorldState, _ content: ContentDB) -> (TextID, ItemID?)? {
        guard let p = w.placements.items[id], let m = p.module, let kind = p.moduleKind,
              let def = content.modules[kind] else { return (ProductionText.notAModule, nil) }
        switch Self.kind(of: m, def) {
        case .extract:
            guard let dep = m.deposit, let d = w.map[p.at.layer]?.deposits[dep] else { return (ProductionText.noDeposit, nil) }
            if d.isDepleted { return (ProductionText.depleted, nil) }
            if m.outputCount + 3 * m.batch > m.capacity { return (ProductionText.outputFull, nil) }
            return auxBlocker(m)
        case .produce:
            let most = (def.produces ?? []).reduce(0) { $0 + $1.max } * m.batch
            if m.outputCount + most > m.capacity { return (ProductionText.outputFull, nil) }
            return auxBlocker(m)
        case .process:
            if m.mainInputCount < 1 { return (ProductionText.noInput, nil) }
            if m.outputCount + 1 > m.capacity { return (ProductionText.outputFull, nil) }
            return auxBlocker(m)
        case .idle:
            return (ProductionText.noInput, nil)
        }
    }

    /// 1 単位ぶんの段の物が揃っているか。
    static func auxBlocker(_ m: ModuleRuntime) -> (TextID, ItemID?)? {
        for i in m.auxPerUnit.keys.sorted() where !m.freeItems.contains(i) {
            if m.inputCount(i) < m.auxPerUnit[i]! { return (ProductionText.noAux, i) }
        }
        return nil
    }

    static func advance(_ id: EntityID, _ ctx: inout StepContext) {
        guard let p = ctx.world.placements.items[id], let kind = p.moduleKind, let def = ctx.content.modules[kind]
        else { return }
        let dt = SimStep.gameSeconds
        if let (reason, item) = blocker(id, ctx.world, ctx.content) {
            setStatus(id, .stopped(reason: reason), waiting: item, &ctx)
            ctx.world.placements.items[id]?.module?.today.idleSeconds += dt
            return
        }
        setStatus(id, .running, waiting: nil, &ctx)
        let s = speed(id, ctx.world, ctx.content)
        ctx.world.placements.items[id]?.module?.today.runningSeconds += dt
        ctx.world.placements.items[id]?.module?.progress += dt * 1000 * Int64(s) / 1000
        let cycle = Int64(max(1, def.cycleSeconds)) * 1000
        guard let prog = ctx.world.placements.items[id]?.module?.progress, prog >= cycle else { return }
        ctx.world.placements.items[id]?.module?.progress = prog - cycle
        cycleOnce(id, def, &ctx)
    }

    static func setStatus(_ id: EntityID, _ s: PlacementStatus, waiting: ItemID?, _ ctx: inout StepContext) {
        guard let old = ctx.world.placements.items[id]?.status else { return }
        ctx.world.placements.items[id]?.module?.waitingFor = waiting
        guard old != s else { return }
        ctx.world.placements.items[id]?.status = s
        ctx.changes.mark(.placements)
        switch s {
        case .stopped(let r): ctx.emit(.moduleStopped(placement: id, reason: r))
        case .running: if case .stopped = old { ctx.emit(.moduleResumed(placement: id)) }
        default: break
        }
    }

    static func cycleOnce(_ id: EntityID, _ def: ModuleDef, _ ctx: inout StepContext) {
        guard let m = ctx.world.placements.items[id]?.module else { return }
        var made = 0
        switch kind(of: m, def) {
        case .extract: made = extract(id, &ctx)
        case .produce: made = produce(id, def, &ctx)
        case .process:
            for _ in 0..<m.batch {
                guard blocker(id, ctx.world, ctx.content) == nil, processOne(id, &ctx) else { break }
                made += 1
            }
        case .idle: break
        }
        guard made > 0 else { return }
        wearFinite(id, &ctx)
        ctx.world.placements.items[id]?.module?.today.produced += made
        ctx.world.placements.items[id]?.module?.lifetimeProduced += made
        ctx.changes.mark(.placements)
        ctx.emit(.produced(placement: id, quantity: made))
    }

    /// 主の材料を 1 つ取り、段を当てて出口へ。燃料・混ぜ物・水は規則が使う分だけ(水に接していれば水は只)。
    static func processOne(_ id: EntityID, _ ctx: inout StepContext) -> Bool {
        guard let m = ctx.world.placements.items[id]?.module, let step = m.step,
              let first = m.input.first(where: { if case .matter = $0.stuff { true } else { false } }),
              case .matter(let matter) = first.stuff else { return false }
        let o = ProcessChain.advance(matter, through: step, at: m.stepIndex ?? 0, rules: ctx.content.ruleBook)
        // 規則が使う物が揃っているか(先に確かめてから取る)
        var need: [ItemID: Int] = [:]
        for a in o.consumed where !m.freeItems.contains(a.item) { need[a.item, default: 0] += a.quantity }
        for (i, n) in need where m.inputCount(i) < n {
            setStatus(id, .stopped(reason: ProductionText.noAux), waiting: i, &ctx)
            return false
        }
        var inputs: [ProvenanceID] = []
        let main = ModuleRuntime.take(1, from: &ctx.world.placements.items[id]!.module!.input,
                                      where: { $0.stuff == first.stuff && $0.unique == first.unique })
        for e in main { inputs += e.origins.keys }
        for (i, n) in need.sorted(by: { $0.key < $1.key }) {
            let used = ModuleRuntime.take(n, from: &ctx.world.placements.items[id]!.module!.input,
                                          where: { $0.stuff == .item(i) })
            for e in used { inputs += e.origins.keys }
        }
        let rec = producedRecord(id, inputs: inputs, &ctx)
        ModuleRuntime.put(StockEntry(stuff: .matter(o.matter), quantity: 1, origins: [rec: 1]),
                          into: &ctx.world.placements.items[id]!.module!.output)
        ctx.world.placements.items[id]?.module?.today.consumed += 1
        noteFirstMatter(o.matter, module: rec, &ctx)
        return true
    }

    /// 採掘口: 鉱脈を batch 回掘る。鉄鉱石は鉱脈の純度の物質(塊)、ほかは物。
    static func extract(_ id: EntityID, _ ctx: inout StepContext) -> Int {
        guard let p = ctx.world.placements.items[id], let m = p.module, let dep = m.deposit else { return 0 }
        var made = 0
        for _ in 0..<m.batch {
            guard let (all, purity) = Mining.extract(dep, layer: p.at.layer, &ctx) else { break }
            let keep = ctx.world.map[p.at.layer]?.deposits[dep].flatMap { Mining.primary($0.category) }
            let yields = all.filter { keep?.contains($0.item) ?? true }
            let n = yields.reduce(0) { $0 + $1.quantity }
            guard n > 0 else { continue }
            let rec = producedRecord(id, inputs: [], &ctx)
            if n > 1 { ctx.world.ledger.update(rec) { $0.count += n - 1 } }
            for y in yields {
                let stuff = Mining.stuff(for: y, depositPurity: purity)
                ModuleRuntime.put(StockEntry(stuff: stuff, quantity: y.quantity, origins: [rec: y.quantity]),
                                  into: &ctx.world.placements.items[id]!.module!.output)
                if case .matter(let mm) = stuff { noteFirstMatter(mm, module: rec, &ctx) }
            }
            made += n
            ctx.changes.markTile(WorldPoint(p.at.layer, p.at.point), .terrain)
        }
        return made
    }

    /// T1: 使う物を取って、定義の物を出す。
    static func produce(_ id: EntityID, _ def: ModuleDef, _ ctx: inout StepContext) -> Int {
        guard let m = ctx.world.placements.items[id]?.module else { return 0 }
        var made = 0
        for _ in 0..<m.batch {
            guard auxBlocker(ctx.world.placements.items[id]!.module!) == nil else { break }
            var inputs: [ProvenanceID] = []
            for (i, n) in m.auxPerUnit.sorted(by: { $0.key < $1.key }) where !m.freeItems.contains(i) {
                for e in ModuleRuntime.take(n, from: &ctx.world.placements.items[id]!.module!.input,
                                            where: { $0.stuff == .item(i) }) { inputs += e.origins.keys }
            }
            var rolled: [(Stuff, Int)] = []
            for y in def.produces ?? [] {
                let n = ctx.random(.production) { rng -> Int in
                    if let bp = y.basisPoints, !rng.chance(basisPoints: bp) { return 0 }
                    return y.max > y.min ? rng.int(in: y.min...y.max) : y.min
                }
                guard n > 0, let stuff: Stuff = y.matter.map({ .matter($0) }) ?? y.item.map({ .item($0) }) else { continue }
                rolled.append((stuff, n))
            }
            let unit = rolled.reduce(0) { $0 + $1.1 }
            guard unit > 0 else { continue }
            let rec = producedRecord(id, inputs: inputs, &ctx)
            if unit > 1 { ctx.world.ledger.update(rec) { $0.count += unit - 1 } }
            for (stuff, n) in rolled {
                ModuleRuntime.put(StockEntry(stuff: stuff, quantity: n, origins: [rec: n]),
                                  into: &ctx.world.placements.items[id]!.module!.output)
            }
            made += unit
        }
        return made
    }

    /// 生産の来歴(1 日・入力の来歴の組ごとに 1 件。同じ日に同じ入力から作った分は count を増やす)。
    /// 1 件目は数 1 で作る。返した記録に 1 個ぶん数えてある。
    static func producedRecord(_ id: EntityID, inputs raw: [ProvenanceID], _ ctx: inout StepContext) -> ProvenanceID {
        let p = ctx.world.placements.items[id]!
        let m = p.module!
        var ins = Array(Set(raw.filter { $0 != ProvenanceLedger.unknownOrigin })).sorted()
        if let cur = m.producedRecord, let r = ctx.world.ledger.record(cur), r.day == ctx.world.clock.day,
           r.run == ctx.world.run.index, Set(ins).isSubset(of: r.inputs)
        {
            ctx.world.ledger.update(cur) { $0.count += 1 }
            return cur
        }
        ins = Array(ins.prefix(8))
        var all = [p.origin]
        if let f = m.finiteRecord { all.append(f) }
        all += ins.filter { !all.contains($0) }
        let rec = ctx.record(.produced, .module(p.moduleKind!, id), actor: m.operatorID, place: p.at, inputs: all)
        ctx.world.placements.items[id]?.module?.producedRecord = rec
        return rec
    }

    /// 初めてこの名前の物ができたとき、物の名前で 1 件残す(「初めて精鉄板をラインで作った」の条件のため)。
    static func noteFirstMatter(_ m: Matter, module rec: ProvenanceID, _ ctx: inout StepContext) {
        let name = NameGenerator.name(for: m)
        guard ctx.world.ledger.first(.produced, .matter(name)) == nil else { return }
        let r = ctx.world.ledger.record(rec)
        ctx.record(.produced, .matter(name), actor: r?.actor, place: r?.place, inputs: [rec])
    }

    /// 有限の品が 1 回ぶん減る。尽きたら無くなり、戻らない(来歴に残す)。
    static func wearFinite(_ id: EntityID, _ ctx: inout StepContext) {
        guard let p = ctx.world.placements.items[id], let kind = p.moduleKind, var m = p.module, var f = m.finite,
              let def = ctx.content.modules[kind]?.finite else { return }
        let left = (f.durability ?? ProductionRules.finiteFull).raw - Int64(def.wearPerCycle)
        if left > 0 {
            f.durability = Milli(raw: left)
            m.finite = f
        } else {
            guard case .item(let item) = f.stuff else { return }
            let subject: SubjectRef = f.unique.map { .entity($0) } ?? .item(item)
            ctx.record(.consumed, subject, place: p.at, inputs: m.finiteRecord.map { [$0] } ?? [],
                       detail: ["wornOut": .bool(true), "module": .string(kind.rawValue)])
            m.finite = nil
        }
        ctx.world.placements.items[id]?.module = m
    }
}

/// 鉱脈を掘る(採掘口と手の採掘で同じ規則)。鉱脈の残りは有限で、0 で枯れる。
enum Mining {
    /// 1 回掘る。枯れていれば nil。出た物と、鉱脈の純度(鉄鉱石の物質の純度)。
    static func extract(_ dep: DepositID, layer: LayerID, _ ctx: inout StepContext) -> ([OreYield], Purity)? {
        guard var l = ctx.world.map[layer], let d = l.deposits[dep], !d.isDepleted else { return nil }
        var rngs = ctx.world.rng
        let y = rngs.use(.production) { l.deposits.extract(dep, rng: &$0) }
        ctx.world.rng = rngs
        ctx.world.map[layer] = l
        guard let y else { return nil }
        return (y, d.purity)
    }

    /// 採掘口が出す物(鉱脈の主な物だけ。石などの捨て石は出さない)。nil は全部(土石の鉱脈)。
    /// 手で掘るときは全部を拾う。
    static func primary(_ c: DepositCategory) -> Set<ItemID>? {
        switch c {
        case .iron, .mixed, .rare: [.ironOre]
        case .coal: [.coal]
        case .copper: ["copper_ore"]
        case .quarry: nil
        }
    }

    /// 掘った物を在庫の中身にする。鉄鉱石は鉱脈の純度(Fe2O3 の割合)の塊の物質。
    static func stuff(for y: OreYield, depositPurity: Purity) -> Stuff {
        y.item == .ironOre ? .matter(Matter.ironOre(purity: depositPurity)) : .item(y.item)
    }
}
