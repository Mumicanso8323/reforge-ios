import RFContent
import RFKernel
import RFMatter
import RFPerception
import RFRules
import RFWorld

// PT-B2 夜の締めの 3 行と、再開の 1 行。どちらも世界を読むだけで、世界にも保存にも何も足さない(INV-B2-1)。

/// 物の名前と数(認識の層を通した名前)。
public struct CountedName: Equatable, Sendable {
    public var name: String
    public var count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

/// 日没の帯の上に出す締めの 3 行。日没(夜作業か寝るかを選ぶ間)だけ Frame に入る。
public struct DayWrapView: Equatable, Sendable {
    /// 今日できた物(多い順に 3 つまで)。
    public var made: [CountedName]
    /// 動いている物の 1 行。
    public var running: String?
    /// 明日の見込みで一番急ぐもの 1 つ。
    public var outlook: String?

    public init(made: [CountedName], running: String? = nil, outlook: String? = nil) {
        self.made = made
        self.running = running
        self.outlook = outlook
    }

    /// 3 行とも空のとき true(画面は何も出さない)。
    public var isEmpty: Bool { made.isEmpty && running == nil && outlook == nil }
}

/// 再開の 1 行の材料。実時刻は持たない(出すかどうかはアプリが実時間で決める)。
public struct ResumeLine: Equatable, Sendable {
    /// ノアの最後の目立つ行為(無ければ nil)。
    public var last: String?
    /// 今の目標の 1 行(表示と同じ)。
    public var next: String?

    public init(last: String? = nil, next: String? = nil) {
        self.last = last
        self.next = next
    }
}

/// 明日の見込みの候補と、急ぐ順の決め方(1 つの関数。表で確かめる)。
public enum DayWrapRules {
    public enum Kind: Int, Equatable, Sendable, CaseIterable {
        // 同じ急ぎなら、小さい方を先に出す(水 → 食料 → 火 → ライン)
        case water, food, fire, line
        // 暦の見込み(W-24)。同じ急ぎなら一番後
        case calendar
    }

    public struct Candidate: Equatable, Sendable {
        public var kind: Kind
        /// 困るまでの見当(千分率の日数。小さいほど急ぐ)。
        public var milliDays: Int
        public var text: String
        /// 暦の見込みの日数の幅(暦以外は nil)。同じ値なら日数 1 つの文。
        public var daysMin: Int?
        public var daysMax: Int?

        public init(kind: Kind, milliDays: Int, text: String, daysMin: Int? = nil, daysMax: Int? = nil) {
            self.kind = kind
            self.milliDays = milliDays
            self.text = text
            self.daysMin = daysMin
            self.daysMax = daysMax
        }

        /// 暦の見込みの候補。daysMin == daysMax なら日数の文、違えば幅の文。急ぎは小さい方の日数。
        public static func calendarOutlook(daysMin: Int, daysMax: Int, text: String) -> Candidate {
            Candidate(kind: .calendar, milliDays: daysMin * 1000, text: text, daysMin: daysMin, daysMax: daysMax)
        }
    }

    /// 暦の見込みの日数の幅 [daysMin, daysMax](真の残り日数を必ず含む)。出さない時は nil。
    ///
    /// - 季節の定義・宣言が無い、数えが 0、替わり目まで leadDays より遠い時は出さない。
    /// - 幅 w = max(0, initialWidth - (数え / narrowEvery) * narrowStep)。w == 0 は日数 1 つ。
    /// - 真の値が幅のどこに来るかは、世界の seed と替わり目の通し番号から決まる固定のずれ(毎日の帯で揺れない)。
    public static func calendarRange(clock: ClockDef, day: Int, count: Int, seed: UInt64) -> (daysMin: Int, daysMax: Int)? {
        guard let seasons = clock.seasons, let decl = clock.calendarOutlook, count >= 1,
              let next = seasons.next(elapsedDays: day &- 1), next.daysLeft <= decl.leadDays else { return nil }
        let left = next.daysLeft
        let w = decl.width(count: count)
        guard w > 0 else { return (left, left) }
        let offset = Int(mix(seed, UInt64(truncatingIfNeeded: next.index)) % UInt64(w + 1))
        let lo = max(1, left - offset)
        return (lo, lo + w)
    }

    /// splitmix64 による固定のずれ(世界の seed × 替わり目の番号)。
    static func mix(_ seed: UInt64, _ index: UInt64) -> UInt64 {
        var z = seed &+ (index &+ 1) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 食料・水を候補に入れる残り日数の上限(千分率)。これより多ければ急がない。
    public static let stockHorizon = 3000

    /// 火の見込み(PT-B1 の 4 段。薪の置き場の分も足した見込み)→ 困るまでの見当(千分率の日数)。
    /// 夜明けまでもつなら急がない(nil)。消えている火は 0。
    public static func fireMilliDays(_ outlook: FireOutlook, lit: Bool) -> Int? {
        guard lit else { return 0 }
        switch outlook {
        case .untilEvening: return 0
        case .midnight: return 250
        case .beforeDawn: return 500
        case .throughNight: return nil
        }
    }

    /// ライン止まりの見当(千分率の日数)。止まっている間は 1 日ぶんの生産を失うと数える。
    public static let stoppedLineMilliDays = 1000

    /// 一番急ぐ 1 つ。困るまでの日数が短い順、同じなら Kind の順。
    public static func mostUrgent(_ candidates: [Candidate]) -> Candidate? {
        candidates.min { a, b in
            a.milliDays != b.milliDays ? a.milliDays < b.milliDays : a.kind.rawValue < b.kind.rawValue
        }
    }
}

extension FrameBuilder {
    private func label(_ p: Perceiver, _ id: TextID, _ args: [String: TextArg] = [:]) -> String {
        p.render(TextRef(id, args))
    }

    // MARK: - 夜の締め

    /// 夜の締めの 3 行。日没でなくても作れる(出すかどうかは build が決める)。
    public func dayWrap(_ w: WorldState) -> DayWrapView {
        let p = perceiver(w)
        let today = todaysRecords(w)
        return DayWrapView(made: made(today, p), running: runningLine(w, today, p), outlook: outlook(w, p))
    }

    /// その日の夜明けから今まで(いまの周回)の来歴。
    func todaysRecords(_ w: WorldState) -> [ProvenanceRecord] {
        w.ledger.records.filter { $0.day == w.clock.day && $0.run == w.run.index }
    }

    static let madeActs: Set<ActKind> = [.crafted, .produced, .built, .trialed, .designed, .mined, .gathered]

    /// 数える対象(数えられない対象は nil)。モジュールのラインの生産は、そのモジュールが作る物で数える。
    private func madeTarget(_ r: ProvenanceRecord) -> SubjectRef? {
        switch r.subject {
        case .none, .entity, .design: return nil
        case .module(let kind, _):
            guard r.act == .produced, let y = content.modules[kind]?.produces?.first else { return nil }
            if let m = y.matter { return .matter(NameGenerator.name(for: m)) }
            return y.item.map { SubjectRef.item($0) }
        default: return r.subject
        }
    }

    /// 来歴の対象(`SubjectRef` の鍵)で数え、同数は鍵で並べる。表示の名前は最後に引く(名前は言語で変わる)。
    func made(_ records: [ProvenanceRecord], _ p: Perceiver) -> [CountedName] {
        var tally: [String: (ref: SubjectRef, count: Int)] = [:]
        for r in records where Self.madeActs.contains(r.act) {
            guard let ref = madeTarget(r) else { continue }
            let key = ref.kindKey
            tally[key, default: (ref, 0)].count += max(1, r.count)
        }
        let sorted = tally.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
        return sorted.prefix(3).map { CountedName(name: p.name(of: $0.value.ref), count: $0.value.count) }
    }

    // MARK: 2 行目: 動いている物

    /// 仕事に就いている仲間(ノアを除く)の数。
    private func workingCrew(_ w: WorldState) -> Int {
        w.people.members.filter { id in
            guard id != .noah, let a = w.people.effectiveAssignment(id) else { return false }
            switch a {
            case .idle, .rest, .follow: return false
            default: return true
            }
        }.count
    }

    func runningLine(_ w: WorldState, _ today: [ProvenanceRecord], _ p: Perceiver) -> String? {
        let lines = w.placements.moduleIDs.filter { w.placements.items[$0]?.status == .running }.count
        let crew = workingCrew(w)
        // その日に初めて動いた物(その種類の初めての生産の記録が今日のもの)
        let first = today.first { r in
            guard r.act == .produced, case .module = r.subject else { return false }
            return w.ledger.first(.produced, r.subject) == r.id
        }
        var parts: [String] = []
        if let f = first { parts.append(label(p, "ui.daywrap.first", ["name": .subject(Perceiver.subject(of: f.subject))])) }
        if lines > 0 { parts.append(label(p, "ui.daywrap.lines", ["n": .int(Int64(lines))])) }
        if crew > 0 { parts.append(label(p, "ui.daywrap.crew", ["n": .int(Int64(crew))])) }
        return parts.isEmpty ? nil : parts.joined(separator: label(p, "ui.daywrap.sep"))
    }

    // MARK: 3 行目: 明日の見込み

    func outlook(_ w: WorldState, _ p: Perceiver) -> String? {
        DayWrapRules.mostUrgent(outlookCandidates(w, p))?.text
    }

    func outlookCandidates(_ w: WorldState, _ p: Perceiver) -> [DayWrapRules.Candidate] {
        var out: [DayWrapRules.Candidate] = []
        // 食料・水の残り日数(蓄えが何日もつか。生存が毎ステップ書く値)
        if let def = content.survival {
            func days(_ id: StatID) -> Int? { w.survival.stats[id].map { Int($0.raw) } }
            if let d = days(def.waterDaysStat), d < DayWrapRules.stockHorizon {
                out.append(.init(kind: .water, milliDays: d,
                                 text: label(p, "ui.daywrap.water", ["n": .int(Int64(Self.wholeDays(d)))])))
            }
            if let d = days(def.foodDaysStat), d < DayWrapRules.stockHorizon {
                out.append(.init(kind: .food, milliDays: d,
                                 text: label(p, "ui.daywrap.food", ["n": .int(Int64(Self.wholeDays(d)))])))
            }
        }
        // 火(PT-B1 の火の見込みと同じ 4 段。焚き火が無ければ見ない)
        if let pl = primaryHearth(w), let outlook = fireGauge(of: pl, w)?.outlook {
            let lit = Hearths.campfireLevel(w, content) != .out
            if let d = DayWrapRules.fireMilliDays(outlook, lit: lit) {
                let text: String = if !lit {
                    label(p, "ui.daywrap.fire_out")
                } else {
                    switch outlook {
                    case .untilEvening: label(p, "ui.daywrap.fire_until_evening")
                    case .midnight: label(p, "ui.daywrap.fire_midnight")
                    case .beforeDawn: label(p, "ui.daywrap.fire_before_dawn")
                    case .throughNight: label(p, "ui.daywrap.fire_through_night")
                    }
                }
                out.append(.init(kind: .fire, milliDays: d, text: text))
            }
        }
        // 止まっているライン(理由つき。ID の小さい物)
        for id in w.placements.moduleIDs {
            guard let pl = w.placements.items[id], case .stopped(let reason) = pl.status else { continue }
            // 印で見せる止まり方は、理由の文を出さない(場面の印と同じ決め)
            let text: String = if StopKind.of(reason: reason) != nil {
                label(p, "ui.daywrap.line_marked", ["name": .subject(Perceiver.subject(of: pl.kind))])
            } else {
                label(p, "ui.daywrap.line",
                      ["name": .subject(Perceiver.subject(of: pl.kind)),
                       "reason": .string(p.stoppedText(reason, waitingFor: pl.module?.waitingFor))])
            }
            out.append(.init(kind: .line, milliDays: DayWrapRules.stoppedLineMilliDays, text: text))
            break
        }
        // 暦の見込み(季節の定義・宣言・数えがある内容だけ)
        if let decl = content.clock.calendarOutlook,
           let r = DayWrapRules.calendarRange(clock: content.clock, day: w.clock.day,
                                              count: w.narrative.counters[decl.counter] ?? 0, seed: w.seed) {
            let text: String = if r.daysMin == r.daysMax {
                label(p, "ui.daywrap.calendar_days_left", ["n": .int(Int64(r.daysMin))])
            } else {
                label(p, "ui.daywrap.calendar_days_range", ["min": .int(Int64(r.daysMin)), "max": .int(Int64(r.daysMax))])
            }
            out.append(DayWrapRules.Candidate.calendarOutlook(daysMin: r.daysMin, daysMax: r.daysMax, text: text))
        }
        return out
    }

    /// 千分率の日数 → 切り上げた日数(0 のときは 0)。帯と同じ SurvivalDef.wholeDays を通る。
    static func wholeDays(_ milli: Int) -> Int { Int(SurvivalDef.wholeDays(milli: Int64(milli))) }

    // MARK: - 再開の 1 行

    static let resumeActs: Set<ActKind> = [.built, .designed, .trialed, .crafted, .placed]

    /// 前回のノアの最後の目立つ行為と、今の目標。実時刻は持たない。
    public func resumeLine(_ w: WorldState) -> ResumeLine {
        let p = perceiver(w)
        let last = w.ledger.records.last { $0.actor == .noah && Self.resumeActs.contains($0.act) }
            .flatMap { r in p.journalLine(r) ?? p.name(of: r.subject) }
        let next = unlocks(w).isOpen(UIElements.bandObjective) ? objective(w, p) : nil
        return ResumeLine(last: last, next: next)
    }
}
