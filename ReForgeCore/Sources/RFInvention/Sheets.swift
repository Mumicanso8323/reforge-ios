import RFContent
import RFKernel
import RFMatter
import RFRules
import RFWorld

/// 工程表の出所。設計画面の縦一列の表は物のライン専用にしない(結合設計 REQ-S8):
/// ライン札・試作・設計画面の下書き・コンテンツの記録(SheetDef。後で任意の記録など)を同じ形で開く。
public enum SheetSource: Equatable, Sendable {
    case design(EntityID)
    case trial(ProvenanceID)
    case record(SheetID)
    /// 設計画面の下書き(まだ試しても札にしてもいない並び)。input は試すつもりの物(見込みの照合に使う)。
    case draft(steps: [ProcessStep], input: Matter?)
}

public enum SheetTitle: Equatable, Sendable {
    /// 文字列表のキー(ライン札・試作・下書き)。
    case text(TextID)
    /// 認識の表の見出し(コンテンツの記録。見え方が事実で変わる)。
    case subject(SubjectID)
}

/// 工程表の 1 行。文字は持たない(見出しと ID だけ。画面が認識の層で引く)。
public struct SheetRow: Equatable, Sendable {
    /// 行の見出し(module:<id> など)。
    public var subject: SubjectID
    /// 行の横の選択(燃料・混ぜ物)。
    public var inputs: [ItemID]
    /// 行の注記(コンテンツの記録のとき)。
    public var note: TextID?
    /// 工程の行なら、その段。
    public var step: ProcessStep?
    /// この段を通った後の見込み(試した並びだけ。nil は「？」)。
    public var forecast: Forecast?

    public init(subject: SubjectID, inputs: [ItemID] = [], note: TextID? = nil, step: ProcessStep? = nil,
                forecast: Forecast? = nil) {
        self.subject = subject
        self.inputs = inputs
        self.note = note
        self.step = step
        self.forecast = forecast
    }
}

/// 見込み(既に試した工程の組み合わせから分かる、その段を通った後の物)。
public struct Forecast: Equatable, Sendable {
    public var name: MatterName
    /// 純度の見当(ノアの手)。
    public var sensed: Purity
    /// その段で載った所見。
    public var findings: [FindingID]
    /// どの試作で確かめたか。
    public var from: ProvenanceID
}

/// 表の頭(入力の物と、ノアの手の見当。「鉄鉱石 ── ノアの手: 三割くらい」)。
public struct SheetHead: Equatable, Sendable {
    public var name: MatterName
    public var sensed: Purity
}

/// 試作の結果カード(物・純度の見当・硬さ・粘り・副産物・所見・使った物)。
public struct TrialCard: Equatable, Sendable {
    public var record: ProvenanceID
    public var name: MatterName
    public var sensed: Purity
    public var hardness: Int
    public var toughness: Int
    public var byproducts: [ByproductID]
    public var findings: [Finding]
    /// 実際に使った物(1 単位ぶん × 数)。
    public var consumed: [ItemAmount]
    public var quantity: Int
    /// 最初の鉄などの唯一品になったとき。
    public var unique: EntityID?
}

/// 工程表(設計画面の部品で描く中身)。
public struct SheetModel: Equatable, Sendable {
    public var source: SheetSource
    public var title: SheetTitle
    public var head: SheetHead?
    public var rows: [SheetRow]
    /// 試作の結果カード(試作の表のとき)。
    public var card: TrialCard?
    /// 並び全体の見込み(ライン札・下書き。試していなければ nil)。
    public var expected: Forecast?
}

/// 工程表を作る(真実の ID と数だけ。文字にするのは画面と認識の層)。
public enum Sheets {
    public static func model(_ source: SheetSource, world w: WorldState, content: ContentDB) -> SheetModel? {
        switch source {
        case .design(let id):
            guard let d = w.invention.designs[id] else { return nil }
            let input = d.trial.flatMap { r in w.notebook.trials.first { $0.record == r }?.input }
            let f = forecast(d.steps, input: input, notebook: w.notebook)
            return SheetModel(source: source, title: .text(InventionTexts.designSheet),
                              head: input.map(head), rows: rows(d.steps, f), card: nil,
                              expected: expected(d.steps, input: input, notebook: w.notebook))
        case .trial(let rec):
            guard let t = w.notebook.trials.first(where: { $0.record == rec }) else { return nil }
            let f = own(t)
            return SheetModel(source: source, title: .text(InventionTexts.trialSheet), head: head(t.input),
                              rows: rows(t.steps, f), card: card(t), expected: nil)
        case .record(let sid):
            guard let def = content.sheets[sid],
                  ConditionEvaluator.evaluatePure(def.when, world: w, content: content) == true
            else { return nil }
            let rows = def.rows.compactMap { r -> SheetRow? in
                if let c = r.when, ConditionEvaluator.evaluatePure(c, world: w, content: content) != true { return nil }
                return SheetRow(subject: r.subject, note: r.note)
            }
            return SheetModel(source: source, title: .subject(def.title), head: nil, rows: rows, card: nil,
                              expected: nil)
        case .draft(let steps, let input):
            let f = forecast(steps, input: input, notebook: w.notebook)
            return SheetModel(source: source, title: .text(InventionTexts.draftSheet), head: input.map(head),
                              rows: rows(steps, f), card: nil,
                              expected: expected(steps, input: input, notebook: w.notebook))
        }
    }

    /// 並び全体の見込み: ちょうど同じ並びを同じ入力で試したことがあれば、その最後の物(冷え方まで含む)。
    public static func expected(_ steps: [ProcessStep], input: Matter?, notebook: NotebookState) -> Forecast? {
        guard let t = matching(input, notebook).first(where: { $0.steps == steps }) else { return nil }
        return Forecast(name: t.outcome.name, sensed: HandSense.estimate(t.outcome.product),
                        findings: t.outcome.findings.filter { $0.step == nil }.map(\.id), from: t.record)
    }

    /// 同じ入力で試した記録(新しい順)。
    static func matching(_ input: Matter?, _ notebook: NotebookState) -> [TrialRecord] {
        notebook.trials.reversed().filter { t in
            guard let input else { return true }
            return t.input.stage == input.stage && t.input.shape == input.shape
                && t.input.substance == input.substance && HandSense.estimate(t.input) == HandSense.estimate(input)
        }
    }

    /// 下書きの各段の見込み。同じ入力(形と段階が同じで、ノアの手の見当が同じ物)で、先頭からその段まで同じ並びを
    /// 試したことがあれば、その試作の途中の物を出す(新しい試作を優先)。無ければ nil(「？」)。
    /// input が nil なら入力は問わない。
    public static func forecast(_ steps: [ProcessStep], input: Matter?, notebook: NotebookState) -> [Forecast?] {
        let candidates = matching(input, notebook)
        return steps.indices.map { i in
            let prefix = Array(steps[0...i])
            guard let t = candidates.first(where: { $0.steps.count > i && Array($0.steps[0...i]) == prefix }) else {
                return nil
            }
            return cell(t, at: i)
        }
    }

    public static func card(_ t: TrialRecord) -> TrialCard {
        TrialCard(
            record: t.record, name: t.outcome.name, sensed: HandSense.estimate(t.outcome.product),
            hardness: t.outcome.hardness, toughness: t.outcome.toughness, byproducts: t.outcome.byproducts,
            findings: t.outcome.findings,
            consumed: t.outcome.consumed.map { ItemAmount($0.item, $0.quantity * t.quantity) }, quantity: t.quantity,
            unique: t.unique)
    }

    static func own(_ t: TrialRecord) -> [Forecast?] { t.steps.indices.map { cell(t, at: $0) } }

    static func cell(_ t: TrialRecord, at i: Int) -> Forecast? {
        guard i < t.outcome.trace.count else { return nil }
        let after = t.outcome.trace[i].after
        return Forecast(name: NameGenerator.name(for: after), sensed: HandSense.estimate(after),
                        findings: t.outcome.findings.filter { $0.step == i }.map(\.id), from: t.record)
    }

    static func head(_ m: Matter) -> SheetHead { SheetHead(name: NameGenerator.name(for: m), sensed: HandSense.estimate(m)) }

    static func rows(_ steps: [ProcessStep], _ f: [Forecast?]) -> [SheetRow] {
        steps.enumerated().map { i, s in
            SheetRow(subject: Subject.module(s.module), inputs: s.inputItems, step: s, forecast: i < f.count ? f[i] : nil)
        }
    }
}
