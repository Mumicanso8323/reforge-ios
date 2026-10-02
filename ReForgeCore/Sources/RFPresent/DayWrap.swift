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
    }

    public struct Candidate: Equatable, Sendable {
        public var kind: Kind
        /// 困るまでの見当(千分率の日数。小さいほど急ぐ)。
        public var milliDays: Int
        public var text: String

        public init(kind: Kind, milliDays: Int, text: String) {
            self.kind = kind
            self.milliDays = milliDays
            self.text = text
        }
    }

    /// 食料・水を候補に入れる残り日数の上限(千分率)。これより多ければ急がない。
    public static let stockHorizon = 3000

    /// 火の段 → 困るまでの見当(千分率の日数)。一番強い段は急がない(nil)。
    public static func fireMilliDays(_ level: HearthLevel) -> Int? {
        switch level {
        case .out: 0
        case .smoldering: 500
        case .flickering: 1500
        case .burning: 2500
        case .roaring: nil
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
    // MARK: - 固定の文言(内容の文字列表に同じ ID があればそちらを使う)

    private func label(_ id: TextID, _ fallback: String, _ args: [String: String] = [:]) -> String {
        var s = content.texts[id] ?? fallback
        for (k, v) in args.sorted(by: { $0.key < $1.key }) { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    // MARK: - 夜の締め

    /// 夜の締めの 3 行。日没でなくても作れる(出すかどうかは build が決める)。
    public func dayWrap(_ w: WorldState) -> DayWrapView {
        let p = Perceiver(content: content, world: w)
        let today = todaysRecords(w)
        return DayWrapView(made: made(today, p), running: runningLine(w, today, p), outlook: outlook(w, p))
    }

    /// その日の夜明けから今まで(いまの周回)の来歴。
    func todaysRecords(_ w: WorldState) -> [ProvenanceRecord] {
        w.ledger.records.filter { $0.day == w.clock.day && $0.run == w.run.index }
    }

    static let madeActs: Set<ActKind> = [.crafted, .produced, .built, .trialed, .designed, .mined, .gathered]

    /// 来歴の対象の名前(数えられない対象は nil)。モジュールのラインの生産は、そのモジュールが作る物の名前で数える。
    private func madeName(_ r: ProvenanceRecord, _ p: Perceiver) -> String? {
        switch r.subject {
        case .none, .entity, .design: return nil
        case .module(let kind, _):
            guard r.act == .produced, let y = content.modules[kind]?.produces?.first else { return nil }
            if let m = y.matter { return p.name(of: NameGenerator.name(for: m)) }
            return y.item.map { p.name(Subject.item($0)) }
        default: return p.name(of: r.subject)
        }
    }

    func made(_ records: [ProvenanceRecord], _ p: Perceiver) -> [CountedName] {
        var tally: [String: Int] = [:]
        for r in records where Self.madeActs.contains(r.act) {
            guard let name = madeName(r, p) else { continue }
            tally[name, default: 0] += max(1, r.count)
        }
        let sorted = tally.map { CountedName(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return Array(sorted.prefix(3))
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
        if let f = first { parts.append(label("ui.daywrap.first", "初めて動いた: {name}", ["name": p.name(of: f.subject)])) }
        if lines > 0 { parts.append(label("ui.daywrap.lines", "動いているライン {n}", ["n": "\(lines)"])) }
        if crew > 0 { parts.append(label("ui.daywrap.crew", "仕事に就いた仲間 {n}", ["n": "\(crew)"])) }
        return parts.isEmpty ? nil : parts.joined(separator: "。")
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
                                 text: label("ui.daywrap.water", "水はあと {n} 日分", ["n": "\(Self.wholeDays(d))"])))
            }
            if let d = days(def.foodDaysStat), d < DayWrapRules.stockHorizon {
                out.append(.init(kind: .food, milliDays: d,
                                 text: label("ui.daywrap.food", "食料はあと {n} 日分", ["n": "\(Self.wholeDays(d))"])))
            }
        }
        // 火(焚き火のうち一番強い段。焚き火が無ければ見ない)
        if !Hearths.structureHearths(w, content).isEmpty {
            let level = Hearths.campfireLevel(w, content)
            if let d = DayWrapRules.fireMilliDays(level) {
                let text: String = switch level {
                case .out: label("ui.daywrap.fire_out", "火が消えている")
                case .smoldering: label("ui.daywrap.fire_smoldering", "火がくすぶっている")
                default: label("ui.daywrap.fire_low", "火が弱くなっている")
                }
                out.append(.init(kind: .fire, milliDays: d, text: text))
            }
        }
        // 止まっているライン(理由つき。ID の小さい物)
        for id in w.placements.moduleIDs {
            guard let pl = w.placements.items[id], case .stopped(let reason) = pl.status else { continue }
            out.append(.init(kind: .line, milliDays: DayWrapRules.stoppedLineMilliDays,
                             text: label("ui.daywrap.line", "{name}が止まっている: {reason}",
                                         ["name": p.name(of: pl.kind), "reason": p.text(reason)])))
            break
        }
        return out
    }

    /// 千分率の日数 → 切り上げた日数(0 のときは 0)。
    static func wholeDays(_ milli: Int) -> Int { max(0, (milli + 999) / 1000) }

    // MARK: - 再開の 1 行

    static let resumeActs: Set<ActKind> = [.built, .designed, .trialed, .crafted, .placed]

    /// 前回のノアの最後の目立つ行為と、今の目標。実時刻は持たない。
    public func resumeLine(_ w: WorldState) -> ResumeLine {
        let p = Perceiver(content: content, world: w)
        let last = w.ledger.records.last { $0.actor == .noah && Self.resumeActs.contains($0.act) }
            .flatMap { r in p.journalLine(r) ?? p.name(of: r.subject) }
        let next = unlocks(w).isOpen(UIElements.bandObjective) ? objective(w, p) : nil
        return ResumeLine(last: last, next: next)
    }
}
