import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 視界と地図の既知(knowledge.mapKnown)。地図の上にいる一員は誰でも同じ規則で見る(ノアだけを特別にしない)。
/// 半径は RFMap の VisionRule(昼 8・夜 −3・灯り +4・最小 2。原作 VisibilityLayer.cs:21-27)。
/// 灯り: 灯りを出す建造物(StructureDef.provides["light"] = 半径)の範囲の中にいれば +4。
public enum Vision {
    static let rule = VisionRule.original

    static func radius(of id: PersonID, in w: WorldState, content: ContentDB) -> Int {
        guard let pos = w.people[id]?.position else { return 0 }
        let night = w.clock.phase != .day
        return rule.radius(isNight: night, hasTorch: night && isLit(pos, w, content))
    }

    static func isLit(_ pos: WorldPoint, _ w: WorldState, _ content: ContentDB) -> Bool {
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id], p.at.layer == pos.layer, case .structure(let k) = p.kind else { continue }
            if case .underConstruction = p.status { continue }
            guard let r = content.structures[k]?.provides["light"], r > 0 else { continue }
            if VisionRule.inCircle(pos.point, center: p.at.point, radius: r) { return true }
        }
        return false
    }

    /// いま見えているマス(保存しない。画面の明暗と、敵が見えるかの判定に使う)。
    public static func visibleNow(_ w: WorldState, content: ContentDB, layer: LayerID) -> Set<GridPoint> {
        guard let l = w.map[layer] else { return [] }
        var out = Set<GridPoint>()
        for id in w.people.membersOnMap {
            guard let pos = w.people[id]?.position, pos.layer == layer else { continue }
            out.formUnion(VisionRule.cells(center: pos.point, radius: radius(of: id, in: w, content: content), in: l.size))
        }
        return out
    }

    /// 一員の視界で既知を増やす。新しく知ったマスは画面の描き直しの印を付け、見つけた POI は発見にする。
    static func update(_ ctx: inout StepContext) {
        var revealed: [LayerID: Int] = [:]
        for id in ctx.world.people.membersOnMap {
            guard let pos = ctx.world.people[id]?.position, let l = ctx.world.map[pos.layer] else { continue }
            let r = radius(of: id, in: ctx.world, content: ctx.content)
            var known = ctx.world.knowledge.mapKnown[pos.layer] ?? GridBitset(size: l.size)
            if known.size != l.size { known = GridBitset(size: l.size) }
            var personal = ctx.world.people[id]?.personalKnown?[pos.layer]
            var fresh: [GridPoint] = []
            for p in VisionRule.cells(center: pos.point, radius: r, in: l.size) {
                if personal != nil, personal?[p] == false { personal?[p] = true }
                guard !known[p] else { continue }
                known[p] = true
                fresh.append(p)
            }
            if let personal { ctx.world.people[id]?.personalKnown?[pos.layer] = personal }
            guard !fresh.isEmpty else { continue }
            ctx.world.knowledge.mapKnown[pos.layer] = known
            revealed[pos.layer, default: 0] += fresh.count
            for p in fresh { ctx.changes.markTile(WorldPoint(pos.layer, p), .fog) }
            discover(fresh, layer: pos.layer, by: id, &ctx)
        }
        for (layer, n) in revealed.sorted(by: { $0.key < $1.key }) {
            ctx.emit(.tilesRevealed(layer: layer, count: n))
        }
    }

    /// 新しく見たマスにある POI(残骸・遺跡・巣…)を発見にする。
    static func discover(_ cells: [GridPoint], layer: LayerID, by id: PersonID, _ ctx: inout StepContext) {
        guard let l = ctx.world.map[layer] else { return }
        var found: [(EntityID, POIKindID, GridPoint)] = []
        var seen = Set<EntityID>()
        for p in cells {
            guard let mp = l.placements.placement(at: p), let e = mp.entity, mp.kind != .module,
                  !ctx.world.knowledge.discovered.contains(e), !seen.contains(e) else { continue }
            seen.insert(e)
            found.append((e, POIKindID(mp.templateID), mp.anchor))
        }
        for (e, kind, at) in found.sorted(by: { $0.0 < $1.0 }) {
            ctx.world.knowledge.discovered.insert(e)
            let rec = ctx.record(.discovered, .poi(kind, e), actor: id, place: WorldPoint(layer, at))
            ctx.emit(.discovered(entity: e, record: rec))
        }
    }
}
