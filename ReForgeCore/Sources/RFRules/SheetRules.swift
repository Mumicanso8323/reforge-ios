import RFContent
import RFKernel
import RFWorld

/// 工程表の規則(U15。結合設計 BEAT-05・06・07・29 / REQ-S8)。条件・本体・画面が共通に使う、乱数を使わない問い合わせ。
///
/// - 記録の並び: 席 1...slots のうち、entries に無い番号は「空いた席」。空いた席は数えられ、開ける(開いたことが来歴に残る)。
/// - 答えの席: 行に、プレイヤー自身の来歴を 1 つ置く。置ける来歴は AnswerSlotDef.accepts のどれかに合うもの。
/// - 工程表: 付けられる人・本人が断るかは PersonTest で決める(思想・関係・記憶)。
/// - 選ぶ表: 仲間の言い分は LeaningDef の上から順に、tests に全部合う最初のもの。
public enum SheetRules {
    // MARK: 条件

    public static func test(_ t: SheetTest, _ p: SheetProgress, _ w: WorldState) -> Bool {
        switch t {
        case .opened(let slot):
            return slot.map { p.openedSlots.contains($0) || p.emptySeen.contains($0) } ?? p.openedIndex
        case .emptySlotsSeen(let n): return p.emptySeen.count >= n
        case .answered(let row, let q):
            guard let rec = p.answers[row] else { return false }
            guard let q else { return true }
            return w.ledger.record(rec).map { ProvenanceQueries.matches(q, $0) } ?? false
        case .granted(let person, let n):
            let who = person.map { p.granted[$0] != nil ? 1 : 0 } ?? p.granted.count
            return who >= (n ?? 1)
        case .declined(let person, let n):
            let who = person.map { p.declined[$0] != nil ? 1 : 0 } ?? p.declined.count
            return who >= (n ?? 1)
        case .included(let person, let n):
            if let person { return p.included(person) && isPresent(person, w) }
            return includedList(p, w).count >= (n ?? 1)
        case .excluded(let person, let n):
            if let person { return !p.included(person) && isPresent(person, w) }
            return candidates(w).filter { !p.included($0) }.count >= (n ?? 1)
        case .locked: return p.locked != nil
        }
    }

    // MARK: 記録の並び

    /// 並びに出ている記録(席の順)。
    public static func entries(_ def: SheetDef, _ w: WorldState, _ c: ContentDB) -> [SheetEntryDef] {
        (def.entries ?? []).filter { e in
            e.when.map { ConditionEvaluator.evaluatePure($0, world: w, content: c) == true } ?? true
        }.sorted { $0.slot < $1.slot }
    }

    /// 空いた席の番号(並びに記録の無い番号)。
    public static func emptySlots(_ def: SheetDef, _ w: WorldState, _ c: ContentDB) -> [Int] {
        guard let n = def.slots, n > 0 else { return [] }
        let filled = Set(entries(def, w, c).map(\.slot))
        return (1...n).filter { !filled.contains($0) }
    }

    // MARK: 答えと数

    /// この行に置ける来歴(新しい順)。
    public static func answerCandidates(_ row: SheetDef.Row, _ w: WorldState) -> [ProvenanceRecord] {
        guard let a = row.answer else { return [] }
        return w.ledger.records.filter { r in a.accepts.contains { ProvenanceQueries.matches($0, r) } }.reversed()
    }

    public static func accepts(_ row: SheetDef.Row, _ r: ProvenanceRecord) -> Bool {
        row.answer?.accepts.contains { ProvenanceQueries.matches($0, r) } ?? false
    }

    /// 行の横の数。
    public static func measure(_ m: SheetMeasure, _ w: WorldState) -> Int {
        switch m {
        case .count(let q): return ProvenanceQueries.count(q, in: w)
        case .maxDetail(let q, let key):
            return w.ledger.records.filter { ProvenanceQueries.matches(q, $0) }.compactMap { r -> Int? in
                if case .int(let v)? = r.detail[key] { return Int(v) }
                return nil
            }.max() ?? 0
        }
    }

    // MARK: 工程表

    public static func grantOpen(_ im: SkillGrantDef, _ w: WorldState, _ c: ContentDB) -> Bool {
        im.when.map { ConditionEvaluator.evaluatePure($0, world: w, content: c) == true } ?? true
    }

    /// 書き足せる人か(一員で生きていて、targets に全部合う)。
    public static func grantTarget(_ im: SkillGrantDef, _ person: PersonID, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let ps = w.people[person], ps.presence.isMember, ps.presence.isAlive else { return false }
        return (im.targets ?? []).allSatisfy { ConditionEvaluator.testPerson(ps, $0, w, c) }
    }

    /// 本人が断るか。
    public static func refuses(_ im: SkillGrantDef, _ person: PersonID, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let rw = im.refuseWhen, !rw.isEmpty else { return false }
        return rw.allSatisfy { ConditionEvaluator.testPerson(w.people[person], $0, w, c) }
    }

    // MARK: 選ぶ表

    /// 選ぶ表の対象者(ノアと、生きている一員)。
    public static func candidates(_ w: WorldState) -> [PersonID] {
        w.people.order.filter { isPresent($0, w) }
    }

    static func isPresent(_ p: PersonID, _ w: WorldState) -> Bool {
        guard let ps = w.people[p] else { return false }
        return ps.presence.isAlive && (p == .noah || ps.presence.isMember)
    }

    public static func includedList(_ p: SheetProgress, _ w: WorldState) -> [PersonID] {
        candidates(w).filter { p.included($0) }
    }

    /// 仲間の言い分(nil = 何も言わない)。ノアは言わない(プレイヤーが決める)。
    public static func leaning(_ m: RosterDef, _ person: PersonID, _ w: WorldState, _ c: ContentDB) -> LeaningDef? {
        guard person != .noah, let ps = w.people[person] else { return nil }
        return m.leanings.first { l in l.tests.allSatisfy { ConditionEvaluator.testPerson(ps, $0, w, c) } }
    }
}

/// 拠点の段階(条件が読む)。格 n は、1...n の条件が全部成り立つとき。保存した格(world.base.grade)より下がらない。
public enum BaseGrades {
    public static func current(_ w: WorldState, _ c: ContentDB) -> Int {
        var g = 1
        for d in (c.base.grades ?? []).sorted(by: { $0.grade < $1.grade }) where d.grade > g {
            guard ConditionEvaluator.evaluatePure(d.when, world: w, content: c) == true else { break }
            g = d.grade
        }
        return max(g, w.base.grade)
    }
}
