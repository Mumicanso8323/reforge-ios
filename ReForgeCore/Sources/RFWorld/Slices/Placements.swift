import RFKernel
import RFMatter

/// 地図に置いた物。持ち主: モジュールは RFProduction、建造物は RFBase。
public struct PlacementsState: Codable, Equatable, Sendable {
    public var items: [EntityID: Placement] = [:]

    public init() {}

    /// 位置の昇順(決定的に回すため)。
    public var sortedIDs: [EntityID] { items.keys.sorted() }

    public func at(_ p: WorldPoint) -> [EntityID] {
        items.filter { $0.value.covers(p) }.map(\.key).sorted()
    }
}

public enum PlaceableKind: Codable, Hashable, Sendable {
    case module(ModuleKindID)
    case structure(StructureKindID)
}

public struct Placement: Codable, Equatable, Sendable {
    public var id: EntityID
    public var kind: PlaceableKind
    public var at: WorldPoint
    public var facing: Direction
    /// 占めるマス(at からの相対。1 マスなら [(0,0)])。
    public var footprint: [GridPoint]
    /// 置いた・建てたときの来歴。後の開示が「あなたが置いたこれ」を指す。
    public var origin: ProvenanceID
    public var status: PlacementStatus
    public var module: ModuleRuntime?
    public var structure: StructureRuntime?

    public init(id: EntityID, kind: PlaceableKind, at: WorldPoint, facing: Direction,
                footprint: [GridPoint] = [GridPoint(0, 0)], origin: ProvenanceID, status: PlacementStatus) {
        self.id = id
        self.kind = kind
        self.at = at
        self.facing = facing
        self.footprint = footprint
        self.origin = origin
        self.status = status
    }

    public func covers(_ p: WorldPoint) -> Bool {
        p.layer == at.layer && footprint.contains { GridPoint(at.point.x + $0.x, at.point.y + $0.y) == p.point }
    }
}

public enum PlacementStatus: Codable, Equatable, Sendable {
    /// 建造中(進み具合 0...1000)。
    case underConstruction(progress: Int)
    case running
    /// 止まっている(理由は文字列表のキー。「燃料が来ていない」など)。
    case stopped(reason: TextID)
    /// 壊れた(R2 の保守)。
    case broken
}

/// 生産モジュールの動き。
public struct ModuleRuntime: Codable, Equatable, Sendable {
    /// どのライン札から置いたか(札なしで置いた単体なら nil)。
    public var design: EntityID?
    /// このモジュールが受け持つ工程。
    public var step: ProcessStepSpec?
    public var input: [StockEntry] = []
    public var output: [StockEntry] = []
    /// いまの 1 回の進み(ゲーム秒)。
    public var progress: Int64 = 0
    /// 付いている仲間。
    public var operatorID: PersonID?
    /// 1 日あたりの入出の集計(ボトルネックの表示)。
    public var today: ThroughputTally = ThroughputTally()
    public var yesterday: ThroughputTally = ThroughputTally()

    public init(design: EntityID?, step: ProcessStepSpec?) {
        self.design = design
        self.step = step
    }
}

public struct ThroughputTally: Codable, Equatable, Sendable {
    public var consumed: Int = 0
    public var produced: Int = 0
    /// 止まっていたゲーム秒。
    public var idleSeconds: Int64 = 0

    public init() {}
}

/// 建造物の動き(中身は建造物の種類ごと。R1: シェルター・焚き火台・柵・保管・炭焼き窯・研究机)。
public struct StructureRuntime: Codable, Equatable, Sendable {
    public var durability: Milli?
    /// 灯り・燃料などの種類ごとの値。形は RFBase の担当が決める。
    public var parameters: [String: Int] = [:]

    public init(durability: Milli? = nil) {
        self.durability = durability
    }
}
