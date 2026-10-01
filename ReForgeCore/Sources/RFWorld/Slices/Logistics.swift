import RFKernel

/// 運搬と(R2 の)電力。持ち主: RFLogistics。
/// 隣接で向きが合うモジュールのつながりは置き場所から毎回計算する(保存しない)。
/// 離れたモジュールの間は運搬の経路で結び、仲間が実際に歩いて運ぶ。
public struct LogisticsState: Codable, Equatable, Sendable {
    public var routes: [EntityID: HaulRoute] = [:]
    /// 電力網(R2)。形は担当が決める。
    public var power: [String: Int] = [:]

    public init() {}
}

public struct HaulRoute: Codable, Equatable, Sendable {
    public var id: EntityID
    public var from: EntityID
    public var to: EntityID
    /// 担当の仲間(Assignment.haul と対になる)。
    public var haulers: [PersonID]
    /// 昨日運んだ数(流量の表示)。
    public var movedYesterday: Int = 0
    public var movedToday: Int = 0

    public init(id: EntityID, from: EntityID, to: EntityID, haulers: [PersonID] = []) {
        self.id = id
        self.from = from
        self.to = to
        self.haulers = haulers
    }
}
