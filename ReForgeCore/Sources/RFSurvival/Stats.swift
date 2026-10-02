import RFContent
import RFKernel
import RFMap
import RFRules
import RFWorld

/// 拠点全体の数値(survival.stats)の進め方。
///
/// - StatDef.perDay: 1 日(昼 + 夜)あたりの基礎の増減(基礎の上昇・暦)。
/// - 範囲の効果の statPerHour: 範囲が 1 つ効いている間、1 時間あたり足す(強さの千分率を掛ける)。上積み。
/// - 効果 stat(add): 出来事が内訳の値に直接足す(RFRules.EffectApplier)。
/// - StatDef.sumOf: 合計(内訳を足し直す)。内訳は内部に持ち、見せ方は認識の表。
/// - StatDef.wrap: 回る値(暦)。
/// - StatDef.marks: 越えたら statCrossed を出す(警告 G04・G05 と期限 G06 はこの値と失敗の規則で書く)。
enum Stats {
    /// 区切り 1 回(前の区切りから seconds 秒ぶん)。辞書を新しく作らず、定義の表を 1 回なめるだけにする。
    static func step(_ ctx: inout StepContext, seconds: Int64) {
        let defs = ctx.content.stats
        guard !defs.isEmpty else { return }
        let daySeconds = dayLength(ctx.content.clock)
        // 範囲の効果の上積み(raw/日)。効いている範囲が無ければ作らない
        var fromAuras: [StatID: Int64] = [:]
        if !ctx.world.auras.active.isEmpty {
            let now = ctx.world.clock.now
            let auraDefs = ctx.content.auras
            for a in ctx.world.auras.active.values {
                guard a.strength > 0, a.until.map({ now < $0 }) ?? true, let def = auraDefs[a.kind] else { continue }
                if def.requiresNear != nil, !Auras.tetherHolds(a, in: ctx.world, content: ctx.content) { continue }
                for m in def.modifiers {
                    if case .statPerHour(let stat, let amount) = m {
                        fromAuras[stat, default: 0] += Int64(amount) * Int64(a.strength) * daySeconds / (1000 * 3600)
                    }
                }
            }
        }
        // 数値ごとに独立なので、回す順番は結果に効かない(出来事は出さない)
        var hasSums = false
        for (id, def) in defs {
            if def.sumOf != nil { hasSums = true; continue }
            let rate = Int64(def.perDay ?? 0) + (fromAuras.isEmpty ? 0 : fromAuras.removeValue(forKey: id) ?? 0)
            if rate != 0 {
                let delta = Rates.advance(&ctx.world.survival.statCarry[id, default: 0], perDay: rate,
                                          seconds: seconds, daySeconds: daySeconds)
                if delta != 0 { ctx.world.survival.stats[id, default: .zero].raw += delta }
            }
            if let wrap = def.wrap, wrap > 0, let v = ctx.world.survival.stats[id] {
                let w = Int64(wrap)
                let wrapped = ((v.raw % w) + w) % w
                if wrapped != v.raw { ctx.world.survival.stats[id] = Milli(raw: wrapped) }
            }
        }
        // 定義の無い数値への上積み(範囲の効果だけが足す値)
        for (id, rate) in fromAuras where rate != 0 {
            let delta = Rates.advance(&ctx.world.survival.statCarry[id, default: 0], perDay: rate,
                                      seconds: seconds, daySeconds: daySeconds)
            if delta != 0 { ctx.world.survival.stats[id, default: .zero].raw += delta }
        }
        addMined(&ctx)
        if hasSums { recomputeSums(&ctx.world.survival, defs) }
        ctx.changes.mark(.survival)
    }

    /// 掘った量の項(StatDef.mined。U16・OPEN-S2)。合う鉱脈の減った回数の合計を数え、前に足した回数からの差だけ足す。
    /// per 回ごとに amount。端数の回数は次に持ち越す(足した回数を per の倍数で進める)。掘らなければ何もしない。
    static func addMined(_ ctx: inout StepContext) {
        let terms = ctx.content.stats.filter { $0.value.mined != nil }
        guard !terms.isEmpty else { return }
        for (id, def) in terms.sorted(by: { $0.key < $1.key }) {
            guard let m = def.mined, m.amount != 0 else { continue }
            let per = max(1, m.per ?? 1)
            let total = minedCount(m.ores, ctx.world)
            let seen = ctx.world.survival.minedSeen?[id] ?? 0
            let steps = (total - seen) / per
            guard steps > 0 else { continue }
            ctx.world.survival.minedSeen = (ctx.world.survival.minedSeen ?? [:]).merging([id: seen + steps * per]) { $1 }
            ctx.world.survival.stats[id, default: .zero].raw += Int64(steps * m.amount)
        }
    }

    /// 合う鉱脈(種類の名前か組成の物質)の、掘った回数の合計(全部の層)。
    static func minedCount(_ ores: [String], _ w: WorldState) -> Int {
        let want = Set(ores)
        var n = 0
        for (_, layer) in w.map.layers {
            for d in layer.deposits.all where d.remainingExtractions < d.initialExtractions {
                if want.contains(d.category.rawValue) || d.composition.contains(where: { want.contains($0.substance.rawValue) }) {
                    n += d.initialExtractions - d.remainingExtractions
                }
            }
        }
        return n
    }

    /// 合計の値を内訳から足し直す。合計の合計もあるので、変わらなくなるまで(最大で合計の数だけ)繰り返す。
    static func recomputeSums(_ s: inout SurvivalState, _ defs: [StatID: StatDef]) {
        var passes = 0
        var changed = true
        while changed, passes <= defs.count {
            changed = false
            passes += 1
            for (id, def) in defs {
                guard let parts = def.sumOf else { continue }
                var total: Int64 = 0
                for part in parts { total += s.stats[part]?.raw ?? 0 }
                if s.stats[id]?.raw != total {
                    s.stats[id] = Milli(raw: total)
                    changed = true
                }
            }
        }
    }

    /// しきい値を越えた数値を知らせる(上りでも下りでも)。前に見た値と比べるので、効果が足した分も拾う。
    /// 知らせは数値の ID 順(決定的に)。
    static func markCrossings(_ ctx: inout StepContext) {
        var crossed: [StatID] = []
        for (id, def) in ctx.content.stats {
            guard let marks = def.marks, !marks.isEmpty else { continue }
            let now = ctx.world.survival.stat(id)
            guard let before = ctx.world.survival.marksSeen[id] else {
                ctx.world.survival.marksSeen[id] = now
                continue
            }
            guard before != now else { continue }
            ctx.world.survival.marksSeen[id] = now
            let lo = min(before.raw, now.raw), hi = max(before.raw, now.raw)
            // 上り: before < m <= now / 下り: now < m <= before
            if marks.contains(where: { Int64($0) > lo && Int64($0) <= hi }) { crossed.append(id) }
        }
        guard !crossed.isEmpty else { return }
        for id in crossed.sorted() { ctx.emit(.statCrossed(stat: id, value: ctx.world.survival.stat(id))) }
    }

    /// 内部の 1 日の秒(ContentDB を丸ごと渡さない。毎ステップ写すと重いので)。
    static func dayLength(_ clock: ClockDef) -> Int64 {
        max(1, clock.dayGameSeconds + clock.nightGameSeconds)
    }
}

/// 「率 × 時間」を整数の端数つきで足す道具。
enum Rates {
    /// 1 日あたり perDay の率で seconds 秒ぶん進めたときの増減を返す。端数は carry(単位: raw × 秒)に残す。
    /// 同じ時間を何回に分けても合計が一致する(固定ステップでも、効果の割り込みがあっても)。
    static func advance(_ carry: inout Int64, perDay: Int64, seconds: Int64, daySeconds: Int64) -> Int64 {
        carry += perDay * seconds
        let delta = carry / daySeconds
        carry -= delta * daySeconds
        return delta
    }

    /// 1 時間あたりの率で。
    static func advance(_ carry: inout Int64, perHour: Int64, seconds: Int64) -> Int64 {
        advance(&carry, perDay: perHour, seconds: seconds, daySeconds: 3600)
    }
}
