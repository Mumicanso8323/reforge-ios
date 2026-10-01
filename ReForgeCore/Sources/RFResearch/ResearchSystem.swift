import RFContent
import RFKernel
import RFRules
import RFWorld

/// 研究・スキル・解禁(CORE-13)。
///
/// - 研究パッケージ: 選んだパッケージを、研究机(provides["research"] を持つ建造物)に付いた人が昼の間に進める
///   (夜は夜作業の「研究」でだけ)。中の段(nodes)ごとに解禁と効果があり、全部終わるとパッケージの解禁と効果。
///   発明の試作とは別の解禁の道。存在を伏せる研究は visibleWhen が成り立つまで一覧に出ず、選べない。
/// - スキル: 人が時間をかけて習う(習っている間は学ぶ時期 = BEAT-15)。身につくと解禁と効果、
///   作業への効き(WorkModifier: 成功率・速さ・量)は各システムが ContentDB の問い合わせで読む。
///   PersonState.skills への書き込みは人の担当(U5)が `.skillAcquired` を受けて行う。
///
/// 書いてよい切れ端: research。乱数の流れ: .research(今は使わない)。受けるコマンド: .research(...)。
public struct ResearchSystem: SimSystem {
    public let name = "research"
    public init() {}

    // MARK: コマンド

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .research(let rc) = command else { return .notMine }
        switch rc {
        case .select(let id): return select(id, &ctx)
        case .learnSkill(let p, let s): return learn(p, s, &ctx)
        case .stopLearning(let p):
            guard let l = ctx.world.research.learning[p] else { return .rejected(Rejection(ResearchReasons.notLearning)) }
            ctx.world.research.skillProgress[p, default: [:]][l.skill] = l.progress
            ctx.world.research.learning[p] = nil
            ctx.changes.mark(.research)
            return .done
        case .nightStudy(let p): return nightStudy(p, &ctx)
        }
    }

    private func select(_ id: ResearchID, _ ctx: inout StepContext) -> CommandResult {
        let w = ctx.world
        guard let d = ctx.content.research[id], ResearchRules.isVisible(d, w, ctx.content) else {
            return .rejected(Rejection(ResearchReasons.unknown))
        }
        guard !w.research.completed.contains(id) else { return .rejected(Rejection(ResearchReasons.done)) }
        guard ResearchRules.requirementsMet(d, w, ctx.content) else {
            return .rejected(Rejection(ResearchReasons.locked))
        }
        if w.research.active == id { return .done }
        // 物を使う研究は、初めて選んだときにだけ使う。
        if let cost = d.cost, !cost.isEmpty, !w.research.costPaid.contains(id) {
            for ing in cost {
                let have = w.inventory.entries(.base).filter(ing.matches).reduce(0) { $0 + $1.quantity }
                guard have >= ing.quantity else { return .rejected(Rejection(ResearchReasons.noMaterials)) }
            }
            for ing in cost { _ = ctx.takeStock(ing.quantity, from: .base, where: ing.matches) }
            ctx.world.research.costPaid.insert(id)
        }
        ctx.world.research.active = id
        ctx.changes.mark(.research)
        return .done
    }

    private func learn(_ p: PersonID, _ s: SkillID, _ ctx: inout StepContext) -> CommandResult {
        let w = ctx.world
        guard let ps = w.people[p], ps.presence.isMember else { return .rejected(Rejection(ResearchReasons.notMember)) }
        guard let d = ctx.content.skills[s], ResearchRules.isVisible(d, w, ctx.content) else {
            return .rejected(Rejection(ResearchReasons.skillUnknown))
        }
        guard !ps.skills.contains(s) else { return .rejected(Rejection(ResearchReasons.skillKnown)) }
        if w.research.learning[p]?.skill == s { return .done }
        guard ResearchRules.requirementsMet(d, w, ctx.content) else {
            return .rejected(Rejection(ResearchReasons.skillLocked))
        }
        // 習っていた別のスキルの進みは取っておく。
        if let old = w.research.learning[p] {
            ctx.world.research.skillProgress[p, default: [:]][old.skill] = old.progress
        }
        let saved = w.research.skillProgress[p]?[s] ?? 0
        ctx.world.research.skillProgress[p]?[s] = nil
        if ResearchRules.skillUnits(d) <= saved {
            ctx.world.research.learning[p] = nil
            acquire(p, s, d, &ctx)
        } else {
            ctx.world.research.learning[p] = SkillLearning(skill: s, progress: saved, since: w.clock.now)
        }
        ctx.changes.mark(.research)
        return .done
    }

    private func nightStudy(_ p: PersonID, _ ctx: inout StepContext) -> CommandResult {
        let w = ctx.world
        guard w.clock.phase == .nightWork else { return .rejected(Rejection(ResearchReasons.notNight)) }
        guard let ps = w.people[p], ps.presence.isMember else { return .rejected(Rejection(ResearchReasons.notMember)) }
        guard let a = w.research.active, let d = ctx.content.research[a] else {
            return .rejected(Rejection(ResearchReasons.nothingSelected))
        }
        guard !ResearchRules.desks(w, ctx.content, station: d.station).isEmpty else {
            return .rejected(Rejection(ResearchReasons.noDesk))
        }
        let time = GameDuration.hours(ResearchRules.nightStudyHours)
        ctx.world.research.nightSessions[p] = w.clock.now + time
        ctx.changes.mark(.research)
        return .accepted(time: time)
    }

    // MARK: ステップ

    public func step(_ ctx: inout StepContext) {
        advanceResearch(&ctx)
        advanceSkills(&ctx)
        // 終わった夜の研究を片付ける。
        let now = ctx.world.clock.now
        if ctx.world.research.nightSessions.values.contains(where: { $0 <= now }) {
            ctx.world.research.nightSessions = ctx.world.research.nightSessions.filter { $0.value > now }
        }
    }

    private func advanceResearch(_ ctx: inout StepContext) {
        var studying: [PersonID] = []
        defer {
            if ctx.world.research.studying != studying {
                ctx.world.research.studying = studying
                ctx.changes.mark(.research)
            }
        }
        guard let id = ctx.world.research.active else { return }
        guard let d = ctx.content.research[id], !ctx.world.research.completed.contains(id) else {
            ctx.world.research.active = nil
            return
        }
        let crew = ResearchRules.contributors(for: d, ctx.world, ctx.content)
        guard !crew.isEmpty else { return }
        studying = crew.map(\.person).sorted()
        let gain = ResearchRules.combined(crew.map(\.units))
        guard gain > 0 else { return }
        let total = d.totalPoints * ResearchState.unitsPerPoint
        let now = min(total, (ctx.world.research.progress[id] ?? 0) + gain)
        ctx.world.research.progress[id] = now
        ctx.changes.mark(.research)
        // 一番速い人を行為者として残す(「誰が研究したか」を後で指せるように)。
        let lead = crew.max { ($0.units, $1.person) < ($1.units, $0.person) }?.person

        // 段
        let nodes = d.nodes ?? []
        let thresholds = ResearchRules.nodeThresholds(d)
        var done = ctx.world.research.nodesDone[id] ?? 0
        while done < nodes.count, now >= thresholds[done] * ResearchState.unitsPerPoint {
            let node = nodes[done]
            ctx.world.research.nodesDone[id] = done + 1
            let rec = ctx.record(.researched, .research(id), actor: lead,
                                 detail: ["node": .int(Int64(done)), "nodeID": .string(node.id)])
            EffectApplier.apply((node.unlocks ?? []).map { .unlock(target: $0) } + (node.effects ?? []), &ctx,
                                cause: rec)
            ctx.emit(.researchNode(research: id, node: done, record: rec))
            done += 1
        }

        if now >= total {
            ctx.world.research.completed.insert(id)
            ctx.world.research.active = nil
            let rec = ctx.record(.researched, .research(id), actor: lead)
            EffectApplier.apply(d.unlocks.map { .unlock(target: $0) } + (d.effects ?? []), &ctx, cause: rec)
            ctx.emit(.researchCompleted(research: id, record: rec))
        }
    }

    private func advanceSkills(_ ctx: inout StepContext) {
        for p in ctx.world.research.learning.keys.sorted() {
            guard let l = ctx.world.research.learning[p] else { continue }
            guard let ps = ctx.world.people[p], ps.presence.isAlive, let d = ctx.content.skills[l.skill] else {
                ctx.world.research.learning[p] = nil
                continue
            }
            guard ResearchRules.skillAdvances(d, ps, ctx.world, ctx.content) else { continue }
            let next = l.progress + Int(SimStep.gameSeconds) * 1000
            if next >= ResearchRules.skillUnits(d) {
                ctx.world.research.learning[p] = nil
                acquire(p, l.skill, d, &ctx)
            } else {
                ctx.world.research.learning[p]?.progress = next
            }
        }
    }

    /// スキルが身につく。来歴を残し、解禁と効果を当て、`.skillAcquired` を出す(人の担当が skills に入れる)。
    private func acquire(_ p: PersonID, _ s: SkillID, _ d: SkillDef, _ ctx: inout StepContext) {
        let rec = ctx.record(.acquiredSkill, .skill(s), actor: p, place: ctx.world.people[p]?.position)
        EffectApplier.apply((d.unlocks ?? []).map { .unlock(target: $0) } + (d.effects ?? []), &ctx, cause: rec)
        ctx.emit(.skillAcquired(person: p, skill: s, record: rec))
        ctx.changes.mark([.research, .people])
    }

    // MARK: 反応

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        switch event {
        case .personDied(let p, _), .personLeft(let p, _):
            if let l = ctx.world.research.learning[p] {
                ctx.world.research.skillProgress[p, default: [:]][l.skill] = l.progress
                ctx.world.research.learning[p] = nil
            }
            ctx.world.research.nightSessions[p] = nil
        default: break
        }
    }
}
