import RFContent
import RFKernel
import RFRules
import RFWorld

/// 関係・賛否・焚き火の会話(MECH-05)。
///
/// 賛否: プレイヤーの判断(資源と人手を何に使うか)は来歴に印(ProvenanceTag)付きで残る。仲間は自分の思想の傾き
/// (軸 → 値)と軸の重み(IdeologyAxisDef.weights: 印 → 重み)から賛否の強さを出し、`opinion` を出して関係が動く。
/// 一番強く思った人が一言(文脈 "opinion.approve" / "opinion.disapprove")を言う。
enum Relations {
    /// 賛否を出す出来事(プレイヤーの判断が来歴になるもの)。持ち物の出入り・賛否そのもの・会話などは見ない(二重に数えない)。
    static let decisionHooks: Set<String> = [
        "placed", "dismantled", "built", "crafted", "trialed", "designed", "decided", "interacted", "finite.used",
        "research.completed", "skill", "battle.ended", "event",
    ]

    /// 点を足し、ランクが変わったら知らせる。
    static func add(_ id: PersonID, _ delta: Int, _ ctx: inout StepContext) {
        guard delta != 0, var ps = ctx.world.people[id] else { return }
        ps.relation.add(delta)
        ctx.world.people[id] = ps
        ctx.emit(.relationChanged(person: id, rank: ps.relation.rank, delta: delta))
        ctx.changes.mark(.people)
    }

    /// 効果などで点だけ足されたものを、ランクに直す(毎ステップ)。
    static func normalizeAll(_ ctx: inout StepContext) {
        for id in ctx.world.people.order {
            guard var ps = ctx.world.people[id] else { continue }
            let before = ps.relation
            guard ps.relation.normalize() > 0 else { continue }
            ctx.world.people[id] = ps
            _ = before
            ctx.emit(.relationChanged(person: id, rank: ps.relation.rank, delta: 0))
            ctx.changes.mark(.people)
        }
    }

    /// 来歴 1 件に対する一員の賛否。
    static func consider(_ record: ProvenanceID, _ ctx: inout StepContext) {
        guard let r = ctx.world.ledger.record(record), !r.tags.isEmpty else { return }
        let day = ctx.world.clock.day
        var strongest: (PersonID, Int)?
        for id in ctx.world.people.members where id != .noah {
            guard let ps = ctx.world.people[id], ps.presence.isAlive else { continue }
            let stance = Ideology.stance(ps.ideology, tags: r.tags, content: ctx.content)
            guard stance != 0 else { continue }
            ctx.emit(.opinion(person: id, about: record, stance: stance))
            // 同じ印で 1 日に何度も関係が動かないように(同じ物を 10 個置いても 1 回分)
            let fresh = r.tags.filter { ps.opinionDays?[$0] != day }
            if !fresh.isEmpty {
                var days = ps.opinionDays ?? [:]
                for t in r.tags { days[t] = day }
                ctx.world.people[id]?.opinionDays = days
                let delta = max(-CrewRules.opinionPointCap, min(CrewRules.opinionPointCap, stance))
                add(id, delta, &ctx)
            }
            if strongest == nil || abs(stance) > abs(strongest!.1) { strongest = (id, stance) }
        }
        if let (who, stance) = strongest {
            Lines.say(context: stance > 0 ? "opinion.approve" : "opinion.disapprove", speaker: who, &ctx, trigger: record)
        }
    }

    /// 焚き火で話す(夜作業)。1 晩に 1 回だけ関係が深まる。
    static func talk(_ id: PersonID, _ ctx: inout StepContext) -> CommandResult {
        guard ctx.world.clock.phase != .day else { return .rejected(Rejection("reason.talk.not_night")) }
        guard id != .noah, let ps = ctx.world.people[id], ps.presence.isMember, ps.position != nil else {
            return .rejected(Rejection("reason.talk.no_one"))
        }
        if case .fighting = ps.activity { return .rejected(Rejection("reason.talk.busy")) }
        let day = ctx.world.clock.day
        let rec = ctx.record(.talked, .person(id), actor: .noah, place: ctx.world.people[.noah]?.position)
        if ps.talkedOnDay != day {
            ctx.world.people[id]?.talkedOnDay = day
            add(id, CrewRules.talkPoints, &ctx)
        }
        let until = ctx.world.clock.now + CrewRules.talkDuration
        for (a, b) in [(id, PersonID.noah), (PersonID.noah, id)] {
            ctx.world.people[a]?.activity = .talking(with: b)
            ctx.world.people[a]?.motion = nil
            ctx.world.people[a]?.dwellUntil = until
        }
        Lines.say(context: "campfire", speaker: id, &ctx, trigger: rec)
        ctx.changes.mark(.people)
        return .accepted(time: CrewRules.talkDuration)
    }
}

/// 会う・加わる・離れる・死ぬ・傷を負う(効果から来るコマンド。cause = 引き金の来歴)。
enum Membership {
    static func meet(_ id: PersonID, at: WorldPoint?, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard var ps = ctx.world.people[id] ?? (ctx.content.people[id] != nil ? PersonState(id: id, presence: .unmet) : nil)
        else { return .rejected(Rejection("reason.person.unknown")) }
        if ctx.world.people[id] == nil { ps.group = ctx.content.people[id]?.group }
        guard case .unmet = ps.presence else { return .done }  // 既に会っている
        let now = ctx.world.clock.now
        ps.presence = .met(at: now)
        if let at { ps.position = at }
        if ps.ideology.isEmpty { ps.ideology = ctx.content.people[id]?.ideology ?? [:] }
        ctx.world.people[id] = ps
        let rec = ctx.record(.met, .person(id), actor: .noah, place: ps.position, inputs: cause.map { [$0] } ?? [])
        ctx.emit(.personMet(person: id, record: rec))
        ctx.changes.mark(.people)
        return .done
    }

    static func join(_ id: PersonID, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard var ps = ctx.world.people[id] ?? (ctx.content.people[id] != nil ? PersonState(id: id, presence: .unmet) : nil)
        else { return .rejected(Rejection("reason.person.unknown")) }
        if ctx.world.people[id] == nil { ps.group = ctx.content.people[id]?.group }
        switch ps.presence {
        case .member: return .done
        case .dead: return .rejected(Rejection("reason.person.dead"))
        default: break
        }
        let now = ctx.world.clock.now
        ps.presence = .member(since: now)
        if ps.position == nil {
            ps.position = ctx.world.people[.noah]?.position ?? ctx.world.map.spawn
        }
        if ps.ideology.isEmpty { ps.ideology = ctx.content.people[id]?.ideology ?? [:] }
        ps.assignment = .idle
        ctx.world.people[id] = ps
        let rec = ctx.record(.joined, .person(id), actor: id, place: ps.position, inputs: cause.map { [$0] } ?? [])
        ctx.emit(.personJoined(person: id, record: rec))
        ctx.changes.mark(.people)
        return .done
    }

    static func leave(_ id: PersonID, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard id != .noah, var ps = ctx.world.people[id] else { return .rejected(Rejection("reason.person.unknown")) }
        guard ps.presence.isMember else { return .done }
        let place = ps.position
        ps.presence = .away(since: ctx.world.clock.now)
        clearOnMap(&ps)
        ctx.world.people[id] = ps
        let rec = ctx.record(.left, .person(id), actor: id, place: place, inputs: cause.map { [$0] } ?? [])
        ctx.emit(.personLeft(person: id, record: rec))
        ctx.changes.mark(.people)
        return .done
    }

    /// 死ぬ。戻らない。来歴の inputs に引き金(誰の判断で・何で)を残す。
    static func die(_ id: PersonID, reason: TextID, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard var ps = ctx.world.people[id] else { return .rejected(Rejection("reason.person.unknown")) }
        guard ps.presence.isAlive else { return .done }
        let place = ps.position
        let rec = ctx.record(.died, .person(id), actor: id, place: place, inputs: cause.map { [$0] } ?? [],
                             detail: ["cause": .string(reason.rawValue)])
        ps.presence = .dead(at: ctx.world.clock.now, record: rec)
        clearOnMap(&ps)
        ctx.world.people[id] = ps
        ctx.emit(.personDied(person: id, record: rec))
        ctx.changes.mark(.people)
        return .done
    }

    /// 傷を負う(amount = 体力の千分率の raw)。体力が尽きれば死ぬ(死因は傷)。
    static func injure(_ id: PersonID, amount: Int, cause: ProvenanceID?, _ ctx: inout StepContext) -> CommandResult {
        guard var ps = ctx.world.people[id], ps.presence.isAlive else { return .rejected(Rejection("reason.person.unknown")) }
        let rec = ctx.record(.wasInjured, .person(id), actor: id, place: ps.position, inputs: cause.map { [$0] } ?? [],
                             detail: ["amount": .int(Int64(amount))])
        ps.body.health = Milli(raw: max(0, ps.body.health.raw - Int64(amount)))
        ctx.world.people[id] = ps
        ctx.emit(.bodyChanged(person: id))
        ctx.changes.mark(.people)
        if ps.body.health.raw <= 0 {
            return die(id, reason: "cause.injury", cause: rec, &ctx)
        }
        return .done
    }

    static func clearOnMap(_ ps: inout PersonState) {
        ps.position = nil
        ps.motion = nil
        ps.activity = .idle
        ps.assignment = .idle
        ps.override = nil
        ps.haulLeg = nil
        ps.workSpeed = nil
        ps.dwellUntil = nil
    }
}
