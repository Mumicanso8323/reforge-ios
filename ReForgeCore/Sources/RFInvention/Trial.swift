import RFContent
import RFKernel
import RFMatter
import RFRules
import RFWorld

/// 試作(設計画面の「試す」)。手持ちの鉱石と燃料・水・混ぜ物を実際に使う(だから総当たりはできない)。
///
/// - 計算は RFMatter の `ProcessChain.run`(規則の表はコンテンツの `ruleBook`)。1 単位ずつ同じ並びを通すので、
///   使う物は 1 単位ぶんの quantity 倍。
/// - できた物(鉱石のままでも)は在庫に戻る。最初の製錬の 1 個は唯一品(最初の鉄)として残る。
/// - 結果はノートに試作の記録(所見・結果)として載り、図鑑が埋まる。所見は事実だけで、規則はまとめない。
/// - 夜作業の中なら 2 時間進む。日没に試せば夜作業を始める。昼はリアルタイムのまま(時間を返さない)。
enum Trials {
    /// 夜作業の試作 1 回にかかる時間(order.md §5.5)。
    static let nightDuration = GameDuration.hours(2)

    static func run(input sel: StockSelector, quantity: Int, steps: [ProcessStep], _ ctx: inout StepContext)
        -> CommandResult
    {
        guard quantity > 0 else { return .rejected(Rejection(InventionReasons.badQuantity)) }
        if let r = InventionChecks.steps(steps, ctx.world) { return .rejected(r) }
        guard case .matter(let ore) = sel.stuff else {
            return .rejected(Rejection(InventionReasons.notMaterial))
        }
        let isInput: (StockEntry) -> Bool = { $0.stuff == sel.stuff && $0.unique == sel.unique }
        let have = ctx.world.inventory.entries(sel.holder).filter(isInput).reduce(0) { $0 + $1.quantity }
        guard have >= quantity else {
            return .rejected(Rejection(InventionReasons.notEnoughInput, detail: ["have": .int(Int64(have))]))
        }

        let result = ProcessChain.run(steps, input: ore, rules: ctx.content.ruleBook)
        let needs = result.consumed.map { ItemAmount($0.item, $0.quantity * quantity) }
        let supply = supplyHolders(sel.holder)
        for need in needs {
            let n = supply.reduce(0) { $0 + spendable(need.item, in: $1, ctx.world) }
            if n < need.quantity {
                return .rejected(Rejection(
                    InventionReasons.missingInput,
                    detail: ["item": .string(need.item.rawValue), "need": .int(Int64(need.quantity)),
                             "have": .int(Int64(n))]))
            }
        }

        // 使う(先に確かめたので足りる)
        var origins = ctx.takeStock(quantity, from: sel.holder, where: isInput) ?? [:]
        for need in needs {
            var left = need.quantity
            for h in supply where left > 0 {
                let k = min(left, spendable(need.item, in: h, ctx.world))
                guard k > 0 else { continue }
                for (p, c) in ctx.takeStock(k, from: h, where: { $0.stuff == .item(need.item) && $0.unique == nil }) ?? [:] {
                    origins[p, default: 0] += c
                }
                left -= k
            }
        }

        let product = result.product
        let smelted = product.stage == .metal && ore.stage != .metal
        let first = smelted && !ctx.world.ledger.records.contains { $0.tags.contains(InventionTags.smelted) }
        var tags: Set<ProvenanceTag> = []
        if smelted { tags.insert(InventionTags.smelted) }
        if first { tags.insert(InventionTags.firstSmelt) }
        let inputs = origins.keys.filter { $0 != ProvenanceLedger.unknownOrigin }.sorted()
        let rec = ctx.record(
            .trialed, .matter(result.name), actor: .noah, place: ctx.world.people[.noah]?.position, inputs: inputs,
            tags: tags,
            detail: [
                "purity": .int(Int64(product.purity.basisPoints)), "stage": .string(product.stage.rawValue),
                "shape": .string(product.shape.rawValue), "quantity": .int(Int64(quantity)),
                "steps": .int(Int64(steps.count)),
            ])

        var unique: EntityID?
        if first {
            let id = ctx.world.newEntityID()
            unique = id
            ctx.addStock(.matter(product), 1, to: sel.holder, origin: rec, unique: id)
            ctx.addStock(.matter(product), quantity - 1, to: sel.holder, origin: rec)
        } else {
            ctx.addStock(.matter(product), quantity, to: sel.holder, origin: rec)
        }

        let now = ctx.world.clock.now
        ctx.world.notebook.trials.append(TrialRecord(
            record: rec, at: now, run: ctx.world.run.index, input: ore, quantity: quantity, steps: steps,
            outcome: result, holder: sel.holder, unique: unique))
        Codex.note(&ctx.world.notebook, name: result.name, purity: product.purity, record: rec)
        ctx.changes.mark(.notebook)
        ctx.emit(.trialed(record: rec))

        switch ctx.world.clock.phase {
        case .day: return .done
        case .dusk:
            // 日没に試したら夜作業を始める(帯で選ぶのと同じ。時計の担当のコマンドを通す)
            ctx.queue(.time(.startNightWork))
            return .accepted(time: nightDuration)
        case .nightWork: return .accepted(time: nightDuration)
        }
    }

    /// 使ってよい数(唯一品は燃料などに使わない)。
    static func spendable(_ item: ItemID, in h: HolderID, _ w: WorldState) -> Int {
        w.inventory.entries(h).filter { $0.stuff == .item(item) && $0.unique == nil }.reduce(0) { $0 + $1.quantity }
    }

    /// 燃料・水・混ぜ物を取る在り処の順(鉱石を出した所 → 拠点の蓄え → ノアの持ち物)。
    static func supplyHolders(_ first: HolderID) -> [HolderID] {
        var out: [HolderID] = []
        for h in [first, .base, .person(.noah)] where !out.contains(h) { out.append(h) }
        return out
    }
}

/// 並びの確かめ(試作とライン札に共通)。
enum InventionChecks {
    static func steps(_ steps: [ProcessStep], _ w: WorldState) -> Rejection? {
        guard !steps.isEmpty else { return Rejection(InventionReasons.noSteps) }
        if let s = steps.first(where: { !w.research.unlocked.modules.contains($0.module) }) {
            return Rejection(InventionReasons.moduleLocked, detail: ["module": .string(s.module.rawValue)])
        }
        return nil
    }
}
