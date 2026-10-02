import RFContent
import RFKernel
import RFWorld

/// 人の自動化の規則(序盤の設計 W-04)。純関数だけ。RFCrew(配属の実行)・RFExploration(採取の速さ)・
/// 画面(頼めない行為の灰色)が同じ答えを引く。コンテンツに crewWork が無ければ何も縛らない。
///
/// - 手が先(INV-O8): 仲間に頼めるのは、ノアが手で 1 度終えた行為だけ(`KnowledgeState.handDone`)。
/// - 働ける人数(INV-O10): min(起きている仲間, 火の枠 + 寝床の枠)。火の枠は焚き火の段から、寝床の枠は
///   建て終えた建造物の寝床(provides の bedTag)の合計からノアの分を引いた数。働けない仲間は焚き火のそばで休む。
/// - 人の速さ: 配属 gather の行為(採る・伐る・掘る・汲む)はノアの gatherPermille 倍。運搬と建設は掛けない。
public enum CrewWork {
    /// 働く配属か(空き・休む・ついて行くは働かない)。火の番は夜の仕事なので昼の枠に数えない。
    public static func isWork(_ a: Assignment) -> Bool {
        switch a {
        case .idle, .rest, .follow, .tendHearth: false
        case .haul, .operate, .guardArea, .build, .gather: true
        }
    }

    /// 仲間に頼めるか。頼めなければ理由(画面はこれで灰色にし、理由の文を出す)。
    public static func refusal(_ a: Assignment, for person: PersonID, _ w: WorldState, _ c: ContentDB) -> Rejection? {
        guard let def = c.crewWork, person != .noah else { return nil }
        if def.handFirst, let fam = family(of: a, def, c), !w.knowledge.handDone.contains(fam) {
            return Rejection("reason.assign.not_done_by_hand", detail: ["family": .string(fam.rawValue)])
        }
        if isWork(a), let cap = workable(w, c) {
            // 今その人を除いて働いている数が枠に届いていれば、頼めない
            let others = explicitWorkers(w).filter { $0 != person }
            if others.count >= cap {
                return Rejection("reason.assign.no_slot", detail: ["count": .int(Int64(cap))])
            }
        }
        return nil
    }

    // MARK: 手が先(INV-O8。v0.4 は行為の種類で数える)

    /// 行為の種類(InteractionDef.handFamily。無ければ行為 ID)。
    public static func family(of def: InteractionDef) -> HandFamilyID { def.handFamily ?? HandFamilyID(def.id.rawValue) }

    /// 配属が要る手の種類(nil = 縛らない)。
    public static func family(of a: Assignment, _ def: CrewWorkDef, _ c: ContentDB) -> HandFamilyID? {
        switch a {
        case .gather(let i, _): return c.interactions[i].map(family(of:)) ?? HandFamilyID(i.rawValue)
        case .tendHearth: return def.tendFamily
        case .haul: return .haul
        case .build: return .build
        case .idle, .rest, .follow, .operate, .guardArea: return nil
        }
    }

    /// ノアが手でやったことを書く(知識の側)。
    public static func noteHand(_ family: HandFamilyID, _ w: inout WorldState) {
        if !w.knowledge.handDone.contains(family) { w.knowledge.handDone.insert(family) }
    }

    /// 働ける人数。nil = 縛らない(crewWork が無い)。
    public static func workable(_ w: WorldState, _ c: ContentDB) -> Int? {
        guard let def = c.crewWork else { return nil }
        let awake = crew(w).count
        return min(awake, fireSlots(w, c, def) + bedSlots(w, c, def))
    }

    /// 火の枠(焚き火の段から)。
    public static func fireSlots(_ w: WorldState, _ c: ContentDB, _ def: CrewWorkDef) -> Int {
        let table = def.slotsByLevel
        let lv = campfireLevel(w, c)
        guard !table.isEmpty else { return 0 }
        return max(0, table[max(0, min(table.count - 1, lv))])
    }

    /// 寝床の枠: 建て終えた建造物の寝床の合計 − ノアの分。
    public static func bedSlots(_ w: WorldState, _ c: ContentDB, _ def: CrewWorkDef) -> Int {
        var beds = 0
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id], case .structure(let k) = p.kind, isBuilt(p) else { continue }
            beds += c.structures[k]?.provides[def.beds] ?? 0
        }
        return max(0, beds - def.noahBedCount)
    }

    /// 拠点の焚き火の段(HearthLevel の raw)。火床(Hearths.campfireLevel)から読む。
    /// 火床を持つ建造物が 1 つも無い内容(古い形)では、灯り(provides["light"])を持つ建て終えた建造物があれば
    /// 「燃えている」(3)とみなす。
    public static func campfireLevel(_ w: WorldState, _ c: ContentDB) -> Int {
        if !Hearths.structureHearths(w, c).isEmpty { return Hearths.campfireLevel(w, c).rawValue }
        for id in w.placements.sortedIDs {
            guard let p = w.placements.items[id], case .structure(let k) = p.kind, isBuilt(p) else { continue }
            if (c.structures[k]?.provides["light"] ?? 0) > 0 { return 3 }
        }
        return 0
    }

    /// 今働く仲間。nil = 縛らない。1 ステップごとに数え直す(INV-O10 v0.4)。
    /// 配属のある人を先に頼んだ順で枠に入れ(超えた分は最後に頼んだ人から休む)、空きの人は残りの枠で共同の運搬に。
    public static func working(_ w: WorldState, _ c: ContentDB) -> Set<PersonID>? {
        guard let cap = workable(w, c) else { return nil }
        var out: [PersonID] = []
        for id in byAssignmentOrder(explicitWorkers(w), w) where out.count < cap { out.append(id) }
        for id in crew(w) where out.count < cap && !out.contains(id) {
            if case .idle = w.people.effectiveAssignment(id) ?? .idle { out.append(id) }
        }
        return Set(out)
    }

    /// 人の速さ(千分率)。仲間が配属 gather の行為をしているときだけ掛ける。
    public static func gatherPermille(_ person: PersonID, _ w: WorldState, _ c: ContentDB) -> Int {
        guard let def = c.crewWork, person != .noah else { return 1000 }
        if case .gather = w.people.effectiveAssignment(person) ?? .idle { return def.gatherPermille }
        return 1000
    }

    // MARK: 内側

    static func crew(_ w: WorldState) -> [PersonID] {
        w.people.members.filter { $0 != .noah && w.people[$0]?.presence.isAlive == true }
    }

    static func explicitWorkers(_ w: WorldState) -> [PersonID] {
        crew(w).filter { isWork(w.people.effectiveAssignment($0) ?? .idle) }
    }

    /// 頼んだ順(来歴の最後の配属の記録が古い順。記録が無い人は先頭・人の順)。
    static func byAssignmentOrder(_ ids: [PersonID], _ w: WorldState) -> [PersonID] {
        var last: [PersonID: Int] = [:]
        let want = Set(ids)
        for (i, r) in w.ledger.records.enumerated().reversed() where r.act == .assigned {
            guard case .person(let p) = r.subject, want.contains(p), last[p] == nil else { continue }
            last[p] = i
            if last.count == want.count { break }
        }
        return ids.enumerated().sorted { (last[$0.element] ?? -1, $0.offset) < (last[$1.element] ?? -1, $1.offset) }
            .map(\.element)
    }

    static func isBuilt(_ p: Placement) -> Bool {
        if case .underConstruction = p.status { false } else { true }
    }
}
