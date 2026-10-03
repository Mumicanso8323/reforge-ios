import RFContent
import RFKernel
import RFRules
import RFWorld

/// 探索(CORE-06)。マス・POI・置いた物に対する行為(InteractionDef: 漁る・汲む・掘る・解体する・直す)、
/// 押し続ける行為、回数の上限とクールダウン、得られる物、有限の部品(残骸の区画)の取り外し・解体・作り直し・修理、
/// 歩いて新しい区画や POI に入ったときの探索の出来事の表(ExploreEventDef)、探索範囲。
///
/// 書いてよい切れ端: exploration・map(地形の変化と POI の残りの回数・鉱脈の残り)。乱数の流れ: .exploration。
/// 受けるコマンド: .exploration(...)。
public struct ExplorationSystem: SimSystem {
    public let name = "exploration"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .exploration(let c) = command else { return .notMine }
        switch c {
        case .interact(let id, let at, let holding, let person):
            if person == nil || person == .noah {
                ctx.world.people[.noah]?.steer = nil
                ctx.world.people[.noah]?.steerBlocked = nil
            }
            return Interactions.command(id, at: at, holding: holding, actor: person ?? .noah, &ctx)
        case .revealMap(let around, let radius, let cause):
            return MapEffects.reveal(around: around, radius: radius, cause: cause, &ctx)
        case .setTerrain(let at, let terrain, let cause):
            return MapEffects.setTerrain(at: at, terrain: terrain, cause: cause, &ctx)
        case .setPart(let poi, let part, let state):
            return MapEffects.setPart(poi: poi, part: part, state: state, &ctx)
        case .setBeacon(let id, let at, _):
            let old = ctx.world.exploration.beacons[id]
            guard old != at else { return .done }
            ctx.world.exploration.beacons[id] = at
            for p in [old, at].compactMap({ $0 }) { ctx.changes.markTile(p, .fog) }
            return .done
        case .inspected(let t, let poi):
            let subjects = [t.map(Subject.terrain), poi.map(Subject.poi)].compactMap { $0 }
            let before = ctx.world.knowledge.inspected.count
            ctx.world.knowledge.inspected.formUnion(subjects)
            if ctx.world.knowledge.inspected.count != before { ctx.changes.mark(.narrative) }
            return .done
        }
    }

    public func step(_ ctx: inout StepContext) {
        Interactions.startAssignedGathering(&ctx)
        Interactions.advance(&ctx)
        Wandering.track(&ctx)
    }
}
