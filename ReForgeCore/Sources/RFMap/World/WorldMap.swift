import RFKernel

/// チャンクの座標(POI と鉱脈を置く単位)。
public struct ChunkCoord: Codable, Equatable, Hashable, Comparable, Sendable {
    public var cx: Int
    public var cy: Int
    public init(_ cx: Int, _ cy: Int) { self.cx = cx; self.cy = cy }
    public static func < (a: ChunkCoord, b: ChunkCoord) -> Bool { (a.cy, a.cx) < (b.cy, b.cx) }
}

/// 視界を動かした結果。
public struct VisionUpdate: Equatable, Sendable {
    /// 使った半径。
    public var radius: Int
    /// 新しく既知になったマスの数。
    public var newlyExplored: Int
    /// 新しく見つけた配置物(残骸・遺跡・巣など)。
    public var discoveredPlacements: [PlacementID]
    /// 新しく見つけた鉱脈。
    public var discoveredDeposits: [DepositID]
}

/// 地図の生成の失敗。
public enum MapGenerationError: Error, Equatable, Sendable {
    /// 地図が小さすぎて目印を置けない。
    case mapTooSmall(MapSize)
    /// やり直しの上限まで試しても位置関係の保証を満たせなかった。
    case layoutNotFound(attempts: Int)
}

/// 生成の記録。
public struct GenerationReport: Codable, Equatable, Sendable {
    /// 目印の配置を何回目で決めたか(1 から)。
    public var attempts: Int
    /// 位置関係の保証を満たしたか(false は `allowUnverifiedFallback` のときだけ)。
    public var verified: Bool

    public init(attempts: Int, verified: Bool) {
        self.attempts = attempts
        self.verified = verified
    }
}

/// 地図全体(原作 `WorldMap` を層に分けたもの = layered-map-architecture の LayeredWorldMap)。
/// 値型。GameState には依存しない。seed と設定が同じなら同じ地図になる。
public struct WorldMap: Codable, Equatable, Sendable {
    /// 地図の seed(生成時に渡された乱数から 1 回引いたもの)。チャンクと層の決定的な生成に使う。
    public let seed: UInt64
    public let config: MapGenerationConfig
    /// 目印(生成した地図だけ。手で作った地図は nil)。
    public let landmarks: Landmarks?
    public let minerals: MineralField
    /// 拠点の整地済みの範囲(地表)。
    public var baseArea: GridRect?
    /// ノアが目覚めた場所。
    public var spawn: WorldPoint
    public private(set) var layers: [MapLayerID: MapLayer]
    /// POI と鉱脈を置き終えた地表のチャンク。
    public private(set) var generatedChunks: Set<ChunkCoord>
    /// 生成の記録(試行回数・保証を満たしたか)。手で作った地図は nil。
    public let generationReport: GenerationReport?

    init(seed: UInt64, config: MapGenerationConfig, landmarks: Landmarks, surface: MapLayer, report: GenerationReport) {
        self.seed = seed
        self.config = config
        self.landmarks = landmarks
        self.generationReport = report
        let b = landmarks.base
        self.baseArea = GridRect(origin: b.minCorner, size: GridSize(width: b.width, height: b.height))
        self.spawn = WorldPoint(.surface, b.center)
        self.minerals = MineralField(seed: seed)
        self.layers = [.surface: surface]
        self.generatedChunks = []
    }

    // MARK: 生成

    /// 渡された乱数で地図を作る(乱数は 1 回だけ進む)。
    /// 地図が小さすぎるとき、位置関係の保証を満たせないときは投げる(未検証の地図を黙って返さない)。
    public static func generate(config: MapGenerationConfig = .r1, rng: inout SeededRandom) throws -> WorldMap {
        try WorldMapGenerator.generate(config: config, rng: &rng)
    }

    /// seed から地図を作る。
    public static func generate(seed: UInt64, config: MapGenerationConfig = .r1) throws -> WorldMap {
        var rng = SeededRandom(state: seed)
        return try generate(config: config, rng: &rng)
    }

    // MARK: 層

    public var size: MapSize { config.size }

    /// 地表の層。
    public var surface: MapLayer {
        get { layers[.surface]! }
        set { layers[.surface] = newValue }
    }

    public subscript(_ id: MapLayerID) -> MapLayer? {
        get { layers[id] }
        set { layers[id] = newValue }
    }

    /// 層を足す(地下など)。同じ ID があれば置き換える。
    public mutating func addLayer(_ layer: MapLayer) {
        layers[layer.id] = layer
    }

    /// 手で作る地図(試験用の平らな地図など)。目印と生成の記録は持たない。辞書の鍵を層の ID にする。
    public init(layers: [LayerID: MapLayer], baseArea: GridRect?, spawn: WorldPoint) {
        var ls: [LayerID: MapLayer] = [:]
        for (id, var l) in layers {
            l.id = id
            ls[id] = l
        }
        let size = layers[.surface]?.size ?? layers.values.first?.size ?? .r1
        self.seed = 0
        self.config = MapGenerationConfig(size: size)
        self.landmarks = nil
        self.minerals = MineralField(seed: 0)
        self.layers = ls
        self.generatedChunks = []
        self.generationReport = nil
        self.baseArea = baseArea
        self.spawn = spawn
    }

    /// 層の ID の一覧(並びは固定)。
    public var layerIDs: [MapLayerID] { layers.keys.sorted() }

    // MARK: 参照

    /// 地表のマスの地形。
    public func biome(at p: GridPoint, layer: MapLayerID = .surface) -> Biome? {
        layers[layer]?.biome(at: p)
    }

    /// 地表のマスの環境パラメータ(温度・水分・地質・汚れ)。
    public func environment(at p: GridPoint) -> EnvironmentParams {
        surface.terrain.field.params(at: p)
    }

    /// マスの見え方。
    public func visibility(at p: GridPoint, layer: MapLayerID = .surface) -> TileVisibility {
        layers[layer]?.visibility.state(at: p) ?? .unseen
    }

    // MARK: 視界

    /// ノアのいる位置から視界を更新し、視界に入った配置物・鉱脈・層の接続を発見済みにする。
    /// 視界の円の中のマスから占有と鉱脈の索引を引く(全部の配置物を毎回なめない)。
    @discardableResult
    public mutating func updateVision(at center: GridPoint, isNight: Bool, hasTorch: Bool,
                                      layer id: MapLayerID = .surface) -> VisionUpdate {
        let r = config.vision.radius(isNight: isNight, hasTorch: hasTorch)
        guard var layer = layers[id] else {
            return VisionUpdate(radius: r, newlyExplored: 0, discoveredPlacements: [], discoveredDeposits: [])
        }
        let added = layer.visibility.update(center: center, radius: r)
        var foundP = Set<PlacementID>()
        var foundD: [DepositID] = []
        for p in VisionRule.cells(center: center, radius: r, in: layer.size) {
            if let pl = layer.placements.placement(at: p), !pl.isDiscovered, !foundP.contains(pl.id) {
                foundP.insert(pl.id)
            }
            if let d = layer.deposits.deposit(at: p), !d.isDiscovered {
                foundD.append(d.id)
            }
        }
        for pid in foundP { layer.placements.update(pid) { $0.isDiscovered = true } }
        for did in foundD { layer.deposits.update(did) { $0.isDiscovered = true } }
        for c in layer.connections where !c.isDiscovered && layer.visibility.isInView(c.at) {
            layer.markConnectionDiscovered(c.id)
        }
        layers[id] = layer
        return VisionUpdate(radius: r, newlyExplored: added, discoveredPlacements: foundP.sorted(),
                            discoveredDeposits: foundD.sorted())
    }

    // MARK: 経路

    /// 経路探索。既定はプレイヤーのタップ用(霧の先は平地と仮定し、`.throughFog` なら歩いて晴れるたびに引き直す)。
    public func route(from start: GridPoint, to goal: GridPoint, layer id: MapLayerID = .surface,
                      costs: MoveCostTable = .original, options: PathOptions = .tap,
                      workspace: PathWorkspace? = nil) -> PathOutcome {
        layers[id]?.route(from: start, to: goal, costs: costs, options: options, workspace: workspace) ?? .blocked
    }

    /// 経路だけが欲しいとき(届かなければ nil)。
    public func findPath(from start: GridPoint, to goal: GridPoint, layer id: MapLayerID = .surface,
                         costs: MoveCostTable = .original, options: PathOptions = .tap) -> MapPath? {
        route(from: start, to: goal, layer: id, costs: costs, options: options).path
    }

    // MARK: 層をまたぐ接続

    /// 2 つの層のマスを両方向につなぐ(入口・階段)。
    public mutating func connect(_ a: MapLocation, _ b: MapLocation, kind: ConnectionKind, id: String) {
        guard layers[a.layer] != nil, layers[b.layer] != nil else { return }
        layers[a.layer]!.addConnection(LayerConnection(id: id, kind: kind, at: a.point, to: b))
        layers[b.layer]!.addConnection(LayerConnection(id: id, kind: kind, at: b.point, to: a))
    }

    // MARK: 鉱脈

    /// 鉱脈を 1 回掘る。鉱脈が無いか枯れていれば nil。
    public mutating func extract(_ deposit: DepositID, layer id: MapLayerID = .surface,
                                 rng: inout SeededRandom) -> [OreYield]? {
        guard var layer = layers[id] else { return nil }
        let y = layer.deposits.extract(deposit, rng: &rng)
        layers[id] = layer
        return y
    }

    // MARK: チャンク(大きい地図の遅延生成)

    /// チャンクの数(横・縦)。
    public var chunkCounts: (x: Int, y: Int) {
        let cs = config.chunkSize
        return ((size.width + cs - 1) / cs, (size.height + cs - 1) / cs)
    }

    public func chunk(containing p: GridPoint) -> ChunkCoord {
        ChunkCoord(p.x / config.chunkSize, p.y / config.chunkSize)
    }

    /// 位置のまわりのチャンクに POI と鉱脈を置く(置き済みなら何もしない)。チャンクの中身は生成の順番に依らない。
    /// 新しく置いた配置物に世界の実体 ID を振るときは allocate を渡す。
    public mutating func ensureGenerated(around p: GridPoint, radiusChunks: Int = 1, allocate: (() -> EntityID)? = nil) {
        let c = chunk(containing: p)
        let (nx, ny) = chunkCounts
        for cy in (c.cy - radiusChunks)...(c.cy + radiusChunks) where cy >= 0 && cy < ny {
            for cx in (c.cx - radiusChunks)...(c.cx + radiusChunks) where cx >= 0 && cx < nx {
                populate(ChunkCoord(cx, cy))
            }
        }
        if let allocate { assignEntities(allocate) }
    }

    /// 実体 ID の無い配置物に ID を振る(層の ID 順 → 配置物の ID 順。決定的)。
    public mutating func assignEntities(_ allocate: () -> EntityID) {
        for lid in layerIDs {
            var layer = layers[lid]!
            for p in layer.placements.all where p.entity == nil {
                layer.placements.update(p.id) { $0.entity = allocate() }
            }
            layers[lid] = layer
        }
    }

    mutating func generateAllChunks() {
        let (nx, ny) = chunkCounts
        for cy in 0..<ny { for cx in 0..<nx { populate(ChunkCoord(cx, cy)) } }
    }

    private mutating func populate(_ c: ChunkCoord) {
        guard !generatedChunks.contains(c) else { return }
        var layer = surface
        guard let landmarks else { return }
        WorldMapGenerator.populateChunk(&layer, chunk: c, seed: seed, landmarks: landmarks, config: config, minerals: minerals)
        surface = layer
        generatedChunks.insert(c)
    }

    // MARK: Codable(層とチャンクは並びを固定して書く)

    private enum CodingKeys: String, CodingKey { case seed, config, landmarks, layers, generatedChunks, generationReport, baseArea, spawn }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seed = try c.decode(UInt64.self, forKey: .seed)
        config = try c.decode(MapGenerationConfig.self, forKey: .config)
        landmarks = try c.decodeIfPresent(Landmarks.self, forKey: .landmarks)
        minerals = MineralField(seed: seed)
        let ls = try c.decode([MapLayer].self, forKey: .layers)
        layers = Dictionary(uniqueKeysWithValues: ls.map { ($0.id, $0) })
        generatedChunks = Set(try c.decode([ChunkCoord].self, forKey: .generatedChunks))
        generationReport = try c.decodeIfPresent(GenerationReport.self, forKey: .generationReport)
        baseArea = try c.decodeIfPresent(GridRect.self, forKey: .baseArea)
        spawn = try c.decode(WorldPoint.self, forKey: .spawn)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
        try c.encode(config, forKey: .config)
        try c.encodeIfPresent(landmarks, forKey: .landmarks)
        try c.encode(layerIDs.map { layers[$0]! }, forKey: .layers)
        try c.encode(generatedChunks.sorted(), forKey: .generatedChunks)
        try c.encodeIfPresent(generationReport, forKey: .generationReport)
        try c.encodeIfPresent(baseArea, forKey: .baseArea)
        try c.encode(spawn, forKey: .spawn)
    }
}
