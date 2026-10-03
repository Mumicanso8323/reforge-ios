import RFKernel

public enum ConnectionKindTag {}
/// 層をまたぐ接続の種類(入口・階段など)。版をまたいで未知の種類も読めるよう文字列の ID。
public typealias ConnectionKind = TypedID<ConnectionKindTag>

extension TypedID where Tag == ConnectionKindTag {
    /// 洞窟や坑道の入口
    public static let entrance = ConnectionKind("entrance")
    /// 階段・はしご
    public static let stairs = ConnectionKind("stairs")
}

/// 層をまたぐ接続(この層のマス → 別の層のマス)。両方向なら相手の層にも逆向きを置く。
public struct LayerConnection: Codable, Equatable, Sendable {
    public let id: String
    public let kind: ConnectionKind
    /// この層の中の位置。
    public let at: GridPoint
    /// つながる先。
    public let to: MapLocation
    /// 視界に入ったことがあるか。
    public var isDiscovered: Bool

    public init(id: String, kind: ConnectionKind, at: GridPoint, to: MapLocation, isDiscovered: Bool = false) {
        self.id = id
        self.kind = kind
        self.at = at
        self.to = to
        self.isDiscovered = isDiscovered
    }
}

/// 1 つの層。地形・配置物・鉱脈・視界・層をまたぐ接続を同じ大きさで重ねて持つ
/// (地表バイオーム/配置物/地下鉱脈/視界のレイヤー)。
public struct MapLayer: Codable, Equatable, Sendable {
    public internal(set) var id: MapLayerID
    public var size: MapSize { terrain.size }
    public internal(set) var terrain: TerrainGrid
    public var placements: PlacementLayer
    public var deposits: DepositLayer
    public var visibility: VisibilityLayer
    /// 層をまたぐ接続(ID 順)。
    public private(set) var connections: [LayerConnection]
    /// 最初の火の置き場(生成の時に決める。古い保存は nil)。
    public internal(set) var firstFireSite: GridPoint?
    /// 夜明けに初めて見える物の置き場(生成の時に決める。古い保存は nil)。
    public internal(set) var dawnFindSite: GridPoint?

    public init(id: MapLayerID, terrain: TerrainGrid) {
        self.id = id
        self.terrain = terrain
        self.placements = PlacementLayer()
        self.deposits = DepositLayer()
        self.visibility = VisibilityLayer(size: terrain.size)
        self.connections = []
    }

    /// マスの地形(地図の外は nil)。
    public func biome(at p: GridPoint) -> Biome? { terrain.biome(at: p) }

    /// 上下左右か斜めに水(水辺・川・浅瀬)があるか(水に接する、の判定)。
    public func touchesWater(_ p: GridPoint) -> Bool {
        p.neighbors8.contains { terrain.biome(at: $0)?.isWet == true }
    }

    /// 経路探索(この層の地形と視界で)。既定はタップ用(霧の先は平地と仮定)。
    public func route(from start: GridPoint, to goal: GridPoint, costs: MoveCostTable = .original,
                      options: PathOptions = .tap, workspace: PathWorkspace? = nil) -> PathOutcome {
        Pathfinder.route(in: self, from: start, to: goal, costs: costs, options: options, workspace: workspace)
    }

    /// 経路だけが欲しいとき(届かなければ nil)。
    public func findPath(from start: GridPoint, to goal: GridPoint, costs: MoveCostTable = .original,
                         options: PathOptions = .tap) -> MapPath? {
        route(from: start, to: goal, costs: costs, options: options).path
    }

    /// 接続を足す。同じ ID があれば置き換える。
    public mutating func addConnection(_ c: LayerConnection) {
        precondition(size.contains(c.at), "接続は層の中に置く")
        connections.removeAll { $0.id == c.id }
        connections.append(c)
        connections.sort { $0.id < $1.id }
    }

    /// マスにある接続。
    public func connections(at p: GridPoint) -> [LayerConnection] { connections.filter { $0.at == p } }

    mutating func markConnectionDiscovered(_ id: String) {
        if let i = connections.firstIndex(where: { $0.id == id }) { connections[i].isDiscovered = true }
    }
}
