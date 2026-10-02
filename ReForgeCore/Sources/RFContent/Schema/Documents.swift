import RFKernel

/// 資料: 地図の上では 3 行までにした長い本文(場面の全文・会話の全文・メモの全文など)を、
/// プレイヤーがノートの記録から開いて読めるようにする定義(REQ-S3)。持ち主: 統合担当(型)/ U13(画面)。
///
/// - 状態を持たない: 条件 `when` が成り立っていれば記録に載る(巻き戻しでも、知った事実が残れば残る)。
/// - 本文は文字列表(`body`)。監査は文字列の門(textGates)で絞れる(門が無ければ全段で調べる)。
/// - `material` は非公開リポジトリの materials/ の元の md(生成スクリプトの出どころ。アプリは読まない)。
public struct DocumentDef: Codable, Equatable, Sendable {
    public var id: DocumentID
    public var title: TextID
    public var body: TextID
    /// 出典のラベルの見出し(認識の表。例 person:<id>・poi:<id>)。無ければ出典を出さない。
    public var source: SubjectID?
    /// 記録に載る条件。
    public var when: Condition
    /// 並び順(小さいほど上。同じなら id の順)。
    public var order: Int?
    public var material: String?
    /// 修理の段で本文と読める割合を選ぶ(U19。残骸の装置の資料など)。無ければいつも body。
    public var stages: DocumentStages?

    public init(id: DocumentID, title: TextID, body: TextID, source: SubjectID? = nil, when: Condition,
                order: Int? = nil, material: String? = nil, stages: DocumentStages? = nil) {
        self.stages = stages
        self.id = id
        self.title = title
        self.body = body
        self.source = source
        self.when = when
        self.order = order
        self.material = material
    }
}

extension DocumentDef: ContentDef {}

/// 資料の段(U19): ある POI の部品の修理の段階(POIProgress.repair。その種類の POI のうち最大)で、
/// 本文(■ で潰した行の多さ)と「読める割合」を選ぶ。段は atLeast の昇順に調べ、成り立った最後の段を使う。
/// どの段にも当たらなければ DocumentDef.body で、読める割合は出さない。
public struct DocumentStages: Codable, Equatable, Sendable {
    public var poiKind: POIKindID
    public var part: String
    public var steps: [DocumentStep]

    public init(poiKind: POIKindID, part: String, steps: [DocumentStep]) {
        self.poiKind = poiKind
        self.part = part
        self.steps = steps
    }
}

public struct DocumentStep: Codable, Equatable, Sendable {
    /// 修理の段階がこれ以上なら(0 = 壊れたまま)。
    public var atLeast: Int
    /// この段の本文(無ければ DocumentDef.body)。
    public var body: TextID?
    /// 読める割合(千分率。40 = 4%)。
    public var readablePermille: Int?

    public init(atLeast: Int, body: TextID? = nil, readablePermille: Int? = nil) {
        self.atLeast = atLeast
        self.body = body
        self.readablePermille = readablePermille
    }
}
