import RFKernel
import RFMatter

/// ライン札(設計画面で決めた並び)。持ち主: RFInvention。
public struct InventionState: Codable, Equatable, Sendable {
    public var designs: [EntityID: LineDesign] = [:]

    public init() {}
}

public struct LineDesign: Codable, Equatable, Sendable {
    public var id: EntityID
    /// 最初に入れる物の種類(鉱石など)。
    public var input: ItemKindID
    public var steps: [ProcessStepSpec]
    /// 札にしたときの来歴(どの試作から作ったか inputs で辿れる)。
    public var origin: ProvenanceID
    /// 試作で確かめた結果(未確認なら nil)。
    public var expected: MaterialProfile?

    public init(id: EntityID, input: ItemKindID, steps: [ProcessStepSpec], origin: ProvenanceID,
                expected: MaterialProfile?) {
        self.id = id
        self.input = input
        self.steps = steps
        self.origin = origin
        self.expected = expected
    }
}

/// 実験ノート・図鑑・聞いたヒント。持ち主: RFInvention。巻き戻しで持ち越す(記憶)。
/// ノートは事実だけを書く(規則をまとめない。推理をプレイヤーから取らない)。
public struct NotebookState: Codable, Equatable, Sendable {
    public var trials: [TrialRecord] = []
    public var hints: [HintID: GameTime] = [:]
    /// 図鑑(物の種類 → 見たことのある最良の純度・形)。空欄は「まだ見ていない」。
    public var codex: [ItemKindID: CodexEntry] = [:]
    /// 手がかりの書き留め(端末の断片・仲間の知識・ノアの手ざわり・命名からの類推)。出典つき。
    /// 出典のラベルも認識の層で引くので、後で「誰が言ったか・何だったか」の見え方が変わる。
    public var notes: [NoteEntry] = []

    public init() {}
}

public struct NoteEntry: Codable, Equatable, Sendable {
    /// 何についての書き留めか(工程・物・地点…)。
    public var about: SubjectID
    /// 本文のキー(文字列表)。
    public var text: TextID
    /// 出典(人・端末・ノアの手…)。表示は認識の層。
    public var source: SubjectID
    public var record: ProvenanceID?
    public var at: GameTime
    public var run: Int

    public init(about: SubjectID, text: TextID, source: SubjectID, record: ProvenanceID?, at: GameTime, run: Int) {
        self.about = about
        self.text = text
        self.source = source
        self.record = record
        self.at = at
        self.run = run
    }
}

public struct TrialRecord: Codable, Equatable, Sendable {
    /// 試作の来歴(ledger の記録と同じ ID)。
    public var record: ProvenanceID
    public var at: GameTime
    public var run: Int
    public var input: MaterialProfile
    public var quantity: Int
    public var steps: [ProcessStepSpec]
    public var outcome: ChainOutcome

    public init(record: ProvenanceID, at: GameTime, run: Int, input: MaterialProfile, quantity: Int,
                steps: [ProcessStepSpec], outcome: ChainOutcome) {
        self.record = record
        self.at = at
        self.run = run
        self.input = input
        self.quantity = quantity
        self.steps = steps
        self.outcome = outcome
    }
}

public struct CodexEntry: Codable, Equatable, Sendable {
    public var bestPurity: Purity
    public var forms: Set<FormID>
    public var firstSeen: ProvenanceID?

    public init(bestPurity: Purity, forms: Set<FormID>, firstSeen: ProvenanceID?) {
        self.bestPurity = bestPurity
        self.forms = forms
        self.firstSeen = firstSeen
    }
}
