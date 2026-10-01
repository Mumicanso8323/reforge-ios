import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 居場所(PersonDef.home。U16)。まだ会っていない人を、その種類の POI に置いておく。
/// プレイヤーがそこへ歩いて行くと、条件 at・hook "entered" の出来事が起きる(砦のキーパーソンに会いに行く)。
/// 確かめるのは 1 時間ごと(と最初のステップ)だけ。位置のある人・会った人は動かさない。
enum Residence {
    static func placeIfDue(_ ctx: inout StepContext) {
        let t = ctx.world.clock.now.seconds
        guard t % 3600 == 0 || t <= SimStep.gameSeconds else { return }
        place(&ctx)
    }

    static func place(_ ctx: inout StepContext) {
        for id in ctx.world.people.order {
            guard let ps = ctx.world.people[id], ps.presence == .unmet, ps.position == nil,
                  let kind = ctx.content.people[id]?.home, let at = firstPOI(kind, ctx.world) else { continue }
            ctx.world.people[id]?.position = at
            ctx.changes.mark(.people)
        }
    }

    /// その種類の POI のうち、層・EntityID の昇順で最初のものの位置(足場の先頭のマス)。
    static func firstPOI(_ kind: POIKindID, _ w: WorldState) -> WorldPoint? {
        for (lid, layer) in w.map.layers.sorted(by: { $0.key < $1.key }) {
            if let (_, poi) = layer.pois.sorted(by: { $0.key < $1.key }).first(where: { $0.value.kind == kind }) {
                return WorldPoint(lid, poi.at)
            }
        }
        return nil
    }
}
