import RFKernel

/// 研究・スキル・解禁。持ち主: RFResearch(解禁は出来事の効果からも足される)。
public struct ResearchState: Codable, Equatable, Sendable {
    public var active: ResearchID?
    /// 研究の進み(点)。
    public var progress: [ResearchID: Int] = [:]
    public var completed: Set<ResearchID> = []
    /// 解禁された物(作れる・置ける・できる)。
    public var unlocked: UnlockSet = UnlockSet()

    public init() {}
}

/// 解禁の集合。
public struct UnlockSet: Codable, Equatable, Sendable {
    public var modules: Set<ModuleKindID> = []
    public var structures: Set<StructureKindID> = []
    public var handwork: Set<HandworkID> = []
    public var interactions: Set<InteractionID> = []
    public var research: Set<ResearchID> = []

    public init() {}
}
