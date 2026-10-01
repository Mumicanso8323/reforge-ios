import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 効果から来る地図と部品の変化(revealMap・setTerrain・setPart)。cause は引き金の来歴で、自分の来歴の inputs に入れる。
enum MapEffects {
    /// 周りのマスを既知にする(地図を見つけた・高い所から見渡した…)。
    static func reveal(around c: WorldPoint, radius: Int, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard let layer = ctx.world.map[c.layer] else { return .rejected(Rejection("reason.explore.no_target")) }
        var known = ctx.world.knowledge.mapKnown[c.layer] ?? GridBitset(size: layer.size)
        var added = 0
        for p in VisionRule.cells(center: c.point, radius: max(0, radius), in: layer.size) where !known[p] {
            known[p] = true
            added += 1
            ctx.changes.markTile(WorldPoint(c.layer, p), .fog)
        }
        ctx.world.knowledge.mapKnown[c.layer] = known
        ctx.record(.observed, .none, place: c, inputs: cause.map { [$0] } ?? [],
                   detail: ["radius": .int(Int64(radius)), "tiles": .int(Int64(added))])
        if added > 0 { ctx.emit(.tilesRevealed(layer: c.layer, count: added)) }
        return .done
    }

    /// 地形を変える(崩落・水が引く…)。地図の知らない地形は変えない(警告)。
    static func setTerrain(at p: WorldPoint, terrain t: TerrainID, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard Biome(terrainID: t) != nil, let layer = ctx.world.map[p.layer], layer.size.contains(p.point) else {
            ctx.warnings.append("地形を変えられない: \(t) at \(p)")
            return .rejected(Rejection("reason.explore.no_target"))
        }
        let before = layer.terrain(at: p.point)
        ctx.world.map[p.layer]?.setTerrain(t, at: p.point)
        ctx.record(.overridden, .none, place: p, inputs: cause.map { [$0] } ?? [],
                   detail: ["terrain": .string(t.rawValue), "before": .string(before?.rawValue ?? "")])
        ctx.changes.markTile(p)
        return .done
    }

    /// 有限の部品の状態を変える(来歴は効果の側で作ってある)。
    static func setPart(poi: EntityID, part: String, state: PartState, _ ctx: inout StepContext) -> CommandResult {
        var prog = ctx.world.exploration.poi[poi] ?? POIProgress()
        prog.parts[part] = state
        ctx.world.exploration.poi[poi] = prog
        if let rec = state.record { ctx.emit(.partChanged(poi: poi, part: part, record: rec)) }
        for layer in ctx.world.map.layerIDs {
            if let at = ctx.world.map[layer]?.pois[poi]?.at { ctx.changes.markTile(WorldPoint(layer, at)) }
        }
        return .done
    }
}
