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

    public init(id: DocumentID, title: TextID, body: TextID, source: SubjectID? = nil, when: Condition,
                order: Int? = nil, material: String? = nil) {
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
