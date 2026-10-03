import RFContent
import RFKernel
import RFMap
import RFMatter
import RFWorld

/// 効果の適用。持ち主: U11(新しい効果の case を足したら、ここに適用を足す)。
///
/// - 出来事の切れ端(narrative・auras)と共通の操作(事実・在庫・来歴の印)、それに出来事のために境界が開けてある
///   人の項目(関係・思想・記憶・配属の上書き)と集団の関係はここで変える。
/// - 他のシステムの計算が要る効果(人の合流と離脱・地形・部品・敵・戦闘・置いた物の変換・出来事をすぐ起こす)は、
///   そのシステムへのコマンドにして ctx.queue に積む(cause = 引き金の来歴を持たせる)。
/// - どの効果も、変化を来歴に残す(inputs に ctx.cause = 引き金)。
/// - 対象が無い効果は ctx.warnings に残す(黙って捨てない)。
public enum EffectApplier {
    public static func apply(_ effects: [Effect], _ ctx: inout StepContext, cause: ProvenanceID?) {
        let saved = ctx.cause
        ctx.cause = cause
        defer { ctx.cause = saved }
        for e in effects { apply(e, &ctx) }
    }

    static func apply(_ e: Effect, _ ctx: inout StepContext) {
        let w = ctx.world
        let cause = ctx.cause
        func resolve(_ p: PlaceSelector) -> WorldPoint? { Places.resolve(p, world: w, trigger: cause) }
        switch e {
        case .learn(let f):
            ctx.learn(f, via: cause)

        // MARK: 物
        case .give(let item, let matter, let n, let unique, let attributes):
            let stuff: Stuff
            if let m = matter { stuff = .matter(m) } else if let i = item { stuff = .item(i) } else {
                ctx.warnings.append("give: item も matter も無い")
                return
            }
            let subject: SubjectRef = item.map { .item($0) } ?? .none
            let rec = ctx.record(.discovered, subject, detail: ["quantity": .int(Int64(n))])
            if unique == true {
                for _ in 0..<n {
                    ctx.addStock(stuff, 1, to: .base, origin: rec, unique: ctx.world.newEntityID(), attributes: attributes)
                }
            } else {
                ctx.addStock(stuff, n, to: .base, origin: rec, attributes: attributes)
            }
        case .take(let ing):
            guard let took = ctx.takeStock(ing.quantity, from: .base, where: ing.matches) else {
                ctx.warnings.append("take: 足りない \(ing)")
                return
            }
            ctx.record(.consumed, ing.item.map { .item($0) } ?? .none, inputs: took.keys.sorted(),
                       detail: ["quantity": .int(Int64(ing.quantity))])

        // MARK: 数
        case .counter(let id, let add):
            ctx.world.narrative.counters[id, default: 0] += add
            ctx.changes.mark(.narrative)
        case .setCounter(let id, let v):
            ctx.world.narrative.counters[id] = v
            ctx.changes.mark(.narrative)
        case .stat(let id, let add):
            ctx.world.survival.stats[id, default: .zero] = ctx.world.survival.stats[id, default: .zero] + Milli(raw: Int64(add))
            ctx.changes.mark(.survival)
        case .setStat(let id, let v):
            ctx.world.survival.stats[id] = Milli(raw: Int64(v))
            ctx.changes.mark(.survival)

        // MARK: 人
        case .relation(let p, let add):
            guard w.people[p] != nil else { return missing(&ctx, e) }
            // 点の増減とランクの直しは RelationState.add の 1 か所。ランクが上がったら、その場で知らせる
            let up = ctx.world.people[p]?.relation.add(add) ?? 0
            if up > 0, let rank = ctx.world.people[p]?.relation.rank {
                ctx.emit(.relationChanged(person: p, rank: rank, delta: add))
            }
            ctx.changes.mark(.people)
        case .ideology(let p, let axis, let add):
            guard var ps = w.people[p] else { return missing(&ctx, e) }
            ps.ideology[axis, default: 0] += add
            ctx.world.people[p] = ps
            ctx.changes.mark(.people)
        case .remember(let p, let kind, let persists):
            guard var ps = w.people[p] else { return missing(&ctx, e) }
            ps.memories.append(MemoryRecord(kind: kind, at: w.clock.now, run: w.run.index, about: cause,
                                            persistsAcrossRewind: persists))
            ctx.world.people[p] = ps
            ctx.emit(.memoryFormed(person: p, kind: kind))
        case .meet(let p, let at):
            guard w.people[p] != nil else { return missing(&ctx, e) }
            ctx.queue(.crew(.meetFromEffect(person: p, at: resolve(at), cause: cause)))
        case .join(let p):
            guard w.people[p] != nil else { return missing(&ctx, e) }
            ctx.queue(.crew(.joinFromEffect(person: p, cause: cause)))
        case .leave(let p):
            guard w.people[p] != nil else { return missing(&ctx, e) }
            ctx.queue(.crew(.leaveFromEffect(person: p, cause: cause)))
        case .die(let p, let reason):
            guard w.people[p] != nil else { return missing(&ctx, e) }
            ctx.queue(.crew(.dieFromEffect(person: p, reason: reason, cause: cause)))
        case .injure(let p, let amount):
            guard w.people[p] != nil else { return missing(&ctx, e) }
            ctx.queue(.crew(.injureFromEffect(person: p, amount: amount, cause: cause)))
        case .overrideAssignment(let p, let toward, let hours):
            guard var ps = w.people[p] else { return missing(&ctx, e) }
            let rec = ctx.record(.overridden, .person(p), place: ps.position)
            var a = Assignment.idle
            if let t = toward {
                if case .person(let other) = t { a = .follow(person: other) } else if let at = resolve(t) {
                    a = .guardArea(center: at, radius: 1)
                }
            }
            ps.override = AssignmentOverride(assignment: a, aura: nil, until: hours.map { w.clock.now + .hours($0) }, origin: rec)
            ctx.world.people[p] = ps
            ctx.emit(.assigned(person: p, assignment: a))
            ctx.changes.mark(.people)
        case .clearOverride(let p):
            guard let ps = w.people[p] else { return missing(&ctx, e) }
            ctx.world.people[p]?.override = nil
            ctx.emit(.assigned(person: p, assignment: ps.assignment))
            ctx.changes.mark(.people)
        case .selfBuild(let p, let structure, let near, let radius):
            guard let at = resolve(near) else { return missing(&ctx, e) }
            ctx.queue(.base(.selfBuild(person: p, structure: structure, near: at, radius: radius ?? 3, cause: cause)))
        case .say(let context, let speaker):
            Lines.say(context: context, speaker: speaker, &ctx, trigger: cause)

        // MARK: 集団
        case .groupRelation(let g, let add):
            ctx.world.people.groups[g, default: GroupState()].relation += add
            ctx.changes.mark(.people)
        case .groupFlag(let g, let flag, let on):
            if on { ctx.world.people.groups[g, default: GroupState()].flags.insert(flag) } else {
                ctx.world.people.groups[g]?.flags.remove(flag)
            }
            ctx.changes.mark(.people)

        // MARK: 範囲の効果
        case .addAura(let kind, let at, let radius, let hours, let strength):
            let source: Aura.Source
            switch at {
            case .person(let id):
                guard w.people[id] != nil else { return missing(&ctx, e) }
                source = .person(id)
            case .placement(let m, let s):
                guard let pl = Places.placement(m, s, in: w) else { return missing(&ctx, e) }
                source = .placement(pl)
            case .trigger where Places.triggerPlacement(cause, in: w) != nil:
                source = .placement(Places.triggerPlacement(cause, in: w)!)
            default:
                guard let pt = resolve(at) else { return missing(&ctx, e) }
                source = .point(pt)
            }
            let scale = w.auras.kindScale[kind] ?? AuraScale()
            let r = (radius ?? ctx.content.auras[kind]?.radius ?? 0) * scale.radius / 1000
            let id = ctx.world.newEntityID()
            let rec = ctx.record(.overridden, .aura(kind, id))
            ctx.world.auras.active[id] = Aura(id: id, kind: kind, source: source, radius: r,
                                              strength: (strength ?? 1000) * scale.strength / 1000, origin: rec,
                                              until: hours.map { w.clock.now + .hours($0) })
            ctx.changes.mark([.people, .fog])
        case .scaleAura(let kind, let permille, let radiusPermille):
            var scale = w.auras.kindScale[kind] ?? AuraScale()
            scale.strength = scale.strength * permille / 1000
            scale.radius = scale.radius * (radiusPermille ?? 1000) / 1000
            ctx.world.auras.kindScale[kind] = scale
            for (id, a) in w.auras.active.sorted(by: { $0.key < $1.key }) where a.kind == kind {
                let s = a.strength * permille / 1000
                if s <= 0 {
                    ctx.world.auras.active[id] = nil
                } else {
                    ctx.world.auras.active[id]?.strength = s
                    ctx.world.auras.active[id]?.radius = a.radius * (radiusPermille ?? 1000) / 1000
                }
            }
            ctx.record(.overridden, .aura(kind, nil), detail: ["permille": .int(Int64(permille)),
                                                               "radiusPermille": .int(Int64(radiusPermille ?? 1000))])
            ctx.changes.mark([.people, .fog])
        case .removeAura(let kind):
            ctx.world.auras.active = w.auras.active.filter { $0.value.kind != kind }
            ctx.record(.overridden, .aura(kind, nil), detail: ["removed": .bool(true)])
            ctx.changes.mark([.people, .fog])

        // MARK: 有限の部品・地図・敵・置いた物(持ち主のシステムへ)
        case .setPart(let kind, let part, let state):
            guard let poi = firstPOI(kind, w) else { return missing(&ctx, e) }
            let act: ActKind = state == .rebuilt ? .rebuiltPart : .salvagedPart
            let ps: PartState
            switch state {
            case .intact: ps = .intact
            case .salvaged: ps = .salvaged(record: ctx.record(act, .part(poi, part)))
            case .dismantled: ps = .dismantled(record: ctx.record(act, .part(poi, part)))
            case .rebuilt: ps = .rebuilt(record: ctx.record(act, .part(poi, part)))
            }
            ctx.queue(.exploration(.setPart(poi: poi, part: part, state: ps)))
        case .revealMap(let around, let radius):
            guard let at = resolve(around) else { return missing(&ctx, e) }
            ctx.queue(.exploration(.revealMap(around: at, radius: radius, cause: cause)))
        case .setTerrain(let place, let terrain):
            guard let at = resolve(place) else { return missing(&ctx, e) }
            ctx.queue(.exploration(.setTerrain(at: at, terrain: terrain, cause: cause)))
        case .spawnEnemy(let kind, let count, let near):
            guard let at = resolve(near) else { return missing(&ctx, e) }
            ctx.queue(.combat(.spawnEnemy(kind: kind, count: count, near: at, cause: cause)))
        case .startBattle(let enemy, let count, let near):
            guard let at = resolve(near) else { return missing(&ctx, e) }
            ctx.queue(.combat(.startBattle(enemy: enemy, count: count, near: at)))
        case .convertPlacements(let from, let to):
            ctx.queue(.production(.convertPlacements(from: from, to: to, cause: cause)))

        // MARK: 来歴の印・解禁
        case .tagRecords(let q, let tag):
            for r in w.ledger.records where ProvenanceQueries.matches(q, r) {
                ctx.world.ledger.update(r.id) { $0.tags.insert(tag) }
            }
            ctx.changes.mark(.perception)
        case .unlock(let t):
            switch t {
            case .module(let id): ctx.world.research.unlocked.modules.insert(id)
            case .structure(let id): ctx.world.research.unlocked.structures.insert(id)
            case .handwork(let id): ctx.world.research.unlocked.handwork.insert(id)
            case .interaction(let id): ctx.world.research.unlocked.interactions.insert(id)
            case .research(let id): ctx.world.research.unlocked.research.insert(id)
            }
            ctx.emit(.unlocked(what: unlockKey(t)))
            ctx.changes.mark(.research)

        // MARK: 物語
        case .startScene(let scene):
            var first = 0
            let lines = ctx.content.scenes[scene]?.lines ?? []
            while first < lines.count, let c = lines[first].when,
                  ConditionEvaluator.evaluatePure(c, world: ctx.world, content: ctx.content, trigger: cause) != true {
                first += 1
            }
            guard first < lines.count else { return }
            ctx.world.narrative.scene = SceneProgress(scene: scene, line: first, lineSince: w.clock.now, origin: cause)
            ctx.emit(.sceneStarted(scene: scene))
            ctx.changes.mark(.narrative)
        case .schedule(let ev, let minutes):
            ctx.world.narrative.scheduled.append(ScheduledEvent(event: ev, at: w.clock.now + .minutes(minutes), cause: cause))
            ctx.changes.mark(.narrative)
        case .unschedule(let ev):
            ctx.world.narrative.scheduled.removeAll { $0.event == ev }
            ctx.changes.mark(.narrative)
        case .fire(let ev):
            ctx.queue(.narrative(.fireFromEffect(event: ev, cause: cause)))
        case .objective(let id, let st):
            let status = ObjectiveStatus(rawValue: st.rawValue) ?? .active
            guard w.narrative.objectives[id] != status else { return }
            ctx.world.narrative.objectives[id] = status
            ctx.emit(.objectiveChanged(objective: id, status: status))
            ctx.changes.mark(.narrative)
        case .chapter(let id):
            guard w.narrative.chapter != id else { return }
            let rec = ctx.record(.chapterEnded, .none, detail: ["chapter": .string(id.rawValue)])
            if let old = w.narrative.chapter { ctx.emit(.chapterEnded(chapter: old, record: rec)) }
            ctx.world.narrative.chapter = id
            ctx.changes.mark(.narrative)
        case .ending(let id):
            guard w.narrative.ending == nil else { return }
            ctx.world.narrative.ending = id
            ctx.world.run.outcome = .ended(id)
            ctx.emit(.endingReached(ending: id))
            ctx.changes.mark([.narrative, .run])

        // MARK: U16 置いた物を壊す・集団との戦い(持ち主のシステムへ)
        case .destroyPlacements(let near, let radius, let module, let structure, let max):
            guard let at = resolve(near) else { return missing(&ctx, e) }
            if structure == nil {
                ctx.queue(.production(.destroyFromEffect(near: at, radius: radius, module: module, max: max, cause: cause)))
            }
            if module == nil {
                ctx.queue(.base(.destroyFromEffect(near: at, radius: radius, structure: structure, max: max, cause: cause)))
            }
        case .groupBattle(let group, let place, let members, let lethal):
            guard let at = resolve(place) else { return missing(&ctx, e) }
            ctx.queue(.combat(.startGroupBattle(group: group, near: at, members: members, lethal: lethal ?? true,
                                                cause: cause)))
        case .beacon(let id, let place):
            guard let at = resolve(place) else { return missing(&ctx, e) }
            ctx.queue(.exploration(.setBeacon(id: id, at: at, cause: cause)))
        case .clearBeacon(let id):
            ctx.queue(.exploration(.setBeacon(id: id, at: nil, cause: cause)))
        case .hearth(let place, let op):
            guard let at = resolve(place), let target = Hearths.nearest(to: at, in: w, content: ctx.content)
            else { return missing(&ctx, e) }
            Hearths.applyEffect(op, to: target, &ctx)
        case .placeStructure(let kind, let place, let built):
            guard let at = resolve(place) else { return missing(&ctx, e) }
            if case .failure(let r) = StructureSites.placeFromEffect(kind, near: at, built: built, &ctx) {
                ctx.warnings.append("placeStructure: \(r.reason)")
            }
        }
    }

    /// その種類の POI のうち最初のもの(層・ID の順)。
    static func firstPOI(_ kind: POIKindID, _ w: WorldState) -> EntityID? {
        for (_, layer) in w.map.layers.sorted(by: { $0.key < $1.key }) {
            if let (id, _) = layer.pois.sorted(by: { $0.key < $1.key }).first(where: { $0.value.kind == kind }) { return id }
        }
        return nil
    }

    static func unlockKey(_ t: UnlockTarget) -> String {
        switch t {
        case .module(let id): "module:\(id)"
        case .structure(let id): "structure:\(id)"
        case .handwork(let id): "handwork:\(id)"
        case .interaction(let id): "interaction:\(id)"
        case .research(let id): "research:\(id)"
        }
    }

    private static func missing(_ ctx: inout StepContext, _ e: Effect) {
        ctx.warnings.append("効果の対象が無い: \(e)")
    }
}
