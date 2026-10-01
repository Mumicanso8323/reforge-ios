import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld

/// 置ける場所の規則(画面の照準の影の緑/赤にも使う。世界を変えない)。
public enum PlacementCheck {
    /// 置けるなら nil、置けなければ理由(1 行)。excluding は「動かす」ときの自分。
    public static func check(_ kind: ModuleKindID, at: WorldPoint, facing: Direction, excluding: EntityID? = nil,
                             payingCost: Bool = true, world w: WorldState, content: ContentDB) -> Rejection? {
        guard let def = content.modules[kind] else { return Rejection(ProductionText.unknownModule) }
        guard w.research.unlocked.modules.contains(kind) else {
            return Rejection(ProductionText.locked, detail: ["module": .string(kind.rawValue)])
        }
        guard let layer = w.map[at.layer], layer.size.contains(at.point) else { return Rejection(ProductionText.outOfMap) }
        if w.placements.at(at).contains(where: { $0 != excluding }) { return Rejection(ProductionText.occupied) }
        for poi in layer.pois.values where poi.footprint.contains(where: { poi.at + $0 == at.point }) {
            return Rejection(ProductionText.occupied)
        }
        // 地形
        let tid = layer.terrain(at: at.point)
        let tdef = tid.flatMap { content.terrains[$0] }
        if let tags = def.placement.terrainTags {
            guard let t = tdef, !Set(t.tags).isDisjoint(with: tags) else {
                return Rejection(def.placement.reasonIfBlocked ?? ProductionText.terrain)
            }
        } else if isWater(at.point, layer: layer, content: content) || tdef?.passable == false {
            return Rejection(def.placement.reasonIfBlocked ?? ProductionText.terrain)
        }
        if def.placement.requiresDeposit == true {
            guard let d = layer.deposits.deposit(at: at.point) else {
                return Rejection(def.placement.reasonIfBlocked ?? ProductionText.needsDeposit)
            }
            if d.isDepleted { return Rejection(ProductionText.depositDepleted) }
        }
        if def.placement.requiresWaterAdjacent == true, !touchesWater(at.point, layer: layer, content: content) {
            return Rejection(def.placement.reasonIfBlocked ?? ProductionText.needsWater)
        }
        if payingCost {
            for ing in def.cost where available(ing, w) < ing.quantity {
                return Rejection(ProductionText.noMaterials, detail: ["item": .string(ing.item?.rawValue ?? "matter")])
            }
        }
        return nil
    }

    /// 札の i 段目を置けるか。
    public static func check(design: EntityID, stepIndex: Int, at: WorldPoint, facing: Direction,
                             world w: WorldState, content: ContentDB) -> Rejection? {
        guard let d = w.invention.designs[design] else { return Rejection(ProductionText.unknownDesign) }
        guard d.steps.indices.contains(stepIndex) else { return Rejection(ProductionText.noSuchStep) }
        return check(d.steps[stepIndex].module, at: at, facing: facing, world: w, content: content)
    }

    /// 次の段の影の場所(置いたモジュールの向きの方向の隣)。
    public static func nextGhost(after placement: EntityID, in w: WorldState) -> WorldPoint? {
        guard let p = w.placements.items[placement] else { return nil }
        return WorldPoint(p.at.layer, p.at.point.moved(p.facing))
    }

    static func isWater(_ p: GridPoint, layer: MapLayer, content: ContentDB) -> Bool {
        guard let t = layer.terrain(at: p) else { return false }
        return content.terrains[t]?.isWater ?? (layer.biome(at: p)?.isWet ?? false)
    }

    static func touchesWater(_ p: GridPoint, layer: MapLayer, content: ContentDB) -> Bool {
        p.neighbors8.contains { isWater($0, layer: layer, content: content) }
    }

    /// 材料を出せる在り処(拠点の蓄え → ノアの持ち物)。
    static let payHolders: [HolderID] = [.base, .person(.noah)]

    static func available(_ ing: Ingredient, _ w: WorldState) -> Int {
        payHolders.reduce(0) { acc, h in
            acc + w.inventory.entries(h).filter { $0.unique == nil && ing.matches($0) }.reduce(0) { $0 + $1.quantity }
        }
    }
}

/// 置く・動かす・片付ける・有限の品を使う。
enum Placing {
    static func placeFromDesign(_ design: EntityID, stepIndex: Int, at: WorldPoint, facing: Direction,
                                _ ctx: inout StepContext) -> CommandResult {
        guard let d = ctx.world.invention.designs[design] else { return .rejected(Rejection(ProductionText.unknownDesign)) }
        guard d.steps.indices.contains(stepIndex) else { return .rejected(Rejection(ProductionText.noSuchStep)) }
        let step = d.steps[stepIndex]
        return place(step.module, step: step, design: design, stepIndex: stepIndex, at: at, facing: facing, &ctx)
    }

    static func place(_ kind: ModuleKindID, step: ProcessStep?, design: EntityID?, stepIndex: Int?, at: WorldPoint,
                      facing: Direction, _ ctx: inout StepContext) -> CommandResult {
        if let r = PlacementCheck.check(kind, at: at, facing: facing, world: ctx.world, content: ctx.content) {
            return .rejected(r)
        }
        let def = ctx.content.modules[kind]!
        guard let paid = pay(def.cost, &ctx) else { return .rejected(Rejection(ProductionText.noMaterials)) }

        let id = ctx.world.newEntityID()
        var inputs: [ProvenanceID] = []
        if let design, let o = ctx.world.invention.designs[design]?.origin { inputs.append(o) }
        for e in paid { for o in e.origins.keys.sorted() where o != ProvenanceLedger.unknownOrigin && !inputs.contains(o) {
            inputs.append(o)
        } }
        var detail: [String: Value] = [:]
        if let design { detail["design"] = .int(Int64(design.raw)) }
        if let stepIndex { detail["step"] = .int(Int64(stepIndex)) }
        let rec = ctx.record(.placed, .module(kind, id), actor: .noah, place: at, inputs: inputs, detail: detail)

        var p = Placement(id: id, kind: .module(kind), at: at, facing: facing, origin: rec, status: .running)
        var m = ModuleRuntime(design: design, step: step ?? defaultStep(kind, ctx.content))
        m.stepIndex = stepIndex
        m.paid = paid
        configure(&m, def: def, at: at, facing: facing, ctx.world, ctx.content)
        p.module = m
        ctx.world.placements.items[id] = p
        ctx.world.placements.topologyVersion += 1
        attachAuras(def, placement: id, origin: rec, &ctx)
        ctx.changes.mark([.placements, .inventory])
        ctx.changes.markTile(at, .placements)
        ctx.emit(.placed(placement: id, record: rec))
        return .done
    }

    /// 工程の無い置き方(単体)のときの工程: 規則の表にあるモジュールなら入れる物なしの段。
    static func defaultStep(_ kind: ModuleKindID, _ content: ContentDB) -> ProcessStep? {
        content.ruleBook.modules[kind] != nil ? ProcessStep(kind) : nil
    }

    /// 定義と置き場所から、動きの値を写す(入出口の向き・受け取る物・水・溜められる数)。
    static func configure(_ m: inout ModuleRuntime, def: ModuleDef, at: WorldPoint, facing: Direction,
                          _ w: WorldState, _ content: ContentDB) {
        let ports = def.ports.isEmpty
            ? [PortDef(side: .south, flow: .input), PortDef(side: .north, flow: .output)] : def.ports
        m.ports = ModulePorts(
            inputs: ports.filter { $0.flow == .input }.map { ModulePorts.rotate($0.side, facing: facing) },
            outputs: ports.filter { $0.flow == .output }.map { ModulePorts.rotate($0.side, facing: facing) })
        let extracts = def.placement.requiresDeposit == true
        m.takesMatter = !extracts && def.produces == nil && content.ruleBook.modules[def.id] != nil
        var aux: [ItemID: Int] = [:]
        for lot in m.step?.inputs ?? [] { aux[lot.item, default: 0] += lot.quantity }
        for ing in def.consumes ?? [] { if let i = ing.item { aux[i, default: 0] += ing.quantity } }
        m.auxPerUnit = aux
        if let layer = w.map[at.layer], PlacementCheck.touchesWater(at.point, layer: layer, content: content) {
            m.freeItems = [.water]
        } else {
            m.freeItems = []
        }
        m.capacity = max(1, def.buffer ?? 12)
        m.batch = max(1, def.batch ?? 1)
        m.deposit = extracts ? w.map[at.layer]?.deposits.deposit(at: at.point)?.id : nil
    }

    static func attachAuras(_ def: ModuleDef, placement: EntityID, origin: ProvenanceID, _ ctx: inout StepContext) {
        for kind in def.auras ?? [] {
            let id = ctx.world.newEntityID()
            ctx.world.auras.active[id] = Aura(id: id, kind: kind, source: .placement(placement),
                                              radius: ProductionRules.defaultAuraRadius, origin: origin)
            ctx.changes.mark(.people)
        }
    }

    // MARK: 材料

    /// 費用を蓄え(足りなければノアの持ち物)から取る。取った山(来歴つき)を返す。足りなければ何もしない。
    static func pay(_ cost: [Ingredient], _ ctx: inout StepContext) -> [StockEntry]? {
        for ing in cost where PlacementCheck.available(ing, ctx.world) < ing.quantity { return nil }
        var paid: [StockEntry] = []
        for ing in cost {
            var left = ing.quantity
            for h in PlacementCheck.payHolders where left > 0 {
                for e in ctx.world.inventory.entries(h) where left > 0 && e.unique == nil && ing.matches(e) {
                    let k = min(left, e.quantity)
                    guard let origins = ctx.takeStock(k, from: h, where: { $0.unique == nil && $0.stuff == e.stuff })
                    else { continue }
                    left -= k
                    ModuleRuntime.put(StockEntry(stuff: e.stuff, quantity: k, origins: origins), into: &paid)
                }
            }
        }
        return paid
    }

    /// 物を拠点の蓄えへ返す(来歴ごと)。物質は並びの最後の規則で冷える(熱いまま蓄えには置かない)。
    static func toBase(_ e: StockEntry, cool: Bool, _ ctx: inout StepContext) {
        var stuff = e.stuff
        if cool, case .matter(let m) = stuff { stuff = .matter(ProcessChain.finish(m, rules: ctx.content.ruleBook).matter) }
        if e.unique != nil || e.durability != nil {
            var piece = e
            piece.stuff = stuff
            ctx.world.inventory.holders[.base, default: []].append(piece)
            ctx.changes.mark(.inventory)
            ctx.emit(.itemGained(holder: .base, stuff: stuff, quantity: e.quantity, record: e.origins.keys.max()))
            return
        }
        var rest = e.quantity
        for (o, n) in e.origins.sorted(by: { $0.key < $1.key }) where n > 0 && rest > 0 {
            let k = min(n, rest)
            ctx.addStock(stuff, k, to: .base, origin: o)
            rest -= k
        }
        if rest > 0 { ctx.addStock(stuff, rest, to: .base) }
    }

    // MARK: 動かす・片付ける

    static func move(_ id: EntityID, to: WorldPoint, facing: Direction, _ ctx: inout StepContext) -> CommandResult {
        guard let p = ctx.world.placements.items[id] else { return .rejected(Rejection(ProductionText.noSuchPlacement)) }
        guard let kind = p.moduleKind, var m = p.module, let def = ctx.content.modules[kind] else {
            return .rejected(Rejection(ProductionText.notAModule))
        }
        if let r = PlacementCheck.check(kind, at: to, facing: facing, excluding: id, payingCost: false,
                                        world: ctx.world, content: ctx.content) {
            return .rejected(r)
        }
        let from = p.at
        configure(&m, def: def, at: to, facing: facing, ctx.world, ctx.content)
        var q = p
        q.at = to
        q.facing = facing
        q.module = m
        ctx.world.placements.items[id] = q
        ctx.world.placements.topologyVersion += 1
        ctx.record(.moved, .module(kind, id), actor: .noah, place: to, inputs: [p.origin])
        ctx.changes.mark(.placements)
        ctx.changes.markTile(from, .placements)
        ctx.changes.markTile(to, .placements)
        return .done
    }

    static func dismantle(_ id: EntityID, _ ctx: inout StepContext) -> CommandResult {
        guard let p = ctx.world.placements.items[id] else { return .rejected(Rejection(ProductionText.noSuchPlacement)) }
        guard let kind = p.moduleKind, let m = p.module else { return .rejected(Rejection(ProductionText.notAModule)) }
        // 材料は全部戻る(払った物・入口と出口の待ち・使っていた有限の品)
        for e in m.paid { toBase(e, cool: false, &ctx) }
        for e in m.input { toBase(e, cool: true, &ctx) }
        for e in m.output { toBase(e, cool: true, &ctx) }
        if let f = m.finite { toBase(f, cool: false, &ctx) }
        ctx.world.placements.items[id] = nil
        ctx.world.placements.topologyVersion += 1
        ctx.world.auras.active = ctx.world.auras.active.filter { $0.value.source != .placement(id) }
        let rec = ctx.record(.dismantled, .module(kind, id), actor: .noah, place: p.at, inputs: [p.origin])
        ctx.changes.mark([.placements, .inventory, .people])
        ctx.changes.markTile(p.at, .placements)
        ctx.emit(.dismantled(placement: id, record: rec))
        return .done
    }

    /// 置いてある from のモジュールを全部 to に変える(U11 の効果 convertPlacements から。過去に置いた物も意味が変わる)。
    /// 置き場所・向き・来歴・払った材料・入口と出口の待ち・有限の品はそのまま。入出口・段の物・範囲の効果は to の定義で付け直す。
    /// to の置ける場所の規則(鉱脈の上など)は問わない。合わなければ止まった理由が出る。
    /// 来歴: 変わった 1 つごとに overridden(subject = 新しい種類、inputs = [引き金, 置いたときの来歴])。
    static func convert(from: ModuleKindID, to: ModuleKindID, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard let def = ctx.content.modules[to] else { return .rejected(Rejection(ProductionText.unknownModule)) }
        guard from != to else { return .done }
        let ids = ctx.world.placements.moduleIDs.filter { ctx.world.placements.items[$0]?.moduleKind == from }
        for id in ids {
            guard var p = ctx.world.placements.items[id], var m = p.module else { continue }
            configure(&m, def: def, at: p.at, facing: p.facing, ctx.world, ctx.content)
            m.progress = 0
            p.kind = .module(to)
            p.module = m
            ctx.world.placements.items[id] = p
            ctx.world.auras.active = ctx.world.auras.active.filter { $0.value.source != .placement(id) }
            attachAuras(def, placement: id, origin: p.origin, &ctx)
            ctx.record(.overridden, .module(to, id), place: p.at, inputs: [cause, p.origin].compactMap { $0 },
                       detail: ["from": .string(from.rawValue), "to": .string(to.rawValue)])
            ctx.changes.markTile(p.at, .placements)
        }
        if !ids.isEmpty {
            ctx.world.placements.topologyVersion += 1
            ctx.changes.mark([.placements, .people])
        }
        return .done
    }

    // MARK: 有限の品

    /// 有限の品をモジュールに使う。使うと速いが、減ったら戻らない(BEAT-08)。使ったことは来歴に残る。
    static func useFinite(_ id: EntityID, stock: StockSelector, _ ctx: inout StepContext) -> CommandResult {
        guard let p = ctx.world.placements.items[id] else { return .rejected(Rejection(ProductionText.noSuchPlacement)) }
        guard let kind = p.moduleKind, var m = p.module else { return .rejected(Rejection(ProductionText.notAModule)) }
        guard let fdef = ctx.content.modules[kind]?.finite, case .item(let item) = stock.stuff, fdef.items.contains(item)
        else { return .rejected(Rejection(ProductionText.finiteNotUsable)) }
        guard m.finite == nil else { return .rejected(Rejection(ProductionText.finiteAlreadyUsed)) }
        guard stock.holder == .base || stock.holder == .person(.noah) else {
            return .rejected(Rejection(ProductionText.finiteMissing))
        }
        var list = ctx.world.inventory.entries(stock.holder)
        guard let i = list.firstIndex(where: { $0.stuff == stock.stuff && $0.unique == stock.unique && $0.quantity > 0 })
        else { return .rejected(Rejection(ProductionText.finiteMissing)) }
        var piece = list[i]
        piece.quantity = 1
        if list[i].quantity > 1 {
            // 合わさった山から 1 つ(来歴は多い方から 1)
            list[i].quantity -= 1
            if let o = list[i].origins.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).first {
                piece.origins = [o.key: 1]
                list[i].origins[o.key] = o.value - 1 == 0 ? nil : o.value - 1
            }
        } else {
            list.remove(at: i)
        }
        ctx.world.inventory.holders[stock.holder] = list
        ctx.emit(.itemSpent(holder: stock.holder, stuff: stock.stuff, quantity: 1))
        piece.durability = piece.durability ?? ProductionRules.finiteFull

        let subject: SubjectRef = piece.unique.map { .entity($0) } ?? .item(item)
        let inputs = piece.origins.keys.sorted().filter { $0 != ProvenanceLedger.unknownOrigin } + [p.origin]
        let rec = ctx.record(.used, subject, actor: .noah, place: p.at, inputs: inputs,
                             detail: ["module": .string(kind.rawValue), "placement": .int(Int64(id.raw))])
        m.finite = piece
        m.finiteRecord = rec
        ctx.world.placements.items[id]?.module = m
        ctx.changes.mark([.placements, .inventory])
        ctx.emit(.finiteUsed(record: rec))
        return .done
    }

    /// 有限の品を使える置き物があるのに使わずに夜明けを迎えた品を「取っておいた」と 1 度だけ残す(選択の記録)。
    static func noteKeptFinites(_ ctx: inout StepContext) {
        var usable: [ItemID: [ModuleKindID]] = [:]
        for id in ctx.world.placements.moduleIDs {
            guard let p = ctx.world.placements.items[id], let k = p.moduleKind, p.module?.finite == nil,
                  let f = ctx.content.modules[k]?.finite else { continue }
            for i in f.items { usable[i, default: []].append(k) }
        }
        guard !usable.isEmpty else { return }
        for h in PlacementCheck.payHolders {
            for e in ctx.world.inventory.entries(h) {
                guard case .item(let i) = e.stuff, let kinds = usable[i] else { continue }
                let subject: SubjectRef = e.unique.map { .entity($0) } ?? .item(i)
                let already = ctx.world.ledger.records.contains {
                    ($0.act == .kept || $0.act == .used) && $0.subject == subject
                }
                guard !already else { continue }
                let inputs = e.origins.keys.sorted().filter { $0 != ProvenanceLedger.unknownOrigin }
                ctx.record(.kept, subject, actor: .noah, inputs: inputs,
                           detail: ["module": .string(kinds.sorted().first!.rawValue)])
            }
        }
    }
}
