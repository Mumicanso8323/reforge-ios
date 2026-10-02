import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 建造物を置く・建てる・片付ける。
enum Construction {
    /// 建てる人の手の届く距離(マス。チェビシェフ)。
    static let reach = 1
    /// 専門が合う人の速さ(千分率)。モジュールに付くときと同じ +30%(order.md §5.6)。
    static let specialtyBonus = 300
    /// 建造の作業の単位: ゲーム秒 × 千分率。
    static let workKey = "work"

    // MARK: 置く

    static func build(_ kind: StructureKindID, at: WorldPoint, facing: Direction, _ ctx: inout StepContext) -> CommandResult {
        let w = ctx.world
        guard let def = ctx.content.structures[kind] else { return .rejected(Rejection("reason.base.unknown")) }
        guard w.research.unlocked.structures.contains(kind) else { return .rejected(Rejection("reason.base.locked")) }
        let footprint = rotate(def.footprint ?? [GridPoint(0, 0)], facing)
        if let r = checkSite(def, at: at, footprint: footprint, ctx) { return .rejected(r) }
        // 費用(全部そろっていなければ何も取らない)
        for ing in def.cost where have(ing, w) < ing.quantity {
            return .rejected(Rejection("reason.base.missing_cost"))
        }
        var lots: [CostLot] = []
        for ing in def.cost {
            var left = ing.quantity
            for e in ctx.world.inventory.entries(.base) where left > 0 && ing.matches(e) && e.unique == nil {
                let k = min(left, e.quantity)
                if let took = ctx.takeStock(k, from: .base, where: { $0.stuff == e.stuff && $0.unique == nil }) {
                    lots.append(CostLot(stuff: e.stuff, origins: took))
                    left -= k
                }
            }
        }
        let id = ctx.world.newEntityID()
        ctx.world.base.spent[id] = lots
        let inputs = Set(lots.flatMap { $0.origins.keys }).filter { $0 != ProvenanceLedger.unknownOrigin }.sorted()
        let origin = ctx.record(.placed, .structure(kind, id), actor: .noah, place: at, inputs: inputs,
                                detail: ["facing": .string(facing.rawValue)])
        var p = Placement(id: id, kind: .structure(kind), at: at, facing: facing, footprint: footprint, origin: origin,
                          status: def.buildSeconds > 0 ? .underConstruction(progress: 0) : .running)
        var rt = StructureRuntime()
        rt.parameters[workKey] = 0
        p.structure = rt
        ctx.world.placements.items[id] = p
        ctx.emit(.placed(placement: id, record: origin))
        markCells(p, &ctx)
        if def.buildSeconds <= 0 { complete(id, &ctx) }
        return .done
    }

    static func have(_ ing: Ingredient, _ w: WorldState) -> Int {
        w.inventory.entries(.base).filter { ing.matches($0) && $0.unique == nil }.reduce(0) { $0 + $1.quantity }
    }

    /// 置ける場所か(拠点の範囲・地形・重なり)。
    static func checkSite(_ def: StructureDef, at: WorldPoint, footprint: [GridPoint], _ ctx: StepContext) -> Rejection? {
        StructureSites.check(def, at: at, footprint: footprint, ctx)
    }

    /// 向きで足跡を回す(north = 定義のまま、時計回りに east・south・west)。
    static func rotate(_ fp: [GridPoint], _ d: Direction) -> [GridPoint] {
        fp.map { o in
            switch d {
            case .north: o
            case .east: GridPoint(-o.y, o.x)
            case .south: GridPoint(-o.x, -o.y)
            case .west: GridPoint(o.y, -o.x)
            }
        }
    }

    // MARK: 建てる

    /// 建造中の物を 1 ステップ進める。1 人は 1 か所だけを手伝う(ID の小さい方)。
    static func advance(_ ctx: inout StepContext) {
        let w = ctx.world
        let sites = w.placements.sortedIDs.filter { id in
            guard let p = w.placements.items[id], case .structure = p.kind, case .underConstruction = p.status else { return false }
            return true
        }
        guard !sites.isEmpty else { return }
        let fireTag = ctx.content.base.constructionFireTag
        let hasFire = fireTag.map { BaseRules.total($0, w, ctx.content) > 0 } ?? true
        var work: [EntityID: Int64] = [:]
        for pid in w.people.members {
            guard let ps = w.people[pid], ps.motion == nil, let pos = ps.position else { continue }
            let assigned = ps.override?.assignment ?? ps.assignment
            for id in sites {
                guard let p = w.placements.items[id], case .structure(let kind) = p.kind, near(pos, p) else { continue }
                let helping: Bool
                if case .build(let target) = assigned, target == id {
                    helping = true
                } else if pid == .noah, w.exploration.active[pid] == nil, assigned == .idle {
                    helping = true
                } else {
                    helping = false
                }
                guard helping else { continue }
                // 拠点の範囲の建設は、火が燃えている間だけ進む(W-02c)
                if !hasFire, let tag = fireTag, let sd = ctx.content.structures[kind], sd.requiresBaseArea != false,
                   sd.provides[tag] == nil { continue }
                // 距離の縛り(PersonDef.tether。U16): 縛る人から遠い間は手伝えない
                if let t = ctx.content.people[pid]?.tether {
                    guard let other = ctx.world.people[t.person]?.position, other.layer == pos.layer,
                          other.point.chebyshev(to: pos.point) <= t.radius else { continue }
                }
                var rate = 1000
                if let sp = ctx.content.structures[kind]?.specialty,
                   ctx.content.people[pid]?.specialties.contains(sp) == true {
                    rate += specialtyBonus
                }
                rate = rate * speedModifier(at: pos, ctx) / 1000
                work[id, default: 0] += SimStep.gameSeconds * Int64(rate)
                break
            }
        }
        for (id, add) in work.sorted(by: { $0.key < $1.key }) where add > 0 {
            guard var p = ctx.world.placements.items[id], case .structure(let kind) = p.kind,
                  let def = ctx.content.structures[kind] else { continue }
            var rt = p.structure ?? StructureRuntime()
            let done = Int64(rt.parameters[workKey] ?? 0) + add
            rt.parameters[workKey] = Int(done)
            p.structure = rt
            let need = Int64(max(1, def.buildSeconds)) * 1000
            p.status = .underConstruction(progress: Int(min(999, done * 1000 / need)))
            ctx.world.placements.items[id] = p
            ctx.changes.mark(.placements)
            if done >= need { complete(id, &ctx) }
        }
    }

    static func near(_ pos: WorldPoint, _ p: Placement) -> Bool {
        pos.layer == p.at.layer && p.footprint.contains { (p.at.point + $0).chebyshev(to: pos.point) <= reach }
    }

    static func speedModifier(at pos: WorldPoint, _ ctx: StepContext) -> Int {
        var speed = 1000
        for (m, strength, _) in Auras.modifiers(at: pos, in: ctx.world, content: ctx.content) {
            if case .workSpeed(let p) = m { speed = speed * (1000 + (p - 1000) * strength / 1000) / 1000 }
        }
        return max(0, speed)
    }

    static func complete(_ id: EntityID, _ ctx: inout StepContext) {
        guard var p = ctx.world.placements.items[id], case .structure(let kind) = p.kind else { return }
        p.status = .running
        ctx.world.placements.items[id] = p
        let rec = ctx.record(.built, .structure(kind, id), place: p.at, inputs: [p.origin])
        ctx.emit(.built(placement: id, record: rec))
        markCells(p, &ctx)
    }

    // MARK: 片付ける

    static func demolish(_ id: EntityID, _ ctx: inout StepContext) -> CommandResult {
        guard let p = ctx.world.placements.items[id] else { return .rejected(Rejection("reason.base.unknown")) }
        // モジュールの片付けは RFProduction(ProductionCommand.dismantle)
        guard case .structure(let kind) = p.kind else { return .rejected(Rejection("reason.base.not_structure")) }
        let rec = ctx.record(.demolished, .structure(kind, id), actor: .noah, place: p.at, inputs: [p.origin])
        ctx.world.placements.items[id] = nil
        // 費用は全部、使った物と同じ物・同じ来歴で戻す
        for lot in ctx.world.base.spent.removeValue(forKey: id) ?? [] {
            for (o, n) in lot.origins.sorted(by: { $0.key < $1.key }) { ctx.addStock(lot.stuff, n, to: .base, origin: o) }
        }
        ctx.emit(.dismantled(placement: id, record: rec))
        markCells(p, &ctx)
        return .done
    }

    static func markCells(_ p: Placement, _ ctx: inout StepContext) {
        ctx.changes.mark(.placements)
        for off in p.footprint { ctx.changes.markTile(WorldPoint(p.at.layer, p.at.point + off), .placements) }
    }

    /// 壊れた建造物を直す(U16)。建てるときと同じ材料を払う(足りなければ何も取らない)。払った物は spent に足す。
    static func repair(_ id: EntityID, _ ctx: inout StepContext) -> CommandResult {
        guard let p = ctx.world.placements.items[id], case .structure(let kind) = p.kind,
              let def = ctx.content.structures[kind] else { return .rejected(Rejection("reason.base.unknown")) }
        guard p.status == .broken else { return .rejected(Rejection("reason.placement.not_broken")) }
        for ing in def.cost where have(ing, ctx.world) < ing.quantity { return .rejected(Rejection("reason.base.missing_cost")) }
        var lots: [CostLot] = []
        for ing in def.cost {
            var left = ing.quantity
            for e in ctx.world.inventory.entries(.base) where left > 0 && ing.matches(e) && e.unique == nil {
                let k = min(left, e.quantity)
                if let took = ctx.takeStock(k, from: .base, where: { $0.stuff == e.stuff && $0.unique == nil }) {
                    lots.append(CostLot(stuff: e.stuff, origins: took))
                    left -= k
                }
            }
        }
        ctx.world.base.spent[id, default: []] += lots
        Destruction.repair(id, paidOrigins: Set(lots.flatMap { $0.origins.keys }).sorted(), &ctx)
        ctx.changes.mark(.inventory)
        return .done
    }
}

/// 画面向けの問い合わせ(置くモードの照準)。世界を変えない。
public enum BaseQueries {
    /// 建造物をそこに置けるか。置けなければ理由(費用の不足は含めない: 照準は場所だけを見る)。
    public static func siteRejection(_ kind: StructureKindID, at: WorldPoint, facing: Direction, world: WorldState,
                                     content: ContentDB) -> Rejection? {
        guard let def = content.structures[kind] else { return Rejection("reason.base.unknown") }
        let ctx = StepContext(world: world, content: content)
        return Construction.checkSite(def, at: at, footprint: footprint(kind, facing: facing, content: content), ctx)
    }

    /// 向きで回した足跡(置く点からのずれ)。
    public static func footprint(_ kind: StructureKindID, facing: Direction, content: ContentDB) -> [GridPoint] {
        Construction.rotate(content.structures[kind]?.footprint ?? [GridPoint(0, 0)], facing)
    }
}
