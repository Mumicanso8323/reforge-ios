/// 層の ID。いまは地表だけ。地下(深さ 1〜)や別の場所は ID を足して層を加える(layered-map-architecture)。
public struct MapLayerID: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }

    /// 地表。
    public static let surface = MapLayerID("surface")
    /// 地下の深さ n の層(R2 以降)。
    public static func underground(_ depth: Int) -> MapLayerID { MapLayerID("underground.\(depth)") }

    public static func < (a: MapLayerID, b: MapLayerID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// 層の中のマス(層 ID つきの座標)。層をまたぐ参照(地下への入口など)に使う。
public struct MapLocation: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var layer: MapLayerID
    public var point: GridPoint

    public init(_ layer: MapLayerID, _ point: GridPoint) {
        self.layer = layer
        self.point = point
    }

    public var description: String { "\(layer)\(point)" }
}

/// 1 つの層。地形・配置物・鉱脈・視界を同じ大きさで重ねて持つ(地表バイオーム/配置物/地下鉱脈/視界のレイヤー)。
public struct MapLayer: Codable, Equatable, Sendable {
    public let id: MapLayerID
    public var size: MapSize { terrain.size }
    public internal(set) var terrain: TerrainGrid
    public var placements: PlacementLayer
    public var deposits: DepositLayer
    public var visibility: VisibilityLayer

    public init(id: MapLayerID, terrain: TerrainGrid) {
        self.id = id
        self.terrain = terrain
        self.placements = PlacementLayer()
        self.deposits = DepositLayer()
        self.visibility = VisibilityLayer(size: terrain.size)
    }

    /// マスの地形(地図の外は nil)。
    public func biome(at p: GridPoint) -> Biome? { terrain.biome(at: p) }

    /// 上下左右か斜めに水辺があるか(水辺に接する、の判定)。
    public func touchesWater(_ p: GridPoint) -> Bool {
        p.neighbors8.contains { terrain.biome(at: $0) == .water }
    }

    /// 経路探索(この層の地形と視界で)。
    public func findPath(from start: GridPoint, to goal: GridPoint, costs: MoveCostTable = .original,
                         options: PathOptions = PathOptions()) -> MapPath? {
        Pathfinder.findPath(in: self, from: start, to: goal, costs: costs, options: options)
    }
}
