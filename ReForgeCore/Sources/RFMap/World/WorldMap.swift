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

/// 地図全体(原作 `WorldMap` を層に分けたもの = layered-map-architecture の LayeredWorldMap)。
/// 値型。GameState には依存しない。seed と設定が同じなら同じ地図になる。
public struct WorldMap: Codable, Equatable, Sendable {
    /// 地図の seed(生成時に渡された乱数から 1 回引いたもの)。チャンクと層の決定的な生成に使う。
    public let seed: UInt64
    public let config: MapGenerationConfig
    public let landmarks: Landmarks
    public let minerals: MineralField
    public private(set) var layers: [MapLayerID: MapLayer]
    /// POI と鉱脈を置き終えた地表のチャンク。
    public private(set) var generatedChunks: Set<ChunkCoord>

    init(seed: UInt64, config: MapGenerationConfig, landmarks: Landmarks, surface: MapLayer) {
        self.seed = seed
        self.config = config
        self.landmarks = landmarks
        self.minerals = MineralField(seed: seed)
        self.layers = [.surface: surface]
        self.generatedChunks = []
    }

    // MARK: 生成

    /// 渡された乱数で地図を作る(乱数は 1 回だけ進む)。
    public static func generate(config: MapGenerationConfig = .r1, rng: inout SeededRandom) -> WorldMap {
        WorldMapGenerator.generate(config: config, rng: &rng)
    }

    /// seed から地図を作る。
    public static func generate(seed: UInt64, config: MapGenerationConfig = .r1) -> WorldMap {
        var rng = SeededRandom(state: seed)
        return generate(config: config, rng: &rng)
    }

    // MARK: 層

    public var size: MapSize { config.size }

    /// 地表の層。
    public var surface: MapLayer {
        get { layers[.surface]! }
        set { layers[.surface] = newValue }
    }

    public subscript(layer id: MapLayerID) -> MapLayer? {
        get { layers[id] }
        set { layers[id] = newValue }
    }

    /// 層を足す(地下など)。同じ ID があれば置き換える。
    public mutating func addLayer(_ layer: MapLayer) {
        layers[layer.id] = layer
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

    /// ノアのいる位置から視界を更新し、視界に入った配置物と鉱脈を発見済みにする。
    @discardableResult
    public mutating func updateVision(at center: GridPoint, isNight: Bool, hasTorch: Bool,
                                      layer id: MapLayerID = .surface) -> VisionUpdate {
        let r = config.vision.radius(isNight: isNight, hasTorch: hasTorch)
        guard var layer = layers[id] else {
            return VisionUpdate(radius: r, newlyExplored: 0, discoveredPlacements: [], discoveredDeposits: [])
        }
        let added = layer.visibility.update(center: center, radius: r)
        var foundP: [PlacementID] = []
        for p in layer.placements.all where !p.isDiscovered && p.cells.contains(where: layer.visibility.isInView) {
            layer.placements.update(p.id) { $0.isDiscovered = true }
            foundP.append(p.id)
        }
        var foundD: [DepositID] = []
        for d in layer.deposits.all where !d.isDiscovered && layer.visibility.isInView(d.position) {
            layer.deposits.update(d.id) { $0.isDiscovered = true }
            foundD.append(d.id)
        }
        layers[id] = layer
        return VisionUpdate(radius: r, newlyExplored: added, discoveredPlacements: foundP, discoveredDeposits: foundD)
    }

    // MARK: 経路

    /// 経路探索(既定では見たことのあるマスだけを通る)。
    public func findPath(from start: GridPoint, to goal: GridPoint, layer id: MapLayerID = .surface,
                         costs: MoveCostTable = .original, options: PathOptions = PathOptions()) -> MapPath? {
        layers[id]?.findPath(from: start, to: goal, costs: costs, options: options)
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
    public mutating func ensureGenerated(around p: GridPoint, radiusChunks: Int = 1) {
        let c = chunk(containing: p)
        let (nx, ny) = chunkCounts
        for cy in (c.cy - radiusChunks)...(c.cy + radiusChunks) where cy >= 0 && cy < ny {
            for cx in (c.cx - radiusChunks)...(c.cx + radiusChunks) where cx >= 0 && cx < nx {
                populate(ChunkCoord(cx, cy))
            }
        }
    }

    mutating func generateAllChunks() {
        let (nx, ny) = chunkCounts
        for cy in 0..<ny { for cx in 0..<nx { populate(ChunkCoord(cx, cy)) } }
    }

    private mutating func populate(_ c: ChunkCoord) {
        guard !generatedChunks.contains(c) else { return }
        var layer = surface
        WorldMapGenerator.populateChunk(&layer, chunk: c, seed: seed, landmarks: landmarks, config: config, minerals: minerals)
        surface = layer
        generatedChunks.insert(c)
    }

    // MARK: Codable(層とチャンクは並びを固定して書く)

    private enum CodingKeys: String, CodingKey { case seed, config, landmarks, layers, generatedChunks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seed = try c.decode(UInt64.self, forKey: .seed)
        config = try c.decode(MapGenerationConfig.self, forKey: .config)
        landmarks = try c.decode(Landmarks.self, forKey: .landmarks)
        minerals = MineralField(seed: seed)
        let ls = try c.decode([MapLayer].self, forKey: .layers)
        layers = Dictionary(uniqueKeysWithValues: ls.map { ($0.id, $0) })
        guard layers[.surface] != nil else {
            throw DecodingError.dataCorruptedError(forKey: .layers, in: c, debugDescription: "地表の層が無い")
        }
        generatedChunks = Set(try c.decode([ChunkCoord].self, forKey: .generatedChunks))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
        try c.encode(config, forKey: .config)
        try c.encode(landmarks, forKey: .landmarks)
        try c.encode(layerIDs.map { layers[$0]! }, forKey: .layers)
        try c.encode(generatedChunks.sorted(), forKey: .generatedChunks)
    }
}
