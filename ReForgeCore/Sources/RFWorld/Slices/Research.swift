import RFKernel

/// 研究・スキル・解禁。持ち主: RFResearch(解禁は出来事の効果からも足される)。
///
/// 研究の進みは整数の「単位」で持つ(1 点 = `unitsPerPoint` 単位 = 3600 秒 × 千分率)。
/// 1 ステップの増分 = 速さ(点/時) × 15 秒 × 速さの千分率 なので、端数を落とさず、刻みによらず一致する。
public struct ResearchState: Codable, Equatable, Sendable {
    /// 1 点の単位数(1 時間の秒 × 千分率)。
    public static let unitsPerPoint: Int = 3600 * 1000

    /// いま進めている研究パッケージ(選ばなければ研究机は空回りする)。
    public var active: ResearchID?
    /// 研究の進み(単位。points(of:) で点)。切り替えても残る。
    public var progress: [ResearchID: Int] = [:]
    /// 研究パッケージの中で終わった段の数(段は順に進む)。
    public var nodesDone: [ResearchID: Int] = [:]
    public var completed: Set<ResearchID> = []
    /// 選んだときに物を使った研究(選び直しで二度使わない)。
    public var costPaid: Set<ResearchID> = []
    /// 解禁された物(作れる・置ける・できる)。
    public var unlocked: UnlockSet = UnlockSet()
    /// いまスキルを習っている人(BEAT-15: この間は学ぶ時期。生存の担当が食料の消費に使う)。
    public var learning: [PersonID: SkillLearning] = [:]
    /// 途中でやめたスキルの進み(秒 × 千分率)。選び直せば続きから。
    public var skillProgress: [PersonID: [SkillID: Int]] = [:]
    /// 夜作業で研究している人と、その終わり。
    public var nightSessions: [PersonID: GameTime] = [:]
    /// 前のステップで実際に研究を進めた人(ID 順)。生存の担当の「学ぶ時期」・画面の「誰が研究しているか」に使う。
    public var studying: [PersonID] = []

    public init() {}

    /// 研究の進み(点。切り捨て)。
    public func points(of id: ResearchID) -> Int { (progress[id] ?? 0) / Self.unitsPerPoint }

    /// その人がいま学ぶ時期か(研究を進めている・スキルを習っている)。BEAT-15。
    public func isLearning(_ p: PersonID) -> Bool { learning[p] != nil || studying.contains(p) }
}

/// 習っているスキルと進み。
public struct SkillLearning: Codable, Equatable, Sendable {
    public var skill: SkillID
    /// 進み(秒 × 千分率)。習得の時間 × 3600 × 1000 で身につく。
    public var progress: Int
    public var since: GameTime

    public init(skill: SkillID, progress: Int = 0, since: GameTime) {
        self.skill = skill
        self.progress = progress
        self.since = since
    }
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
