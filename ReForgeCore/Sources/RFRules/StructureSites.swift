import RFContent
import RFKernel
import RFMap
import RFWorld

/// 建造物を置ける場所か(拠点の範囲・地形・重なり)。建てるコマンド(RFBase)と、効果 placeStructure が同じ規則を使う。
public enum StructureSites {
    /// 置けなければ理由を返す。ignoreBaseArea: 拠点の範囲を見ない(効果で置くとき)。
    public static func check(_ def: StructureDef, at: WorldPoint, footprint: [GridPoint], _ ctx: StepContext,
                             ignoreBaseArea: Bool = false) -> Rejection? {
        let w = ctx.world
        guard let layer = w.map[at.layer] else { return Rejection("reason.base.blocked") }
        for off in footprint {
            let c = at.point + off
            let cell = WorldPoint(at.layer, c)
            guard layer.size.contains(c), let t = layer.terrain(at: c) else { return Rejection("reason.base.blocked") }
            if !ignoreBaseArea, def.requiresBaseArea ?? true {
                guard at.layer == .surface, w.base.area?.contains(c) == true else { return Rejection("reason.base.outside") }
            }
            let tdef = ctx.content.terrains[t]
            if tdef?.passable == false || tdef?.isWater == true || Biome(terrainID: t)?.isWet == true {
                return Rejection("reason.base.blocked")
            }
            if let rule = def.placement {
                if let tags = rule.terrainTags, !tags.contains(where: { (tdef?.tags ?? [t.rawValue]).contains($0) }) {
                    return rule.reasonIfBlocked.map { Rejection($0) } ?? Rejection("reason.base.terrain")
                }
                if rule.requiresWaterAdjacent == true, !layer.touchesWater(c) {
                    return rule.reasonIfBlocked.map { Rejection($0) } ?? Rejection("reason.base.terrain")
                }
            }
            if !w.placements.at(cell).isEmpty || layer.placements.isOccupied(c) { return Rejection("reason.base.occupied") }
        }
        return nil
    }


    /// 向きで足跡を回す(north = 定義のまま、時計回りに east・south・west)。
    public static func rotate(_ fp: [GridPoint], _ d: Direction) -> [GridPoint] {
        fp.map { o in
            switch d {
            case .north: o
            case .east: GridPoint(-o.y, o.x)
            case .south: GridPoint(-o.x, -o.y)
            case .west: GridPoint(o.y, -o.x)
            }
        }
    }

    /// near のそばで置ける最初のマス(決定的: 距離 0 から 3 まで、同じ距離なら y → x の順)。
    public static func spot(_ def: StructureDef, near: WorldPoint, _ ctx: StepContext) -> Result<WorldPoint, Rejection> {
        let fp = rotate(def.footprint ?? [GridPoint(0, 0)], .north)
        for r in 0...3 {
            for dy in -r...r {
                for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    let at = WorldPoint(near.layer, GridPoint(near.point.x + dx, near.point.y + dy))
                    if check(def, at: at, footprint: fp, ctx, ignoreBaseArea: true) == nil { return .success(at) }
                }
            }
        }
        return .failure(Rejection("reason.base.no_site"))
    }

    /// 効果から建造物を置く(費用は取らない・解禁を見ない)。built なら建ち終えた状態で置く。置いた実体を返す。
    @discardableResult
    public static func placeFromEffect(_ kind: StructureKindID, near: WorldPoint, built: Bool,
                                       _ ctx: inout StepContext) -> Result<EntityID, Rejection> {
        guard let def = ctx.content.structures[kind] else { return .failure(Rejection("reason.base.unknown")) }
        let at: WorldPoint
        switch spot(def, near: near, ctx) {
        case .success(let p): at = p
        case .failure(let r): return .failure(r)
        }
        let id = ctx.world.newEntityID()
        let origin = ctx.record(.placed, .structure(kind, id), place: at, inputs: ctx.cause.map { [$0] } ?? [])
        let fp = rotate(def.footprint ?? [GridPoint(0, 0)], .north)
        var p = Placement(id: id, kind: .structure(kind), at: at, facing: .north, footprint: fp, origin: origin,
                          status: built || def.buildSeconds <= 0 ? .running : .underConstruction(progress: 0))
        var rt = StructureRuntime()
        rt.parameters["work"] = 0
        p.structure = rt
        ctx.world.placements.items[id] = p
        ctx.emit(.placed(placement: id, record: origin))
        if p.status == .running {
            let rec = ctx.record(.built, .structure(kind, id), place: at, inputs: [origin])
            ctx.emit(.built(placement: id, record: rec))
        }
        ctx.changes.mark(.placements)
        for off in fp { ctx.changes.markTile(WorldPoint(at.layer, at.point + off), .placements) }
        return .success(id)
    }
}
