import RFKernel

// 深さの気配(答えを隠し、深さは隠さない)。最上位キー hintThemes・depthHints(perception/hints.json)。
// 事実(真実)ごとに「その答えの手前で、何かがあることだけを見せる主題」を並べ、監査(PerceptionHintAudit)が
// 主題がその段で画面に見えていて、見え方に禁止語が無いことを確かめる。どの項目も省略できる。
//
// 主題の見出しは認識の表と同じ「名前空間:ID」。認識の表を引かない種類:
//   scene:<SceneID>    場面の行の文字列
//   doc:<DocumentID>   資料の本文(段の本文も)
//   hint:<HintID>      手がかりの文
// それ以外(part:・poi:・item:・stat:・terrain:・research: …)は認識の表の見え方(名前が要る)。

/// まだ型・画面が無くて置けていない気配(誰が・何を)。監査は数えない。
public struct HintPending: Codable, Equatable, Sendable {
    public var owner: String
    public var what: String

    public init(owner: String, what: String) {
        self.owner = owner
        self.what = what
    }
}

/// 事実 1 つの気配の主題。
public struct HintTheme: Codable, Equatable, Sendable {
    public var fact: FactID
    /// 主題が見えている段(auditStages の id)。none のときは無い。
    public var stage: String?
    /// 計画の気配の番号(HNT-01 など)。
    public var hnt: [String]?
    public var subjects: [SubjectID]?
    /// 主題を置かず、数値や振る舞いで見せる気配の説明(監査は主題の代わりにこれがあれば良しとする)。
    public var rule: String?
    public var note: String?
    public var pending: [HintPending]?
    /// 気配を置かないと決めた理由(数や比較を出さない事実など)。
    public var none: String?

    public init(fact: FactID, stage: String? = nil, hnt: [String]? = nil, subjects: [SubjectID]? = nil,
                rule: String? = nil, note: String? = nil, pending: [HintPending]? = nil, none: String? = nil) {
        self.fact = fact
        self.stage = stage
        self.hnt = hnt
        self.subjects = subjects
        self.rule = rule
        self.note = note
        self.pending = pending
        self.none = none
    }
}

extension HintTheme: ContentDef {
    public var id: FactID { fact }
}

/// 工業・素材の段の気配(真実の事実に結び付かないもの。建てられない物の影など)。
public struct DepthHint: Codable, Equatable, Sendable {
    public var hnt: String
    public var what: String
    /// 見えている段(既定 r1_end)。
    public var stage: String?
    public var subjects: [SubjectID]?
    public var note: String?
    public var pending: [HintPending]?

    public init(hnt: String, what: String, stage: String? = nil, subjects: [SubjectID]? = nil, note: String? = nil,
                pending: [HintPending]? = nil) {
        self.hnt = hnt
        self.what = what
        self.stage = stage
        self.subjects = subjects
        self.note = note
        self.pending = pending
    }
}

extension DepthHint: ContentDef {
    public var id: String { hnt }
}
