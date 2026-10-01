/// 地表バイオームの元になる 4 軸の場(原作 `BiomeLayer`)。seed と大きさだけで決まる純関数。
/// 周波数は設計書どおり(温度 1/80・水分 1/40・地質 1/30・汚れ 1/60 + 中心からの距離 0.4)。
public struct BiomeField: Codable, Equatable, Sendable {
    public let seed: UInt64
    public let size: MapSize
    /// 汚れが距離で増える基準点(拠点の中心)。
    public let origin: GridPoint
    public let thresholds: BiomeThresholds

    private let temperatureNoise: PerlinNoise
    private let moistureNoise: PerlinNoise
    private let geologyNoise: PerlinNoise
    private let contaminationNoise: PerlinNoise
    private let maxDistance: Double

    static let temperatureFrequency = 1.0 / 80
    static let moistureFrequency = 1.0 / 40
    static let geologyFrequency = 1.0 / 30
    static let contaminationFrequency = 1.0 / 60

    public init(seed: UInt64, size: MapSize, origin: GridPoint? = nil, thresholds: BiomeThresholds = .original) {
        self.seed = seed
        self.size = size
        self.thresholds = thresholds
        let o = origin ?? size.center
        self.origin = o
        temperatureNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 1))
        moistureNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 2))
        geologyNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 3))
        contaminationNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 4))
        let cx = Double(size.width / 2), cy = Double(size.height / 2)
        maxDistance = max(1, (cx * cx + cy * cy).squareRoot())
    }

    /// マスの環境パラメータ。
    public func params(at p: GridPoint) -> EnvironmentParams {
        let x = Double(p.x), y = Double(p.y)
        let t = temperatureNoise.sample(x * Self.temperatureFrequency, y * Self.temperatureFrequency)
        let m = moistureNoise.sample(x * Self.moistureFrequency, y * Self.moistureFrequency)
        let g = geologyNoise.sample(x * Self.geologyFrequency, y * Self.geologyFrequency)
        let base = contaminationNoise.sample(x * Self.contaminationFrequency, y * Self.contaminationFrequency) * 0.6
        let ratio = p.distance(to: origin) / maxDistance
        let c = min(1, max(0, base + ratio * 0.4))
        return EnvironmentParams(temperature: t, moisture: m, geology: g, contamination: c)
    }

    /// 手を加える前の自然のバイオーム(拠点の整地や川などの書き込みは含まない)。
    public func naturalBiome(at p: GridPoint) -> Biome {
        thresholds.biome(params(at: p))
    }

    private enum CodingKeys: String, CodingKey { case seed, size, origin, thresholds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(seed: try c.decode(UInt64.self, forKey: .seed),
                  size: try c.decode(MapSize.self, forKey: .size),
                  origin: try c.decode(GridPoint.self, forKey: .origin),
                  thresholds: try c.decode(BiomeThresholds.self, forKey: .thresholds))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
        try c.encode(size, forKey: .size)
        try c.encode(origin, forKey: .origin)
        try c.encode(thresholds, forKey: .thresholds)
    }

    public static func == (a: BiomeField, b: BiomeField) -> Bool {
        a.seed == b.seed && a.size == b.size && a.origin == b.origin && a.thresholds == b.thresholds
    }
}
