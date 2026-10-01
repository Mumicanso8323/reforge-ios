import RFContent
import RFKernel
import RFWorld

/// 置いた物を壊す・直す(U16。D02・G03・爆発でラインが壊れる場面)。RFProduction(モジュール)と RFBase(建造物)が
/// 自分の側の置いた物について呼ぶ。
///
/// - 壊れた物は地図に残り、status = broken で止まる(範囲の効果も出さない)。入口と出口の待ちは失われる。
///   払った材料は残るので、片付ければ戻る(作った物そのものは残骸として残っている扱い)。
/// - 来歴: destroyed(subject = その置いた物、inputs = [引き金, 置いたときの来歴])。Placement.destroyedBy に持つ。
/// - 直す: 置くときと同じ材料をもう一度払い、running に戻す。来歴 repaired(inputs = [壊した記録, 置いたときの来歴, 材料])。
public enum Destruction {
    /// near から radius 以内の、filter に合う置いた物(壊れていない・建造中でない)を近い順(同じなら ID 順)に max 個。
    public static func targets(near: WorldPoint, radius: Int, max: Int?, in w: WorldState,
                               where filter: (Placement) -> Bool) -> [EntityID] {
        let hits: [(Int, EntityID)] = w.placements.sortedIDs.compactMap { id in
            guard let p = w.placements.items[id], p.at.layer == near.layer, filter(p) else { return nil }
            if p.status == .broken { return nil }
            if case .underConstruction = p.status { return nil }
            let d = p.footprint.map { (p.at.point + $0).chebyshev(to: near.point) }.min() ?? Int.max
            return d <= radius ? (d, id) : nil
        }
        let sorted = hits.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.1)
        return max.map { Array(sorted.prefix(Swift.max(0, $0))) } ?? sorted
    }

    /// 1 つ壊す(持ち主のシステムが呼ぶ)。
    @discardableResult
    public static func destroy(_ id: EntityID, cause: ProvenanceID?, _ ctx: inout StepContext) -> ProvenanceID? {
        guard var p = ctx.world.placements.items[id] else { return nil }
        let subject: SubjectRef
        switch p.kind {
        case .module(let k): subject = .module(k, id)
        case .structure(let k): subject = .structure(k, id)
        }
        let rec = ctx.record(.destroyed, subject, place: p.at, inputs: [cause, p.origin].compactMap { $0 })
        p.status = .broken
        p.destroyedBy = rec
        if var m = p.module {
            m.input = []
            m.output = []
            m.progress = 0
            m.operatorID = nil
            p.module = m
        }
        ctx.world.placements.items[id] = p
        ctx.world.placements.topologyVersion += 1
        ctx.world.auras.active = ctx.world.auras.active.filter { $0.value.source != .placement(id) }
        ctx.changes.mark([.placements, .people])
        ctx.changes.markTile(p.at, .placements)
        ctx.emit(.placementDestroyed(placement: id, record: rec))
        return rec
    }

    /// 直す(材料 paid は持ち主のシステムが払ったもの)。壊れていなければ nil。
    @discardableResult
    public static func repair(_ id: EntityID, paidOrigins: [ProvenanceID], _ ctx: inout StepContext) -> ProvenanceID? {
        guard var p = ctx.world.placements.items[id], p.status == .broken else { return nil }
        let subject: SubjectRef
        switch p.kind {
        case .module(let k): subject = .module(k, id)
        case .structure(let k): subject = .structure(k, id)
        }
        let inputs = [p.destroyedBy, p.origin].compactMap { $0 } + paidOrigins.filter { $0 != ProvenanceLedger.unknownOrigin }
        let rec = ctx.record(.repaired, subject, actor: .noah, place: p.at, inputs: inputs)
        p.status = .running
        p.destroyedBy = nil
        ctx.world.placements.items[id] = p
        ctx.world.placements.topologyVersion += 1
        ctx.changes.mark(.placements)
        ctx.changes.markTile(p.at, .placements)
        ctx.emit(.placementRepaired(placement: id, record: rec))
        return rec
    }
}
