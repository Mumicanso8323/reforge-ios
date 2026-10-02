import RFContent
import RFInvention
import RFKernel
import RFMatter
import RFPerception
import RFRules
import RFWorld

// 設計画面・ノート・資料の射影(U17)。文字はすべて認識の層(Perceiver)を通した後のもの。
// 数の言い回し(「三割くらい」「3 個」)と操作の語(「試す」「札にする」)は画面の固定文言で組む。

/// 設計画面の材料: 工程表に積める段・試す物・段に入れる物・札。
public struct DesignBench: Equatable, Sendable {
    /// 工程表に積める段(解禁済みで、規則の表に載っているモジュール)。
    public struct Module: Equatable, Sendable {
        public var module: ModuleKindID
        public var name: String
        public var glyph: String
        /// 試作に要る設備がそろっているか(そろっていなければ、その理由の 1 行)。
        public var missing: String?
    }

    /// 在庫の 1 山(試す物・段に入れる物)。
    public struct Stock: Equatable, Sendable {
        public var selector: StockSelector
        public var name: String
        public var quantity: Int
        /// 物質ならノアの手の見当(0〜100)。品なら nil。
        public var percent: Int?
    }

    /// ライン札。
    public struct Plate: Equatable, Sendable {
        public var design: EntityID
        /// 札の結果の名前(見込み。試していなければ nil)。
        public var result: String?
        /// 段の名前(上から)。
        public var steps: [String]
    }

    public var modules: [Module]
    /// 試せる物(物質の山)。
    public var materials: [Stock]
    /// 段に入れられる品(燃料・混ぜ物など。物質でない品の山)。
    public var additives: [Stock]
    public var plates: [Plate]
    /// まだ知らない段の数(部品の棚の「？」。名前は出さない)。
    public var unknownModules: Int = 0

    public init(modules: [Module], materials: [Stock], additives: [Stock], plates: [Plate]) {
        self.modules = modules
        self.materials = materials
        self.additives = additives
        self.plates = plates
    }
}

/// ノート: 試したこと・所見・図鑑・手がかり・記録(工程表で開くもの)・資料。
public struct NotebookPage: Equatable, Sendable {
    public struct Trial: Equatable, Sendable {
        public var record: ProvenanceID
        public var day: Int
        public var input: ProcessSheet.Sensed
        public var result: ProcessSheet.Sensed
        public var steps: Int
        public var quantity: Int
    }

    public struct Finding: Equatable, Sendable {
        public var text: String
        /// どの試作で載ったか(開けばその工程表)。
        public var trial: ProvenanceID
    }

    public struct CodexLine: Equatable, Sendable {
        public var name: String
        /// 作ったことがあるか(false は空欄の影)。
        public var made: Bool
        public var percent: Int?
        /// この行に付いた手がかりの文。
        public var clues: [String]
        /// 品の欄(持ったことのある品。正体が分かるまで made = false)。
        public var item: Bool = false
    }

    public struct Clue: Equatable, Sendable {
        /// 何についての書き留めか。
        public var about: String
        public var text: String
        /// 出典の語(人・ノアの手・端末…)。
        public var source: String
        public var day: Int
    }

    public struct Record: Equatable, Sendable {
        public var sheet: SheetID
        public var title: String
    }

    public struct Document: Equatable, Sendable {
        public var id: DocumentID
        public var title: String
        public var source: String?
    }

    /// 新しい順。
    public var trials: [Trial]
    /// 新しい順(同じ文は 1 つにまとめる)。
    public var findings: [Finding]
    public var codex: [CodexLine]
    /// 新しい順。
    public var clues: [Clue]
    public var records: [Record]
    public var documents: [Document]
}

/// 資料 1 つの中身。
public struct DocumentPage: Equatable, Sendable {
    public var id: DocumentID
    public var title: String
    public var body: String
    public var source: String?
    /// 読める割合(千分率。資料に段があるときだけ。U19)。
    public var readablePermille: Int? = nil
    /// いまの修理の段階(資料に段があるときだけ)。
    public var repairStage: Int? = nil
}

extension PresentSubject {
    /// 副産物の名前の見出し「byproduct:<id>」。
    public static func byproduct(_ id: ByproductID) -> SubjectID { SubjectID("byproduct:\(id.rawValue)") }
}

extension FrameBuilder {
    // MARK: - 設計画面

    public func designBench(in w: WorldState) -> DesignBench {
        let p = Perceiver(content: content, world: w)
        let modules = w.research.unlocked.modules
            .filter { content.ruleBook.modules[$0] != nil }
            .sorted()
            .map { m -> DesignBench.Module in
                let miss = TrialRequirements.check([ProcessStep(m)], world: w, content: content).map { p.text($0.reason) }
                return DesignBench.Module(module: m, name: p.name(Subject.module(m)), glyph: p.glyph(Subject.module(m)),
                                          missing: miss)
            }
        var materials: [DesignBench.Stock] = []
        var additives: [DesignBench.Stock] = []
        for h in [HolderID.base, .person(.noah)] {
            for e in w.inventory.entries(h) where e.quantity > 0 {
                let sel = StockSelector(holder: h, stuff: e.stuff, unique: e.unique)
                switch e.stuff {
                case .matter(let m):
                    Self.merge(&materials, DesignBench.Stock(selector: sel, name: p.name(of: e.stuff), quantity: e.quantity,
                                                             percent: HandSense.estimate(m).basisPoints / 100))
                case .item:
                    guard e.unique == nil else { continue }
                    Self.merge(&additives, DesignBench.Stock(selector: StockSelector(holder: .base, stuff: e.stuff),
                                                             name: p.name(of: e.stuff), quantity: e.quantity, percent: nil))
                }
            }
        }
        let plates = w.invention.designs.values.sorted { $0.id < $1.id }.map { d in
            DesignBench.Plate(design: d.id, result: d.expected.map { p.name(of: NameGenerator.name(for: $0)) },
                              steps: d.steps.map { p.name(Subject.module($0.module)) })
        }
        var bench = DesignBench(modules: modules, materials: materials, additives: additives, plates: plates)
        bench.unknownModules = unknownModules(in: w)
        return bench
    }

    /// 同じ山(拠点とノアの持ち物で同じ物)は 1 行にまとめる。物質は在り処ごとに分ける(試すときに在り処を指す)。
    private static func merge(_ list: inout [DesignBench.Stock], _ s: DesignBench.Stock) {
        if case .item = s.selector.stuff, let i = list.firstIndex(where: { $0.selector == s.selector }) {
            list[i].quantity += s.quantity
        } else {
            list.append(s)
        }
    }

    // MARK: - ノート

    public func notebook(in w: WorldState) -> NotebookPage {
        let p = Perceiver(content: content, world: w)
        let nb = w.notebook
        let trials = nb.trials.reversed().map { t in
            NotebookPage.Trial(record: t.record, day: w.ledger.record(t.record)?.day ?? w.clock.day,
                               input: sensed(NameGenerator.name(for: t.input), HandSense.estimate(t.input), p),
                               result: sensed(t.outcome.name, HandSense.estimate(t.outcome.product), p),
                               steps: t.steps.count, quantity: t.quantity)
        }
        var seen: Set<String> = []
        var findings: [NotebookPage.Finding] = []
        for t in nb.trials.reversed() {
            for f in t.outcome.findings {
                let s = findingText(f.id, f.args, p)
                if seen.insert(s).inserted { findings.append(NotebookPage.Finding(text: s, trial: t.record)) }
            }
        }
        let clueText: (NoteEntry) -> String = { self.noteText($0, p) }
        let rows = Codex.rows(nb, content: content)
        var codex = rows.map { r in
            NotebookPage.CodexLine(
                name: p.name(of: r.name), made: r.made, percent: r.bestSensed.map { $0.basisPoints / 100 },
                clues: r.hints.compactMap { h in nb.notes.last { $0.hint == h }.map(clueText) })
        }
        codex += shadowRows(w, rows, p)
        let clues = nb.notes.reversed().map { n in
            NotebookPage.Clue(about: p.name(n.about), text: clueText(n), source: p.source(of: n),
                              day: n.record.flatMap { w.ledger.record($0)?.day } ?? w.clock.day)
        }
        let records = content.sheets.keys.sorted().compactMap { sid -> NotebookPage.Record? in
            guard let def = content.sheets[sid],
                  ConditionEvaluator.evaluatePure(def.when, world: w, content: content) == true else { return nil }
            return NotebookPage.Record(sheet: sid, title: p.name(def.title))
        }
        let docs = Documents.available(in: w, content: content).map { d in
            NotebookPage.Document(id: d.id, title: p.text(d.title), source: d.source.map { p.name($0) })
        }
        return NotebookPage(trials: Array(trials), findings: findings, codex: codex, clues: Array(clues),
                            records: records, documents: docs)
    }

    // MARK: - 深さの影(答えは隠し、深さがあることは隠さない)

    /// 図鑑の影の欄(CodexShadowDef)。作った行・手がかりの空欄と同じ名前のものは重ねない。
    func shadowRows(_ w: WorldState, _ rows: [CodexRow], _ p: Perceiver) -> [NotebookPage.CodexLine] {
        let holds = { (c: Condition?) in c.map { ConditionEvaluator.evaluatePure($0, world: w, content: content) == true } }
        return content.codexShadows.values
            .sorted { ($0.order ?? 0, $0.id) < ($1.order ?? 0, $1.id) }
            .compactMap { d -> NotebookPage.CodexLine? in
                guard holds(d.when) ?? true else { return nil }
                if let t = d.target {
                    // 作れば本物の行が出る。手がかりの空欄で同じ名前が出ていれば重ねない
                    if rows.contains(where: { $0.made && Codex.covers($0.name, t) }) || rows.contains(where: { $0.name == t }) {
                        return nil
                    }
                }
                if let item = d.item {
                    guard Self.everHeld(item, w) else { return nil }
                    return NotebookPage.CodexLine(name: p.name(d.name), made: holds(d.filledWhen) ?? false, percent: nil,
                                                  clues: [], item: true)
                }
                return NotebookPage.CodexLine(name: p.name(d.name), made: holds(d.filledWhen) ?? false, percent: nil,
                                              clues: [])
            }
    }

    /// 品を持ったことがあるか(いま持っているか、来歴に載っている)。
    static func everHeld(_ item: ItemID, _ w: WorldState) -> Bool {
        if w.inventory.holders.values.contains(where: { $0.contains { $0.stuff == .item(item) } }) { return true }
        return w.ledger.records.contains { $0.subject == .item(item) }
    }

    /// まだ解禁していない段(規則の表に載っているモジュール)の数。
    public func unknownModules(in w: WorldState) -> Int {
        content.ruleBook.modules.keys.filter { !w.research.unlocked.modules.contains($0) }.count
    }

    /// 資料を開く(開く条件が成り立っていなければ nil)。
    public func document(_ id: DocumentID, in w: WorldState) -> DocumentPage? {
        guard let d = content.documents[id],
              ConditionEvaluator.evaluatePure(d.when, world: w, content: content) == true else { return nil }
        let p = Perceiver(content: content, world: w)
        let r = Documents.reading(d, in: w)
        return DocumentPage(id: id, title: p.text(d.title), body: p.text(r.body), source: d.source.map { p.name($0) },
                            readablePermille: r.readablePermille, repairStage: r.repairStage)
    }

    // MARK: - 工程表(発明の出所)

    func inventionSheet(_ m: SheetModel, source: ProcessSheet.Source, _ p: Perceiver) -> ProcessSheet {
        let title: String = switch m.title {
        case .text(let t): p.text(t)
        case .subject(let s): p.name(s)
        }
        let rows = m.rows.enumerated().map { i, r -> ProcessSheet.Row in
            var row = ProcessSheet.Row(title: p.name(r.subject), note: nil)
            row.inputs = r.inputs.map { p.name(Subject.item($0)) }
            row.step = r.step == nil ? nil : i
            row.forecast = r.forecast.map { sensed($0.name, $0.sensed, p) }
            row.findings = r.forecast.map { f in f.findings.map { findingText($0, [], p) } } ?? []
            return row
        }
        let card = m.card.map { c in
            ProcessSheet.Card(
                product: sensed(c.name, c.sensed, p), hardness: c.hardness, toughness: c.toughness,
                byproducts: c.byproducts.map { p.name(PresentSubject.byproduct($0)) },
                findings: c.findings.map { findingText($0.id, $0.args, p) },
                used: c.consumed.map { .init(name: p.name(Subject.item($0.item)), quantity: $0.quantity) },
                quantity: c.quantity, unique: c.unique != nil)
        }
        // 工程の行の所見は、結果カードがあればその引数つきの文に差し替える
        var out = ProcessSheet(source: source, title: title, rows: rows, result: nil,
                               head: m.head.map { sensed($0.name, $0.sensed, p) },
                               expected: m.expected.map { sensed($0.name, $0.sensed, p) }, card: card)
        if let c = m.card {
            for i in out.rows.indices {
                out.rows[i].findings = c.findings.filter { $0.step == i }.map { findingText($0.id, $0.args, p) }
            }
        }
        out.result = card?.product.name ?? out.expected?.name
        return out
    }

    func sensed(_ name: MatterName, _ purity: Purity, _ p: Perceiver) -> ProcessSheet.Sensed {
        ProcessSheet.Sensed(name: p.name(of: name), percent: purity.basisPoints / 100)
    }

    /// 所見の文({0} {1} を引数で埋める)。文の定義が無ければ認識の層の「わからない」。
    func findingText(_ id: FindingID, _ args: [FindingArg], _ p: Perceiver) -> String {
        let text = content.findings[id]?.text ?? Perceiver.unknownText
        return p.text(text, argStrings(args, p))
    }

    func noteText(_ n: NoteEntry, _ p: Perceiver) -> String {
        p.text(n.text, argStrings(n.args, p))
    }

    private func argStrings(_ args: [FindingArg], _ p: Perceiver) -> [String: String] {
        var out: [String: String] = [:]
        for (i, a) in args.enumerated() {
            out["\(i)"] = switch a {
            case .item(let it): p.name(Subject.item(it))
            case .module(let m): p.name(Subject.module(m))
            case .shape(let s): p.name(Subject.namePart(.shape(s)))
            case .temper(let t): p.name(Subject.namePart(.temper(t)))
            case .purity(let q): "\(HandSense.estimate(q).basisPoints / 100)%"
            }
        }
        return out
    }
}
