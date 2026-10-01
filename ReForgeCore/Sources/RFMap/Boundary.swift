import RFKernel

// =====================================================================================
// RFMap の境界(設計担当が置いた骨組み)。
//
// 地図の実装担当(葉)はこのモジュールの持ち主。ここにある型の「形」は他の層が使う約束だが、
// 担当が先に作った型があればそちらを正とし、統合のときにこのファイルを合わせる/消す。
// 他の層が当てにしているのは次だけ(docs/architecture/B-data-model.md §3):
//   - MapState は値型で Codable・Equatable・Sendable。層(LayerID)ごとに MapLayer を持つ。
//   - マスの地形は真実の ID(TerrainID)。表示の文字・色・名前は持たない(RFPerception / RFPresent が引く)。
//   - 鉱脈は有限で、位置・種類(ItemKindID)・純度・残り回数を持つ。
//   - 生成・視界・経路は純粋関数で、乱数は渡された SeededRandom だけを使う。
// =====================================================================================

/// 地図全体。層を将来足せる(地表 LayerID.surface から始める)。
public struct MapState: Codable, Equatable, Sendable {
    public var layers: [LayerID: MapLayer]
    /// 拠点の整地済みの範囲(地表)。
    public var baseArea: GridRect?
    /// ノアが目覚めた場所。
    public var spawn: WorldPoint

    public init(layers: [LayerID: MapLayer], baseArea: GridRect?, spawn: WorldPoint) {
        self.layers = layers
        self.baseArea = baseArea
        self.spawn = spawn
    }

    public subscript(layer: LayerID) -> MapLayer? {
        get { layers[layer] }
        set { layers[layer] = newValue }
    }
}

/// 層 1 枚。
public struct MapLayer: Codable, Equatable, Sendable {
    public var size: GridSize
    /// 地形の種類の表(terrain の値はこの表の添字)。
    public var palette: [TerrainID]
    /// 行優先。値は palette の添字。
    public var terrain: [UInt16]
    /// 有限の鉱脈。
    public var deposits: [EntityID: DepositState]
    /// 生成時に置いた地点(残骸・遺跡・水場など)。調べた進み具合は RFWorld の探索の切れ端が持つ。
    public var pois: [EntityID: POIState]

    public init(size: GridSize, palette: [TerrainID], terrain: [UInt16],
                deposits: [EntityID: DepositState] = [:], pois: [EntityID: POIState] = [:]) {
        precondition(terrain.count == size.count, "terrain は size.count 個")
        self.size = size
        self.palette = palette
        self.terrain = terrain
        self.deposits = deposits
        self.pois = pois
    }

    public func terrain(at p: GridPoint) -> TerrainID? {
        guard size.contains(p) else { return nil }
        return palette[Int(terrain[size.index(p)])]
    }

    public mutating func setTerrain(_ t: TerrainID, at p: GridPoint) {
        guard size.contains(p) else { return }
        if let i = palette.firstIndex(of: t) {
            terrain[size.index(p)] = UInt16(i)
        } else {
            palette.append(t)
            terrain[size.index(p)] = UInt16(palette.count - 1)
        }
    }

    public func deposit(at p: GridPoint) -> (EntityID, DepositState)? {
        deposits.first { $0.value.at == p }.map { ($0.key, $0.value) }
    }
}

/// 鉱脈(有限・枯れる)。
public struct DepositState: Codable, Equatable, Sendable {
    public var at: GridPoint
    /// 出てくる鉱石の種類(真実。原作の item_id 例: "iron_ore")。見た目の名前は認識の層が引く。
    public var ore: ItemID
    public var purity: Purity
    public var remainingExtractions: Int

    public init(at: GridPoint, ore: ItemID, purity: Purity, remainingExtractions: Int) {
        self.at = at
        self.ore = ore
        self.purity = purity
        self.remainingExtractions = remainingExtractions
    }
}

/// 生成時に置いた地点。
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

// MARK: - コンテンツの定義(RFContent が読み込む。形は地図の担当が決める)

/// 地形の性質(表示は持たない)。
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

/// 地図の生成の設定(大きさ・バイオーム・POI・鉱脈の配り方)。中身は地図の担当が決める。
public struct MapGenConfig: Codable, Equatable, Sendable {
    public var size: GridSize
    /// 担当が形を決めるまでの入れ物。
    public var parameters: Value

    public init(size: GridSize, parameters: Value = .null) {
        self.size = size
        self.parameters = parameters
    }
}

// MARK: - 計算の約束(実装は地図の担当)

/// 地図の生成。同じ設定と seed からは同じ地図。
public protocol MapGenerating: Sendable {
    func generate(config: MapGenConfig, terrains: [TerrainID: TerrainDef], rng: inout SeededRandom,
                  allocate: () -> EntityID) -> MapState
}

/// 経路探索。通れない・届かないなら nil。
public protocol PathFinding: Sendable {
    func path(on layer: MapLayer, terrains: [TerrainID: TerrainDef], from: GridPoint, to: GridPoint,
              blocked: Set<GridPoint>) -> [GridPoint]?
}

/// 視界。見えているマスを返す(既知への書き込みは呼び出し側)。
public protocol VisibilityComputing: Sendable {
    func visible(on layer: MapLayer, terrains: [TerrainID: TerrainDef], from: GridPoint, radius: Int) -> [GridPoint]
}
