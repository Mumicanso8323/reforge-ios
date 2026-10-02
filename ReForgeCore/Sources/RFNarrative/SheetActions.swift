import RFContent
import RFKernel
import RFRules
import RFWorld

/// 工程表の操作(U15。結合設計 BEAT-05・06・07・29)。どの操作も来歴に残り、出来事(hook)を出す。
/// 開示の本体はコンテンツの出来事が hook と条件 `sheet` で受けて、世界を変える(REQ-S2)。
///
/// - 開く(BEAT-05): 記録の並び・記録の 1 件・空いた席。空いた席を開いたことも数える。hook "sheet.opened"。
/// - 工程表(BEAT-06): 技能の付与は `.skillAcquired` を出す(書くのは RFCrew。思想の賛否も RFCrew が印で出す)。
///   使わないと決めた・本人が断ったは hook "grant.declined"(これも賛否の対象)。
/// - 答え(BEAT-07): 行に来歴を置く。hook "sheet.answered"。
/// - 選ぶ表(BEAT-29): 仲間の言い分は条件が変わりうる出来事(hook)のときだけ見直す。言い分が変わると、本人が一言言い、
///   来歴に残る(actor = 本人)。確定すると hook "roster.confirmed"。
enum SheetActions {
    /// 選ぶ表の言い分を見直す hook(毎ステップは回さない)。
    static let rosterHooks: Set<String> = [
        "dawn", "relation", "memory", "person.joined", "person.left", "person.died", "sheet.opened", "decided", "fact",
    ]

    static func handle(_ c: NarrativeCommand, _ ctx: inout StepContext) -> CommandResult? {
        switch c {
        case .openSheet(let sid, let slot): return open(sid, slot, &ctx)
        case .grant(let sid, let person, let skill): return grant(sid, person, skill, &ctx)
        case .placeAnswer(let sid, let row, let rec): return placeAnswer(sid, row, rec, &ctx)
        case .setRosterPick(let sid, let person, let included): return setRosterPick(sid, person, included, &ctx)
        case .confirmRoster(let sid): return lock(sid, &ctx)
        default: return nil
        }
    }

    static func available(_ sid: SheetID, _ ctx: StepContext) -> SheetDef? {
        guard let def = ctx.content.sheets[sid],
              ConditionEvaluator.evaluatePure(def.when, world: ctx.world, content: ctx.content) == true else { return nil }
        return def
    }

    // MARK: 開く

    static func open(_ sid: SheetID, _ slot: Int?, _ ctx: inout StepContext) -> CommandResult {
        guard let def = available(sid, ctx) else { return .rejected(Rejection("reason.sheet.closed")) }
        var empty = false
        var person: PersonID?
        if let slot {
            if let e = SheetRules.entries(def, ctx.world, ctx.content).first(where: { $0.slot == slot }) {
                person = e.person
            } else if SheetRules.emptySlots(def, ctx.world, ctx.content).contains(slot) {
                empty = true
            } else {
                return .rejected(Rejection("reason.sheet.no_slot"))
            }
        }
        var detail: [String: Value] = [:]
        if let slot { detail["slot"] = .int(Int64(slot)) }
        if empty { detail["empty"] = .bool(true) }
        if let person { detail["person"] = .string(person.rawValue) }
        let rec = ctx.record(.analyzed, .sheet(sid), actor: .noah, detail: detail)
        ctx.world.narrative.updateSheet(sid) { p in
            if let slot { if empty { p.emptySeen.insert(slot) } else { p.openedSlots.insert(slot) } } else { p.openedIndex = true }
        }
        ctx.emit(.sheetOpened(sheet: sid, slot: slot, empty: empty, record: rec))
        ctx.changes.mark(.narrative)
        return .done
    }

    // MARK: 工程表

    static func grant(_ sid: SheetID, _ person: PersonID, _ skill: SkillID?, _ ctx: inout StepContext) -> CommandResult {
        guard let def = available(sid, ctx), let im = def.grant, SheetRules.grantOpen(im, ctx.world, ctx.content) else {
            return .rejected(Rejection("reason.grant.closed"))
        }
        guard SheetRules.grantTarget(im, person, ctx.world, ctx.content) else {
            return .rejected(Rejection("reason.grant.no_target"))
        }
        let prog = ctx.world.narrative.sheet(sid)
        guard let skill else {
            guard prog.declined[person] == nil else { return .rejected(Rejection("reason.grant.decided")) }
            return decline(sid, im, person, refused: false, &ctx)
        }
        guard im.skills.contains(skill) else { return .rejected(Rejection("reason.grant.no_skill")) }
        guard ctx.world.people[person]?.skills.contains(skill) == false else {
            return .rejected(Rejection("reason.grant.known"))
        }
        if prog.declined[person] == true { return .rejected(Rejection("reason.grant.refused")) }
        if SheetRules.refuses(im, person, ctx.world, ctx.content) {
            // 本人が断る: 付けない。断ったことが来歴に残る
            return decline(sid, im, person, refused: true, &ctx)
        }
        let rec = ctx.record(.used, .person(person), actor: .noah, tags: Set(im.tags ?? []),
                             detail: ["sheet": .string(sid.rawValue), "skill": .string(skill.rawValue)])
        ctx.world.narrative.updateSheet(sid) { p in
            p.granted[person, default: []].append(skill)
            p.declined[person] = nil
        }
        ctx.emit(.skillAcquired(person: person, skill: skill, record: rec))
        ctx.changes.mark(.narrative)
        return .done
    }

    static func decline(_ sid: SheetID, _ im: SkillGrantDef, _ person: PersonID, refused: Bool,
                        _ ctx: inout StepContext) -> CommandResult {
        let rec = ctx.record(.kept, .person(person), actor: refused ? person : .noah, tags: Set(im.declineTags ?? []),
                             detail: ["sheet": .string(sid.rawValue), "refused": .bool(refused)])
        ctx.world.narrative.updateSheet(sid) { $0.declined[person] = refused }
        ctx.emit(.grantDeclined(sheet: sid, person: person, refused: refused, record: rec))
        if refused { Lines.say(context: "grant.refuse", speaker: person, &ctx, trigger: rec) }
        ctx.changes.mark(.narrative)
        return .done
    }

    // MARK: 答え

    static func placeAnswer(_ sid: SheetID, _ row: String, _ answer: ProvenanceID, _ ctx: inout StepContext) -> CommandResult {
        guard let def = available(sid, ctx), let r = def.rows.first(where: { $0.id == row }), r.answer != nil else {
            return .rejected(Rejection("reason.sheet.no_row"))
        }
        if let c = r.when, ConditionEvaluator.evaluatePure(c, world: ctx.world, content: ctx.content) != true {
            return .rejected(Rejection("reason.sheet.no_row"))
        }
        guard let ar = ctx.world.ledger.record(answer), SheetRules.accepts(r, ar) else {
            return .rejected(Rejection("reason.sheet.not_an_answer"))
        }
        let rec = ctx.record(.chose, .sheet(sid), actor: .noah, inputs: [answer], tags: ar.tags,
                             detail: ["row": .string(row)])
        ctx.world.narrative.updateSheet(sid) { $0.answers[row] = answer }
        ctx.emit(.answerPlaced(sheet: sid, row: row, record: rec))
        ctx.changes.mark(.narrative)
        return .done
    }

    // MARK: 選ぶ表

    static func roster(_ sid: SheetID, _ ctx: StepContext) -> RosterDef? {
        guard let def = available(sid, ctx), let m = def.roster else { return nil }
        if let c = m.when, ConditionEvaluator.evaluatePure(c, world: ctx.world, content: ctx.content) != true { return nil }
        return m
    }

    static func setRosterPick(_ sid: SheetID, _ person: PersonID, _ included: Bool, _ ctx: inout StepContext) -> CommandResult {
        guard let m = roster(sid, ctx) else { return .rejected(Rejection("reason.roster.closed")) }
        let prog = ctx.world.narrative.sheet(sid)
        guard prog.locked == nil else { return .rejected(Rejection("reason.roster.confirmed")) }
        guard SheetRules.candidates(ctx.world).contains(person) else { return .rejected(Rejection("reason.roster.no_one")) }
        if let l = SheetRules.leaning(m, person, ctx.world, ctx.content), l.firm == true, l.included != included {
            Lines.say(context: l.line ?? (l.included ? "roster.include" : "roster.exclude"), speaker: person, &ctx)
            return .rejected(Rejection("reason.roster.firm"))
        }
        if included, !prog.included(person), let cap = m.capacity, SheetRules.includedList(prog, ctx.world).count >= cap {
            return .rejected(Rejection("reason.roster.full"))
        }
        ctx.record(.chose, .person(person), actor: .noah,
                   detail: ["sheet": .string(sid.rawValue), "included": .bool(included)])
        ctx.world.narrative.updateSheet(sid) { $0.chosen[person] = included }
        ctx.changes.mark(.narrative)
        return .done
    }

    static func lock(_ sid: SheetID, _ ctx: inout StepContext) -> CommandResult {
        guard roster(sid, ctx) != nil else { return .rejected(Rejection("reason.roster.closed")) }
        let prog = ctx.world.narrative.sheet(sid)
        guard prog.locked == nil else { return .rejected(Rejection("reason.roster.confirmed")) }
        let included = SheetRules.includedList(prog, ctx.world)
        guard !included.isEmpty else { return .rejected(Rejection("reason.roster.empty")) }
        let rec = ctx.record(.chose, .sheet(sid), actor: .noah,
                             detail: ["included": .array(included.map { .string($0.rawValue) }),
                                      "excluded": .array(SheetRules.candidates(ctx.world).filter { !prog.included($0) }
                                          .map { .string($0.rawValue) })])
        ctx.world.narrative.updateSheet(sid) { $0.locked = rec }
        ctx.emit(.rosterConfirmed(sheet: sid, record: rec))
        ctx.changes.mark(.narrative)
        return .done
    }

    /// 仲間の言い分を見直す(選ぶ表の開いている表だけ。締めた後は変えない)。
    static func refreshDeclarations(hook: String, _ ctx: inout StepContext) {
        guard rosterHooks.contains(hook) else { return }
        for (sid, def) in ctx.content.sheets.sorted(by: { $0.key < $1.key }) where def.roster != nil {
            guard ctx.world.narrative.sheet(sid).locked == nil, let m = roster(sid, ctx) else { continue }
            for person in SheetRules.candidates(ctx.world) where person != .noah {
                guard let l = SheetRules.leaning(m, person, ctx.world, ctx.content) else { continue }
                guard ctx.world.narrative.sheet(sid).declared[person] != l.included else { continue }
                let rec = ctx.record(.chose, .sheet(sid), actor: person,
                                     detail: ["included": .bool(l.included), "firm": .bool(l.firm == true)])
                ctx.world.narrative.updateSheet(sid) { $0.declared[person] = l.included }
                ctx.emit(.rosterDeclared(sheet: sid, person: person, included: l.included, record: rec))
                Lines.say(context: l.line ?? (l.included ? "roster.include" : "roster.exclude"), speaker: person, &ctx,
                          trigger: rec)
                ctx.changes.mark(.narrative)
            }
        }
    }
}
