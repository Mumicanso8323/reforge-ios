import RFKernel

// =====================================================================================
// RFMap の境界(他の層が使う形)。
//
// 地図の型の正は RFMap の WorldMap / MapLayer(地図の担当)。設計担当が仮に置いた境界の形は、
// ここで RFMap の型への薄い適合にした:
//   - MapState は WorldMap の別名。層(LayerID)ごとに MapLayer を持つ。baseArea・spawn も持つ。
//   - マスの地形は真実の ID(TerrainID)で引ける(`MapLayer.terrain(at:)`)。中では Biome で持つ。
//   - POI は配置物(MapPlacement)。世界の実体 ID(EntityID)を振ったものを `MapLayer.pois` で引ける。
//   - 鉱脈は有限で、位置・種類・組成(純度)・残り回数を持つ(Deposit)。
//   - 生成・視界・経路は純粋関数で、乱数は渡された SeededRandom だけを使う。
// =====================================================================================

/// 世界状態が持つ地図(RFMap の WorldMap)。
public typealias MapState = WorldMap

extension MapLayer {
    /// 地形の ID の表と、その添字の並びから層を作る(試験用の平らな地図など)。
    /// palette の ID は Biome.terrainID のどれか(知らない ID は作れない)。
    public init(size: GridSize, palette: [TerrainID], terrain: [UInt16]) {
        precondition(terrain.count == size.count, "terrain は size.count 個")
        let biomes = palette.map { id -> Biome in
            guard let b = Biome(terrainID: id) else { preconditionFailure("地図の知らない地形: \(id)") }
            return b
        }
        self.init(id: .surface, terrain: TerrainGrid(size: size, cells: terrain.map { biomes[Int($0)] }))
    }

    /// マスの地形の ID(地図の外は nil)。
    public func terrain(at p: GridPoint) -> TerrainID? {
        terrain.biome(at: p)?.terrainID
    }

    /// マスの地形を ID で書き換える(試験用)。知らない ID は書けない。
    public mutating func setTerrain(_ t: TerrainID, at p: GridPoint) {
        guard let b = Biome(terrainID: t) else { preconditionFailure("地図の知らない地形: \(t)") }
        terrain.set(p, b)
    }

    /// 世界の実体 ID を振った POI(残骸・遺跡・巣など)。
    public var pois: [EntityID: POIState] {
        var out: [EntityID: POIState] = [:]
        for p in placements.all {
            guard let e = p.entity, p.kind != .module else { continue }
            out[e] = POIState(kind: POIKindID(p.templateID), at: p.anchor, footprint: p.footprint.offsets)
        }
        return out
    }
}

/// POI の見え方(世界状態から引く形)。中身は MapPlacement から作る。
public struct POIState: Codable, Equatable, Sendable {
    public var kind: POIKindID
    public var at: GridPoint
    /// 占めるマス(at からの相対)。1 マスなら [(0,0)]。
    public var footprint: [GridPoint]

    public init(kind: POIKindID, at: GridPoint, footprint: [GridPoint] = [GridPoint(0, 0)]) {
        self.kind = kind
        self.at = at
        self.footprint = footprint
    }
}

// MARK: - コンテンツの定義(RFContent が読み込む)

/// 地形の性質(表示は持たない)。id は Biome.terrainID と同じ。
public struct TerrainDef: Codable, Equatable, Sendable {
    public var id: TerrainID
    public var passable: Bool
    /// 1 マス進むのにかかる体力(千分率)。
    public var moveCost: Milli
    /// 水に接しているとみなすか(洗い樋の置き場の判定など)。
    public var isWater: Bool
    /// 自由なタグ(配置の制約で使う。例: "rock", "forest")。
    public var tags: [String]

    public init(id: TerrainID, passable: Bool, moveCost: Milli, isWater: Bool, tags: [String] = []) {
        self.id = id
        self.passable = passable
        self.moveCost = moveCost
        self.isWater = isWater
        self.tags = tags
    }
}

extension MoveCostTable {
    /// コンテンツの地形の定義から作る。定義の無い地形は原作の値のまま。
    public init(terrains: [TerrainID: TerrainDef]) {
        var c = MoveCostTable.original.costs
        for b in Biome.allCases {
            guard let d = terrains[b.terrainID] else { continue }
            c[b] = d.passable && d.moveCost.raw > 0 ? Int(d.moveCost.raw) : nil
        }
        self.init(c)
    }
}

/// 地図の生成の設定(コンテンツに書く形)。大きさだけを読み、残りは R1 の既定(MapGenerationConfig)。
public struct MapGenConfig: Codable, Equatable, Sendable {
    public var size: GridSize
    /// 予備(いまは読まない)。
    public var parameters: Value
    /// コンテンツが決める場所(砦など。U16)。距離の範囲を保証して置く。
    public var sites: [SiteRule]?
    /// 序盤の保証の値(W-12)。nil なら R1 の既定(OpeningRules.r1)。
    public var opening: OpeningRules?
    /// 岩山の奥の鉱脈(U19)。nil なら置かず、乱数も引かない。
    public var deepVein: DeepVeinRule?

    public init(size: GridSize, parameters: Value = .null, sites: [SiteRule]? = nil) {
        self.size = size
        self.parameters = parameters
        self.sites = sites
    }
}

// MARK: - 計算の約束

/// 地図の生成。同じ設定と seed からは同じ地図。
public protocol MapGenerating: Sendable {
    func generate(config: MapGenConfig, terrains: [TerrainID: TerrainDef], rng: inout SeededRandom,
                  allocate: () -> EntityID) -> MapState
}

/// RFMap の生成(本番の地図)。POI に世界の実体 ID を振る。
/// この約束は投げられないので、位置関係の保証を満たせないときは未検証の地図を返し、
/// `generationReport.verified == false` に残す(100 seed のテストで 0 件を確かめている)。
/// 目印を置けないほど小さい大きさはコンテンツの誤りとして止める。
public struct RFMapGenerator: MapGenerating {
    public init() {}

    public func generate(config: MapGenConfig, terrains: [TerrainID: TerrainDef], rng: inout SeededRandom,
                         allocate: () -> EntityID) -> MapState {
        // 生成器の最小の一辺より小さい指定は最小まで広げる(コンテンツの数で落ちない。公開の試験用の層は小さい)
        let side = MapGenerationConfig.minimumSide
        let size = GridSize(width: max(side, config.size.width), height: max(side, config.size.height))
        var c = MapGenerationConfig(size: size)
        c.allowUnverifiedFallback = true
        c.sites = config.sites
        if let o = config.opening { c.opening = o.scaled(to: size) }
        c.deepVein = config.deepVein
        do {
            var map = try WorldMap.generate(config: c, rng: &rng)
            map.assignEntities(allocate)
            return map
        } catch {
            preconditionFailure("地図を作れない(コンテンツの地図の大きさを見直す): \(error)")
        }
    }
}

/// 経路探索。通れない・届かないなら nil。
public protocol PathFinding: Sendable {
    func path(on layer: MapLayer, terrains: [TerrainID: TerrainDef], from: GridPoint, to: GridPoint,
              blocked: Set<GridPoint>) -> [GridPoint]?
}

/// RFMap の経路探索(霧を見ない。コストはコンテンツの地形の定義から)。
public struct RFMapPathFinder: PathFinding {
    public init() {}

    public func path(on layer: MapLayer, terrains: [TerrainID: TerrainDef], from: GridPoint, to: GridPoint,
                     blocked: Set<GridPoint>) -> [GridPoint]? {
        Pathfinder.route(in: layer, from: from, to: to, costs: MoveCostTable(terrains: terrains),
                         options: PathOptions(fog: .ignore, blocked: blocked)).path?.steps
    }
}

/// 視界。見えているマスを返す(既知への書き込みは呼び出し側)。
public protocol VisibilityComputing: Sendable {
    func visible(on layer: MapLayer, terrains: [TerrainID: TerrainDef], from: GridPoint, radius: Int) -> [GridPoint]
}

/// RFMap の視界(半径の円。遮るものは見ない = 原作どおり)。
public struct RFMapVisibility: VisibilityComputing {
    public init() {}

    public func visible(on layer: MapLayer, terrains: [TerrainID: TerrainDef], from: GridPoint, radius: Int) -> [GridPoint] {
        VisionRule.cells(center: from, radius: radius, in: layer.size)
    }
}
