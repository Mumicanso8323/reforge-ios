import RFContent
import RFKernel
import RFWorld

/// 仲間の一言の選び方(MECH-05)。持ち主: U11。
///
/// 一言は振る舞いに付く短い文(焚き火・作業中・賛否・配属・巻き戻しの「前にも」…)。どれを言うかは
/// 文脈(LineDef.context)と条件(LineDef.when)で絞り、重み(weight)で物語の乱数の流れから選ぶ。
/// 本文は持たない(LineID を残し、画面は認識の層で文字にする)。
/// 使い方: 効果 say、または他のシステム(RFCrew の焚き火・賛否など)が Lines.say を呼ぶ。
public enum Lines {
    /// 文脈に合う一言の候補(ID 順)。speaker を指定すればその人だけ。乱数は使わない。
    public static func candidates(context: String, speaker: PersonID?, world w: WorldState, content: ContentDB,
                                  trigger: ProvenanceID? = nil) -> [LineDef]
    {
        let recent = w.narrative.lineLog.suffix(3).map(\.line)
        return content.lines.values.sorted { $0.id < $1.id }.filter { l in
            guard l.context == context else { return false }
            if let s = speaker, l.speaker != s { return false }
            // 話す人は生きていて、会っている(一員でなくてもよい: 倒れていた人の一言もある)
            guard let ps = w.people[l.speaker], ps.presence.isAlive else { return false }
            if case .unmet = ps.presence { return false }
            if let c = l.when, ConditionEvaluator.evaluatePure(c, world: w, content: content, trigger: trigger) != true {
                return false
            }
            if let h = l.cooldownHours {
                if let last = w.narrative.lineLog.last(where: { $0.line == l.id }), w.clock.now - last.at < .hours(h) {
                    return false
                }
            } else if recent.contains(l.id) {
                return false
            }
            return true
        }
    }

    /// 一言を選ぶ(候補が 1 つでもあれば物語の乱数の流れを 1 回進める)。
    public static func pick(context: String, speaker: PersonID?, _ ctx: inout StepContext,
                            trigger: ProvenanceID? = nil) -> LineDef?
    {
        let cs = candidates(context: context, speaker: speaker, world: ctx.world, content: ctx.content, trigger: trigger)
        guard !cs.isEmpty else { return nil }
        let total = cs.reduce(0) { $0 + max(1, $1.weight ?? 1) }
        var roll = ctx.random(.narrative) { $0.int(below: total) }
        for l in cs {
            roll -= max(1, l.weight ?? 1)
            if roll < 0 { return l }
        }
        return cs.last
    }

    /// 一言を選んで言わせる(narrative.lineLog に残し、lineSpoken を出す)。言わなかったら nil。
    @discardableResult
    public static func say(context: String, speaker: PersonID?, _ ctx: inout StepContext,
                           trigger: ProvenanceID? = nil) -> LineID?
    {
        guard let l = pick(context: context, speaker: speaker, &ctx, trigger: trigger) else { return nil }
        ctx.world.narrative.lineLog.append(SpokenLine(person: l.speaker, line: l.id, at: ctx.world.clock.now))
        if ctx.world.narrative.lineLog.count > NarrativeState.lineLogLimit {
            ctx.world.narrative.lineLog.removeFirst(ctx.world.narrative.lineLog.count - NarrativeState.lineLogLimit)
        }
        ctx.emit(.lineSpoken(person: l.speaker, line: l.id))
        ctx.changes.mark(.narrative)
        return l.id
    }
}
