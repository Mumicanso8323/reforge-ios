import RFKernel

/// 周回・巻き戻し・失敗。持ち主: RFFailure。
public struct RunState: Codable, Equatable, Sendable {
    /// 何周目か(1 から。巻き戻すと増える)。
    public var index: Int = 1
    public var outcome: RunOutcome = .ongoing
    /// 前の周回で起きたことのうち、覚えておくもの(仲間の「前にもこうなった気がする」の元)。
    public var pastLives: [PastLife] = []
    public var rewinds: Int = 0

    public init() {}

    public var isActive: Bool { outcome == .ongoing }
}

public enum RunOutcome: Codable, Equatable, Sendable {
    case ongoing
    /// 失敗した(4 択を待つ)。原因は文字列表のキー。来歴で何が起きたかを指す。
    case failed(cause: TextID, record: ProvenanceID?)
    /// 結末に着いた。
    case ended(EndingID)
}

public struct PastLife: Codable, Equatable, Sendable {
    public var run: Int
    public var endedDay: Int
    public var cause: TextID
    /// 覚えておく記録(コンテンツが memorable とした印の付いた記録の写し)。
    public var memorable: [ProvenanceRecord]

    public init(run: Int, endedDay: Int, cause: TextID, memorable: [ProvenanceRecord]) {
        self.run = run
        self.endedDay = endedDay
        self.cause = cause
        self.memorable = memorable
    }
}
