import RFContent
import RFKernel
import RFRules
import RFWorld

/// 捨て場は副産物を消すだけで、在庫や保存の形を増やさない。
public enum Dumps {
    private static let held = "dump.held"

    /// モジュールの足に辺で接する、使える捨て場を実体 ID 順で返す。
    public static func adjacent(of id: EntityID, in w: WorldState, content: ContentDB) -> [EntityID] {
        guard let module = w.placements.items[id] else { return [] }
        return w.placements.sortedIDs.filter { candidate in
            guard let dump = w.placements.items[candidate], dump.at.layer == module.at.layer,
                  dump.status != .broken, case .structure(let kind) = dump.kind,
                  (content.structures[kind]?.provides["dump"] ?? 0) > 0 else { return false }
            if case .underConstruction = dump.status { return false }
            return module.footprint.contains { moduleOffset in
                let modulePoint = module.at.point + moduleOffset
                return dump.footprint.contains { dumpOffset in
                    modulePoint.manhattan(to: dump.at.point + dumpOffset) == 1
                }
            }
        }
    }

    /// 出口の副産物を隣の捨て場の空きに移し、捨てた数を返す。
    @discardableResult
    public static func accept(from id: EntityID, _ ctx: inout StepContext) -> Int {
        guard let module = ctx.world.placements.items[id]?.module else { return 0 }
        let waste = Set(ctx.content.byproductItems.values)
        guard !waste.isEmpty, module.output.contains(where: { entry in
            if case .item(let item) = entry.stuff { return waste.contains(item) }
            return false
        }) else { return 0 }

        var moved = 0
        for dumpID in adjacent(of: id, in: ctx.world, content: ctx.content) {
            guard let dump = ctx.world.placements.items[dumpID], case .structure(let kind) = dump.kind else { continue }
            let capacity = max(0, ctx.content.structures[kind]?.provides["dump"] ?? 0)
            let heldNow = dump.structure?.parameters[held] ?? 0
            let room = max(0, capacity - heldNow)
            guard room > 0 else { continue }
            let pieces = ModuleRuntime.take(room, from: &ctx.world.placements.items[id]!.module!.output) { entry in
                if case .item(let item) = entry.stuff { return waste.contains(item) }
                return false
            }
            let count = pieces.reduce(0) { $0 + $1.quantity }
            guard count > 0 else { continue }
            ctx.world.placements.items[dumpID]?.structure?.parameters[held, default: 0] += count
            ctx.world.placements.items[id]?.module?.today.sent += count
            moved += count
        }
        if moved > 0 { ctx.changes.mark(.placements) }
        return moved
    }
}
