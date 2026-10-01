import RFContent
import RFKernel
import RFRules
import RFSave
import RFWorld

/// 失って続ける(D-save.md §3)。失敗した世界から、仲間や物を失ってその場から続ける。死んだ仲間は戻らない
/// (失敗した世界をそのまま続けるので、生死は何も戻さない)。
///
/// 失うもの: コンテンツの `RewindDef.lossEffects` があればそれだけ。無ければ既定の規則
/// (`lossMembers` 人が拠点を去る(既定 1。関係の点が最も低い人から。ノアは去らない)・拠点の蓄えを
/// `lossItemPermille`(既定 500)失う。唯一品は失わない)。
/// 原因を解く: 成り立っていた失敗の規則の `onContinue` の効果。
/// 適用してもまだ失敗の規則が成り立つなら nil(選べない。すぐ同じ失敗に戻らないように)。
public enum LossCarry {
    public static let defaultMembers = 1
    public static let defaultItemPermille = 500

    public static func continueWithLoss(failed: WorldState, content: ContentDB)
        -> (world: WorldState, warnings: [String])?
    {
        guard case .failed(let cause, let failRecord) = failed.run.outcome else { return nil }
        let holding = FailureSystem.holdingRules(world: failed, content: content)
        var ctx = StepContext(world: failed, content: content)
        ctx.world.run.outcome = .ongoing
        let rec = ctx.record(.continuedWithLoss, .none, inputs: failRecord.map { [$0] } ?? [],
                             detail: ["cause": .string(cause.rawValue)])

        if let effects = content.rewind.lossEffects {
            EffectApplier.apply(effects, &ctx, cause: rec)
        } else {
            for p in leavers(ctx.world, count: content.rewind.lossMembers ?? defaultMembers) {
                depart(p, &ctx, cause: rec)
            }
            loseStock(permille: content.rewind.lossItemPermille ?? defaultItemPermille, &ctx, cause: rec)
        }
        for id in holding {
            if let fx = content.failureRules[id]?.onContinue { EffectApplier.apply(fx, &ctx, cause: rec) }
        }
        guard FailureSystem.holdingRules(world: ctx.world, content: content).isEmpty else { return nil }
        ctx.world.run.losses += 1
        ctx.world.run.resumeNotice = rec
        _ = ctx.drainEvents()
        return (ctx.world, ctx.warnings)
    }

    /// 去る人: ノア以外の一員を、関係の点の低い順(同じなら後から加わった順)に。
    static func leavers(_ w: WorldState, count: Int) -> [PersonID] {
        guard count > 0 else { return [] }
        let order = w.people.order
        let candidates = w.people.members.filter { $0 != .noah }.sorted { a, b in
            let pa = w.people[a]?.relation.points ?? 0
            let pb = w.people[b]?.relation.points ?? 0
            if pa != pb { return pa < pb }
            return (order.firstIndex(of: a) ?? 0) > (order.firstIndex(of: b) ?? 0)
        }
        return Array(candidates.prefix(count))
    }

    /// 拠点を去る(一時的にいない = away。戻るかどうかは R2 の離脱と合流の仕組みが決める)。
    /// 持ち物は拠点に置いていく。付いていたモジュール・運搬・戦闘から外れる。
    static func depart(_ p: PersonID, _ ctx: inout StepContext, cause: ProvenanceID) {
        guard var ps = ctx.world.people[p] else { return }
        let rec = ctx.record(.left, .person(p), actor: p, place: ps.position, inputs: [cause])
        ps.presence = .away(since: ctx.world.clock.now)
        ps.position = nil
        ps.motion = nil
        ps.assignment = .idle
        ps.override = nil
        ps.activity = .idle
        ctx.world.people[p] = ps
        let carried = ctx.world.inventory.holders[.person(p)] ?? []
        ctx.world.inventory.holders[.person(p)] = nil
        for entry in carried {
            if entry.unique != nil || entry.durability != nil {
                // 唯一品・減る品はそのままの山で置いていく(合わせない)
                ctx.world.inventory.holders[.base, default: []].append(entry)
                continue
            }
            var rest = entry.quantity
            for (o, n) in entry.origins.sorted(by: { $0.key < $1.key }) where n > 0 {
                ctx.addStock(entry.stuff, n, to: .base, origin: o)
                rest -= n
            }
            if rest > 0 { ctx.addStock(entry.stuff, rest, to: .base) }
        }
        ctx.changes.mark(.inventory)
        for id in ctx.world.placements.sortedIDs where ctx.world.placements.items[id]?.module?.operatorID == p {
            ctx.world.placements.items[id]?.module?.operatorID = nil
        }
        for id in ctx.world.logistics.routes.keys.sorted() {
            ctx.world.logistics.routes[id]?.haulers.removeAll { $0 == p }
        }
        for id in ctx.world.combat.battles.keys.sorted() {
            ctx.world.combat.battles[id]?.participants.removeAll { $0 == p }
        }
        ctx.emit(.personLeft(person: p, record: rec))
        ctx.changes.mark([.people, .placements])
    }

    /// 拠点の蓄えを割合で失う(唯一品は除く)。失った量は来歴 1 件(.consumed)にまとめる。
    static func loseStock(permille: Int, _ ctx: inout StepContext, cause: ProvenanceID) {
        guard permille > 0 else { return }
        var lost: [Value] = []
        for entry in ctx.world.inventory.entries(.base) where entry.unique == nil {
            let n = entry.quantity * min(permille, 1000) / 1000
            guard n > 0,
                  ctx.takeStock(n, from: .base, where: { $0.unique == nil && $0.stuff == entry.stuff }) != nil
            else { continue }
            let stuff = (try? CanonicalJSON.tree(entry.stuff)) ?? .null
            lost.append(.object(["stuff": stuff, "quantity": .int(Int64(n))]))
        }
        if !lost.isEmpty { ctx.record(.consumed, .none, inputs: [cause], detail: ["lost": .array(lost)]) }
    }
}
