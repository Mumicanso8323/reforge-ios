import RFContent
import RFKernel
import RFWorld

/// 画面・ボット向けの研究とスキルの問い合わせ。ID と数だけを返す(名前は認識の層が
/// SubjectID.research(id) / skill の見出しで引く。存在を伏せる研究は一覧に入らない)。
public enum ResearchQueries {
    public enum Status: Equatable, Sendable {
        /// 見えているが前提がまだ。
        case locked
        case available
        case active
        case done
    }

    public struct Entry: Equatable, Sendable {
        public var id: ResearchID
        public var status: Status
        public var points: Int
        public var totalPoints: Int
        public var nodesDone: Int
        public var nodeCount: Int
    }

    public struct SkillEntry: Equatable, Sendable {
        public enum Status: Equatable, Sendable { case locked, available, learning, known }
        public var id: SkillID
        public var status: Status
        /// 習得の進み(千分率)。
        public var progressPermille: Int
    }

    /// 見えている研究パッケージ(ID 順)。
    public static func list(_ w: WorldState, _ c: ContentDB) -> [Entry] {
        c.research.keys.sorted().compactMap { id in
            guard let d = c.research[id], ResearchRules.isVisible(d, w, c) else { return nil }
            let status: Status =
                if w.research.completed.contains(id) { .done }
                else if w.research.active == id { .active }
                else if ResearchRules.requirementsMet(d, w, c) { .available }
                else { .locked }
            let total = d.totalPoints
            return Entry(id: id, status: status, points: status == .done ? total : min(total, w.research.points(of: id)),
                         totalPoints: total, nodesDone: w.research.nodesDone[id] ?? 0, nodeCount: d.nodes?.count ?? 0)
        }
    }

    /// その人のスキル(見えているものだけ。ID 順)。
    public static func skills(of p: PersonID, _ w: WorldState, _ c: ContentDB) -> [SkillEntry] {
        let known = w.people[p]?.skills ?? []
        return c.skills.keys.sorted().compactMap { id in
            guard let d = c.skills[id], ResearchRules.isVisible(d, w, c) else { return nil }
            let need = ResearchRules.skillUnits(d)
            if known.contains(id) { return SkillEntry(id: id, status: .known, progressPermille: 1000) }
            if let l = w.research.learning[p], l.skill == id {
                return SkillEntry(id: id, status: .learning, progressPermille: need > 0 ? l.progress * 1000 / need : 1000)
            }
            let saved = w.research.skillProgress[p]?[id] ?? 0
            let st: SkillEntry.Status = ResearchRules.requirementsMet(d, w, c) ? .available : .locked
            return SkillEntry(id: id, status: st, progressPermille: need > 0 ? saved * 1000 / need : 0)
        }
    }

    /// 研究机に付いて、いま研究を進めている人(前のステップ)。
    public static func studying(_ w: WorldState) -> [PersonID] { w.research.studying }
}
