import RFKernel

/// 周回・巻き戻し・失敗。持ち主: RFFailure。
public struct RunState: Codable, Equatable, Sendable {
    /// 何周目か(1 から。記憶を持って巻き戻すと増える)。
    public var index: Int = 1
    public var outcome: RunOutcome = .ongoing
    /// 前の周回で起きたことのうち、覚えておくもの(仲間の「前にもこうなった気がする」の元)。古い順。
    public var pastLives: [PastLife] = []
    /// 記憶を持って巻き戻した回数(来歴にも .rewound の記録が残る)。
    public var rewinds: Int = 0
    /// 失って続けた回数(来歴にも .continuedWithLoss の記録が残る)。
    public var losses: Int = 0
    /// 巻き戻し・失って続けるの直後に、次のステップで出来事として知らせる来歴(FailureSystem が出して消す)。
    /// 4 択は本体の外(GameHost)で世界を作り直すので、出来事はここを通して本体の中で配る。
    public var resumeNotice: ProvenanceID?

    public init() {}

    public var isActive: Bool { outcome == .ongoing }

    /// 前の周回の記録を ID で引く(巻き戻しで来歴から消えた記録を、持ち越した物・記憶・事実から辿るため)。
    public func pastRecord(_ id: ProvenanceID) -> ProvenanceRecord? {
        for life in pastLives.reversed() {
            if let r = life.memorable.first(where: { $0.id == id }) ?? life.references.first(where: { $0.id == id }) {
                return r
            }
        }
        return nil
    }
}

public enum RunOutcome: Codable, Equatable, Sendable {
    case ongoing
    /// 失敗した(4 択を待つ)。原因は文字列表のキー。来歴で何が起きたかを指す。
    case failed(cause: TextID, record: ProvenanceID?)
    /// 結末に着いた。
    case ended(EndingID)
}

/// 巻き戻しで終わった周回 1 つの記録。
public struct PastLife: Codable, Equatable, Sendable {
    public var run: Int
    public var endedDay: Int
    public var endedAt: GameTime
    /// どの夜明けへ戻ったか。
    public var rewoundToDay: Int
    public var cause: TextID
    /// 覚えておく記録(コンテンツが memorable とした印の付いた記録と、失敗の記録の写し)。
    public var memorable: [ProvenanceRecord]
    /// 持ち越した物(知った事実・ノート・仲間の記憶)が指している記録の写し(巻き戻しで来歴から消えるので)。
    public var references: [ProvenanceRecord]

    public init(run: Int, endedDay: Int, endedAt: GameTime = .zero, rewoundToDay: Int = 0, cause: TextID,
                memorable: [ProvenanceRecord], references: [ProvenanceRecord] = []) {
        self.run = run
        self.endedDay = endedDay
        self.endedAt = endedAt
        self.rewoundToDay = rewoundToDay
        self.cause = cause
        self.memorable = memorable
        self.references = references
    }
}
