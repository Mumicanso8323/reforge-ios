import RFContent
import RFKernel
import RFMap
import RFMatter
import RFWorld

/// 効果の適用。持ち主: RFNarrative の担当(新しい効果の case を足したら、ここに適用を足す)。
///
/// - 世界の切れ端を直接変えてよい効果(事実・数・関係・記憶・範囲・印…)はここで変える。
/// - システムの計算が要る効果(戦闘の開始・敵を出す)はコマンドにして ctx.queue に積む(そのシステムが処理する)。
/// - どの効果も、変化を来歴に残す(inputs に ctx.cause = 引き金)。
/// - まだ仕組みの無い効果は ctx.warnings に残す(黙って捨てない)。
public enum EffectApplier {
    public static func apply(_ effects: [Effect], _ ctx: inout StepContext, cause: ProvenanceID?) {
        let saved = ctx.cause
        ctx.cause = cause
        defer { ctx.cause = saved }
        for e in effects { apply(e, &ctx) }
    }

    static func apply(_ e: Effect, _ ctx: inout StepContext) {
        let w = ctx.world
        switch e {
        case .learn(let f):
            ctx.learn(f, via: ctx.cause)

        case .give(let item, let matter, let n, let unique):
            let stuff: Stuff
            if let m = matter { stuff = .matter(m) } else if let i = item { stuff = .item(i) } else {
                ctx.warnings.append("give: item も matter も無い")
                return
            }
            let subject: SubjectRef = item.map { .item($0) } ?? .none
            let rec = ctx.record(.discovered, subject, detail: ["quantity": .int(Int64(n))])
            if unique == true {
                for _ in 0..<n { ctx.addStock(stuff, 1, to: .base, origin: rec, unique: ctx.world.newEntityID()) }
            } else {
                ctx.addStock(stuff, n, to: .base, origin: rec)
            }

        case .take(let ing):
            _ = ctx.takeStock(ing.quantity, from: .base, where: ing.matches)

        case .counter(let id, let add):
            ctx.world.narrative.counters[id, default: 0] += add
            ctx.changes.mark(.narrative)
        case .setCounter(let id, let v):
            ctx.world.narrative.counters[id] = v
            ctx.changes.mark(.narrative)
        case .stat(let id, let add):
            ctx.world.survival.stats[id, default: .zero] = ctx.world.survival.stats[id, default: .zero] + Milli(raw: Int64(add))
            ctx.changes.mark(.survival)

        case .relation(let p, let add):
            guard var ps = w.people[p] else { return missing(&ctx, e) }
            ps.relation.points += add
            ctx.world.people[p] = ps
            ctx.emit(.relationChanged(person: p, rank: ps.relation.rank, delta: add))
        case .ideology(let p, let axis, let add):
            guard var ps = w.people[p] else { return missing(&ctx, e) }
            ps.ideology[axis, default: 0] += add
            ctx.world.people[p] = ps
        case .remember(let p, let kind, let persists):
            guard var ps = w.people[p] else { return missing(&ctx, e) }
            ps.memories.append(MemoryRecord(kind: kind, at: w.clock.now, run: w.run.index, about: ctx.cause,
                                            persistsAcrossRewind: persists))
            ctx.world.people[p] = ps
            ctx.emit(.memoryFormed(person: p, kind: kind))

        case .overrideAssignment(let p, let toward, let hours):
            guard var ps = w.people[p] else { return missing(&ctx, e) }
            let rec = ctx.record(.overridden, .person(p))
            var a = Assignment.idle
            if let t = toward, let at = Places.resolve(t, world: w, trigger: ctx.cause) {
                a = .guardArea(center: at, radius: 1)
            }
            ps.override = AssignmentOverride(assignment: a, aura: nil,
                                             until: hours.map { w.clock.now + .hours($0) }, origin: rec)
            ctx.world.people[p] = ps
            ctx.changes.mark(.people)
        case .clearOverride(let p):
            ctx.world.people[p]?.override = nil
            ctx.changes.mark(.people)

        case .addAura(let kind, let at, let radius, let hours):
            let source: Aura.Source
            switch at {
            case .person(let id): source = .person(id)
            default:
                guard let pt = Places.resolve(at, world: w, trigger: ctx.cause) else { return missing(&ctx, e) }
                source = .point(pt)
            }
            let id = ctx.world.newEntityID()
            let rec = ctx.record(.overridden, .aura(kind, id))
            ctx.world.auras.active[id] = Aura(id: id, kind: kind, source: source, radius: radius, origin: rec,
                                              until: hours.map { w.clock.now + .hours($0) })
            ctx.changes.mark([.people, .fog])
        case .scaleAura(let kind, let permille):
            for (id, a) in w.auras.active where a.kind == kind {
                let s = a.strength * permille / 1000
                if s <= 0 { ctx.world.auras.active[id] = nil } else { ctx.world.auras.active[id]?.strength = s }
            }
        case .removeAura(let kind):
            ctx.world.auras.active = w.auras.active.filter { $0.value.kind != kind }

        case .tagRecords(let q, let tag):
            for r in w.ledger.records where ProvenanceQueries.matches(q, r, run: w.run.index) {
                ctx.world.ledger.update(r.id) { $0.tags.insert(tag) }
            }

        case .unlock(let t):
            switch t {
            case .module(let id): ctx.world.research.unlocked.modules.insert(id)
            case .structure(let id): ctx.world.research.unlocked.structures.insert(id)
            case .handwork(let id): ctx.world.research.unlocked.handwork.insert(id)
            case .interaction(let id): ctx.world.research.unlocked.interactions.insert(id)
            case .research(let id): ctx.world.research.unlocked.research.insert(id)
            }
            ctx.emit(.unlocked(what: "\(t)"))
            ctx.changes.mark(.research)

        case .startBattle(let enemy, let count, let near):
            guard let at = Places.resolve(near, world: w, trigger: ctx.cause) else { return missing(&ctx, e) }
            ctx.queue(.combat(.startBattle(enemy: enemy, count: count, near: at)))

        case .startScene(let scene):
            ctx.world.narrative.scene = SceneProgress(scene: scene)
            ctx.emit(.sceneStarted(scene: scene))
            ctx.changes.mark(.narrative)
        case .schedule(let ev, let minutes):
            ctx.world.narrative.scheduled.append(ScheduledEvent(event: ev, at: w.clock.now + .minutes(minutes)))
        case .objective(let id, let st):
            let status = ObjectiveStatus(rawValue: st.rawValue) ?? .active
            ctx.world.narrative.objectives[id] = status
            ctx.emit(.objectiveChanged(objective: id, status: status))
            ctx.changes.mark(.narrative)
        case .chapter(let id):
            let rec = ctx.record(.chapterEnded, .none, detail: ["chapter": .string(id.rawValue)])
            if let old = w.narrative.chapter { ctx.emit(.chapterEnded(chapter: old, record: rec)) }
            ctx.world.narrative.chapter = id
        case .ending(let id):
            ctx.world.narrative.ending = id
            ctx.world.run.outcome = .ended(id)
            ctx.emit(.endingReached(ending: id))
            ctx.changes.mark(.run)

        // 以下は担当のシステムが仕組みを入れたら、ここで適用する(またはコマンドにする)
        case .meet, .join, .leave, .die, .injure:
            pending(&ctx, e, owner: "RFCrew")
        case .revealMap, .setTerrain:
            pending(&ctx, e, owner: "RFExploration")
        case .spawnEnemy:
            pending(&ctx, e, owner: "RFCombat")
        case .convertPlacements:
            pending(&ctx, e, owner: "RFProduction")
        case .setPart:
            pending(&ctx, e, owner: "RFExploration")
        }
    }

    private static func missing(_ ctx: inout StepContext, _ e: Effect) {
        ctx.warnings.append("効果の対象が無い: \(e)")
    }

    private static func pending(_ ctx: inout StepContext, _ e: Effect, owner: String) {
        ctx.warnings.append("未実装の効果(\(owner) の担当): \(e)")
    }
}
