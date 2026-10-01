import RFContent
import RFKernel
import RFRules
import RFWorld

/// 研究とスキルの規則(状態を持たない関数だけ)。システムと問い合わせ(ResearchQueries)が共通に使う。
public enum ResearchRules {
    /// 夜作業の研究 1 回の時間(ゲーム時間)。
    public static let nightStudyHours = 2
    /// 同じ研究に付く人が増えたときの効き(原作 PackageManager: 100%・150%・185%・210% を、
    /// 速い人から順に 1000・500・350・250 の重みで足す形にした。5 人目からは足さない)。
    public static let crewWeights = [1000, 500, 350, 250]
    /// 力の元が足りないときの、足りない 1 あたりの傷(AbilityCost の既定)。
    public static let defaultHealthPerShortfall = 5

    // MARK: 見える・選べる

    /// 一覧に出してよいか(存在を伏せる研究は visibleWhen が成り立つまで出さない)。
    public static func isVisible(_ d: ResearchDef, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let v = d.visibleWhen else { return true }
        return ConditionEvaluator.evaluatePure(v, world: w, content: c) == true
    }

    /// 前提を満たしているか。
    public static func requirementsMet(_ d: ResearchDef, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let r = d.requires else { return true }
        return ConditionEvaluator.evaluatePure(r, world: w, content: c) == true
    }

    public static func isVisible(_ d: SkillDef, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let v = d.visibleWhen else { return true }
        return ConditionEvaluator.evaluatePure(v, world: w, content: c) == true
    }

    public static func requirementsMet(_ d: SkillDef, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard let r = d.requires else { return true }
        return ConditionEvaluator.evaluatePure(r, world: w, content: c) == true
    }

    // MARK: 研究机と、付いている人

    /// 研究の建造物(建ち終えて動いているもの。station を指定すればその種類だけ)。ID 順。
    public static func desks(_ w: WorldState, _ c: ContentDB, station: StructureKindID? = nil) -> [EntityID] {
        w.placements.sortedIDs.filter { id in
            guard let pl = w.placements.items[id], pl.status == .running, case .structure(let k) = pl.kind else {
                return false
            }
            if let s = station, s != k { return false }
            return c.researchRate(of: k) > 0
        }
    }

    /// その人が、その建造物で実際に作業しているか。
    /// - いまの動作が「その置いた物で作業中」なら作業している(人の担当がそう決めた)。
    /// - または、配属がその置いた物で、上書きされておらず、歩いておらず、隣のマスにいる。
    public static func isWorking(_ ps: PersonState, at desk: Placement) -> Bool {
        guard ps.presence.isMember else { return false }
        switch ps.activity {
        case .working(let e): return e == desk.id
        case .fighting, .sleeping, .talking, .walking, .carrying, .interacting: return false
        case .idle: break
        }
        guard case .operate(let e) = ps.assignment, e == desk.id, ps.override == nil, ps.motion == nil,
              let pos = ps.position, pos.layer == desk.at.layer
        else { return false }
        return desk.footprint.contains { off in
            GridPoint(desk.at.point.x + off.x, desk.at.point.y + off.y).chebyshev(to: pos.point) <= 1
        }
    }

    /// 1 人の研究の速さ(千分率): 建造物の専門 × 身につけたスキルと力の効き × 範囲の効果の workSpeed。
    public static func personPermille(_ ps: PersonState, desk: Placement, kind: StructureKindID, _ w: WorldState,
                                      _ c: ContentDB) -> Int
    {
        var p = 1000
        let spec = c.researchSpecialty(of: kind)
        if c.people[ps.id]?.specialties.contains(spec.tag) == true { p = p * spec.permille / 1000 }
        p = p * c.speedPermille(person: ps.id, skills: ps.skills, work: WorkKey.research) / 1000
        for m in Auras.modifiers(at: desk.at, in: w, content: c) {
            if case .workSpeed(let s) = m.modifier {
                // 強さ(千分率)で効きを薄める: 1000 + (s − 1000) × 強さ
                p = p * max(0, 1000 + (s - 1000) * m.strength / 1000) / 1000
            }
        }
        return max(0, p)
    }

    /// 研究に付いている人と、その人の 1 ステップの寄与(単位。重みを掛ける前)。人の ID 順。
    public static func contributors(for d: ResearchDef, _ w: WorldState, _ c: ContentDB)
        -> [(person: PersonID, desk: EntityID, units: Int)]
    {
        let phase = w.clock.phase
        let deskIDs = desks(w, c, station: d.station)
        var out: [(PersonID, EntityID, Int)] = []
        for pid in w.people.order {
            guard let ps = w.people[pid], ps.presence.isMember else { continue }
            var at: EntityID?
            if d.activePhases.contains(phase) {
                at = deskIDs.first { w.placements.items[$0].map { isWorking(ps, at: $0) } ?? false }
            }
            // 夜作業の研究(行為で時間が進む間)。研究机が 1 つあればよい。
            if at == nil, phase == .nightWork, let until = w.research.nightSessions[pid], w.clock.now <= until {
                at = deskIDs.first
            }
            guard let e = at, let desk = w.placements.items[e], case .structure(let k) = desk.kind else { continue }
            let units = c.researchRate(of: k) * Int(SimStep.gameSeconds) * personPermille(ps, desk: desk, kind: k, w, c)
            if units > 0 { out.append((pid, e, units)) }
        }
        return out
    }

    /// 寄与を足し合わせる(速い人から重みを掛ける)。
    public static func combined(_ units: [Int]) -> Int {
        units.sorted(by: >).enumerated().reduce(0) { acc, x in
            x.offset < crewWeights.count ? acc + x.element * crewWeights[x.offset] / 1000 : acc
        }
    }

    // MARK: 段

    /// 段の終わりの累計の点(段が無ければ空)。
    public static func nodeThresholds(_ d: ResearchDef) -> [Int] {
        var sum = 0
        return (d.nodes ?? []).map { sum += max(0, $0.points); return sum }
    }

    // MARK: スキル

    /// スキルの習得に要る進み(秒 × 千分率)。
    public static func skillUnits(_ d: SkillDef) -> Int { max(0, d.hours ?? 0) * 3600 * 1000 }

    /// スキルの習得が今のステップで進むか(station があれば、その建造物で作業しているときだけ)。
    public static func skillAdvances(_ d: SkillDef, _ ps: PersonState, _ w: WorldState, _ c: ContentDB) -> Bool {
        guard ps.presence.isMember else { return false }
        guard let st = d.station else { return true }
        return w.placements.sortedIDs.contains { id in
            guard let pl = w.placements.items[id], pl.status == .running, case .structure(let k) = pl.kind, k == st
            else { return false }
            return isWorking(ps, at: pl)
        }
    }
}

/// 断った理由(文字列表のキー)。
public enum ResearchReasons {
    public static let unknown: TextID = "reason.research.unknown"
    public static let locked: TextID = "reason.research.locked"
    public static let done: TextID = "reason.research.done"
    public static let noMaterials: TextID = "reason.research.no_materials"
    public static let notMember: TextID = "reason.research.not_member"
    public static let skillUnknown: TextID = "reason.research.skill_unknown"
    public static let skillLocked: TextID = "reason.research.skill_locked"
    public static let skillKnown: TextID = "reason.research.skill_known"
    public static let notLearning: TextID = "reason.research.not_learning"
    public static let notNight: TextID = "reason.research.not_night"
    public static let noDesk: TextID = "reason.research.no_desk"
    public static let nothingSelected: TextID = "reason.research.nothing_selected"
}
