import RFContent
import RFKernel
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
    static func step(_ ctx: inout StepContext) {
        let content = ctx.content
        guard !content.stats.isEmpty else { return }
        let daySeconds = dayLength(content)
        // 1 日あたりの率(raw/日)を数値ごとに集める
        var perDay: [StatID: Int64] = [:]
        for (id, def) in content.stats where def.sumOf == nil {
            if let d = def.perDay, d != 0 { perDay[id, default: 0] += Int64(d) }
        }
        let now = ctx.world.clock.now
        for a in ctx.world.auras.active.values.sorted(by: { $0.id < $1.id }) {
            guard a.strength > 0, a.until.map({ now < $0 }) ?? true else { continue }
            for m in content.auras[a.kind]?.modifiers ?? [] {
                if case .statPerHour(let stat, let amount) = m {
                    perDay[stat, default: 0] += Int64(amount) * Int64(a.strength) * daySeconds / (1000 * 3600)
                }
            }
        }
        // 数値ごとに独立なので、回す順番は結果に効かない(出来事は出さない)
        for (id, rate) in perDay {
            let delta = Rates.advance(&ctx.world.survival.statCarry[id, default: 0], perDay: rate,
                                      seconds: SimStep.gameSeconds, daySeconds: daySeconds)
            if delta != 0 { ctx.world.survival.stats[id, default: .zero].raw += delta }
        }
        // 回る値と合計
        for (id, def) in content.stats {
            if let wrap = def.wrap, wrap > 0, let v = ctx.world.survival.stats[id] {
                let w = Int64(wrap)
                ctx.world.survival.stats[id] = Milli(raw: ((v.raw % w) + w) % w)
            }
        }
        recomputeSums(&ctx.world.survival, content)
        ctx.changes.mark(.survival)
    }

    /// 合計の値を内訳から足し直す(合計の合計も、定義の深さぶん繰り返して解く)。
    static func recomputeSums(_ s: inout SurvivalState, _ content: ContentDB) {
        let sums = content.stats.filter { $0.value.sumOf != nil }.sorted { $0.key < $1.key }
        guard !sums.isEmpty else { return }
        for _ in 0..<max(1, sums.count) {
            for (id, def) in sums {
                s.stats[id] = Milli(raw: (def.sumOf ?? []).reduce(0) { $0 + (s.stats[$1]?.raw ?? 0) })
            }
        }
    }

    /// しきい値を越えた数値を知らせる(上りでも下りでも)。前に見た値と比べるので、効果が足した分も拾う。
    static func markCrossings(_ ctx: inout StepContext) {
        for (id, def) in ctx.content.stats.sorted(by: { $0.key < $1.key }) {
            guard let marks = def.marks, !marks.isEmpty else { continue }
            let now = ctx.world.survival.stat(id)
            defer { ctx.world.survival.marksSeen[id] = now }
            guard let before = ctx.world.survival.marksSeen[id], before != now else { continue }
            let lo = min(before.raw, now.raw), hi = max(before.raw, now.raw)
            // 上り: before < m <= now / 下り: now < m <= before
            if marks.contains(where: { Int64($0) > lo && Int64($0) <= hi }) {
                ctx.emit(.statCrossed(stat: id, value: now))
            }
        }
    }

    static func dayLength(_ content: ContentDB) -> Int64 {
        max(1, content.clock.dayGameSeconds + content.clock.nightGameSeconds)
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
