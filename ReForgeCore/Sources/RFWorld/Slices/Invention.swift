import RFKernel
import RFMatter

/// ライン札(設計画面で決めた並び)。持ち主: RFInvention。
public struct InventionState: Codable, Equatable, Sendable {
    public var designs: [EntityID: LineDesign] = [:]

    public init() {}
}

public struct LineDesign: Codable, Equatable, Sendable {
    public var id: EntityID
    /// 工程の並び(RFMatter の ProcessStep。採掘口が先頭なら鉱脈から始まる)。
    public var steps: [ProcessStep]
    /// 札にしたときの来歴(どの試作から作ったか inputs で辿れる)。
    public var origin: ProvenanceID
    /// 試作で確かめた結果(未確認なら nil)。
    public var expected: Matter?

    public init(id: EntityID, steps: [ProcessStep], origin: ProvenanceID, expected: Matter?) {
        self.id = id
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
    /// 図鑑(作った・見た物の名前 → 最良の純度)。空欄(まだ無い名前)は認識の表の「影」で出す。
    public var codex: [CodexEntry] = []
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
    public var input: Matter
    public var quantity: Int
    public var steps: [ProcessStep]
    /// 結果(物・名前の部品・硬さ・粘り・副産物・所見・使った物)。RFMatter の ChainResult。
    public var outcome: ChainResult

    public init(record: ProvenanceID, at: GameTime, run: Int, input: Matter, quantity: Int,
                steps: [ProcessStep], outcome: ChainResult) {
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
    public var name: MatterName
    public var bestPurity: Purity
    public var firstSeen: ProvenanceID?

    public init(name: MatterName, bestPurity: Purity, firstSeen: ProvenanceID?) {
        self.name = name
        self.bestPurity = bestPurity
        self.firstSeen = firstSeen
    }
}
