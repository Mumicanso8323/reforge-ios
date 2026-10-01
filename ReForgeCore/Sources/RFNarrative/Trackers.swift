import RFContent
import RFKernel
import RFRules
import RFWorld

/// 追跡カウンタ(TrackerDef → narrative.counters)。日数の代わりに引き金に使う「数で数える来歴」。
/// 例: 2 人が近くで働いた分・条件が成り立っていた夜の数・来歴の数・拠点から最も遠くまで行ったマス数。
/// 出来事の条件は counter(id:cmp:value:) で読む。乱数は使わない。
enum Trackers {
    /// 毎ステップ(近くにいた時間・条件が成り立っていた時間・最も遠くまで行った距離)。
    static func step(_ ctx: inout StepContext) {
        guard !ctx.content.trackers.isEmpty else { return }
        let (add, maxes) = measure(ctx.world, ctx.content)
        for id in add { addSeconds(id, SimStep.gameSeconds, &ctx) }
        for (id, d) in maxes {
            ctx.world.narrative.counters[id] = d
            ctx.changes.mark(.narrative)
        }
    }

    /// 読むだけの部分(世界を書き換える前に済ませる)。
    static func measure(_ w: WorldState, _ content: ContentDB) -> ([CounterID], [(CounterID, Int)]) {
        var add: [CounterID] = []
        var maxes: [(CounterID, Int)] = []
        for (id, def) in content.trackers.sorted(by: { $0.key < $1.key }) {
            switch def.kind {
            case .proximityMinutes(let a, let b, let radius, let whileWorking):
                guard let pa = w.people[a], let pb = w.people[b], pa.presence.isAlive, pb.presence.isAlive,
                      let xa = pa.position, let xb = pb.position, xa.layer == xb.layer,
                      xa.point.chebyshev(to: xb.point) <= radius else { continue }
                if whileWorking {
                    switch pb.activity {
                    case .working, .carrying, .interacting: break
                    default: continue
                    }
                }
                add.append(id)
            case .minutesWhere(let c):
                if ConditionEvaluator.evaluatePure(c, world: w, content: content) == true { add.append(id) }
            case .farthestFromBase(let person):
                guard let area = w.base.area else { continue }
                let base = GridPoint(area.origin.x + area.size.width / 2, area.origin.y + area.size.height / 2)
                let who = person.map { [$0] } ?? w.people.members
                var d = 0
                for p in who {
                    if let pos = w.people[p]?.position, pos.layer == .surface { d = max(d, pos.point.chebyshev(to: base)) }
                }
                if d > w.narrative.counters[id, default: 0] { maxes.append((id, d)) }
            case .nightsWhere, .ledgerCount:
                break
            }
        }
        return (add, maxes)
    }

    /// 夜明け: 条件が成り立っていた夜を 1 つ数える(夜明けの時点で判定)。
    static func dawn(_ ctx: inout StepContext) {
        for (id, def) in ctx.content.trackers.sorted(by: { $0.key < $1.key }) {
            guard case .nightsWhere(let c) = def.kind,
                  ConditionEvaluator.evaluatePure(c, world: ctx.world, content: ctx.content) == true else { continue }
            ctx.world.narrative.counters[id, default: 0] += 1
            ctx.changes.mark(.narrative)
        }
    }

    /// 来歴の数を数え直す(来歴の付いた出来事の後と毎時)。
    static func refreshLedgerCounts(_ ctx: inout StepContext) {
        for (id, def) in ctx.content.trackers.sorted(by: { $0.key < $1.key }) {
            guard case .ledgerCount(let q) = def.kind else { continue }
            let n = ProvenanceQueries.count(q, in: ctx.world)
            if ctx.world.narrative.counters[id] != n {
                ctx.world.narrative.counters[id] = n
                ctx.changes.mark(.narrative)
            }
        }
    }

    /// 秒を端数に足し、分に繰り上げて counters に入れる。
    static func addSeconds(_ id: CounterID, _ s: Int64, _ ctx: inout StepContext) {
        var carry = ctx.world.narrative.trackerCarry[id, default: 0] + s
        let minutes = Int(carry / 60)
        carry %= 60
        ctx.world.narrative.trackerCarry[id] = carry
        if minutes > 0 {
            ctx.world.narrative.counters[id, default: 0] += minutes
            ctx.changes.mark(.narrative)
        }
    }
}
