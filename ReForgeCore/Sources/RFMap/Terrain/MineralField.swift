/// 鉱物の濃さ(原作 `MineralInfo`)。各 0.0〜1.0。
public struct MineralInfo: Codable, Equatable, Sendable {
    public var iron: Double
    public var copper: Double
    public var coal: Double
    public var stone: Double
    public var rare: Double

    public init(iron: Double, copper: Double, coal: Double, stone: Double, rare: Double) {
        self.iron = iron
        self.copper = copper
        self.coal = coal
        self.stone = stone
        self.rare = rare
    }

    /// どれかの鉱物が採掘の閾値を超えているか(鉄・銅 > 0.3、石炭 > 0.4、希少 > 0.2)。
    public var hasMineral: Bool { iron > 0.3 || copper > 0.3 || coal > 0.4 || rare > 0.2 }

    /// いちばん濃い鉱種(原作 `DominantMineral`)。鉄と銅がともに閾値を超えるときは混合。
    public var dominantCategory: DepositCategory {
        if rare > 0.2 { return .rare }
        if iron > 0.3 && copper > 0.3 { return .mixed }
        if iron >= copper && iron >= coal { return .iron }
        if copper >= iron && copper >= coal { return .copper }
        return .coal
    }
}

/// 地下の鉱物分布(原作 `SubsurfaceLayer`)。深さごとの濃さを Perlin ノイズで決める。
/// 地下の層を足すとき(R2)にもこの場を使う。
public struct MineralField: Codable, Equatable, Sendable {
    public static let maxDepth = 5

    public let seed: UInt64
    private let ironNoise: PerlinNoise
    private let copperNoise: PerlinNoise
    private let coalNoise: PerlinNoise
    private let rareNoise: PerlinNoise

    static let ironFrequency = 1.0 / 25
    static let copperFrequency = 1.0 / 35
    static let coalFrequency = 1.0 / 20
    static let rareFrequency = 1.0 / 50

    public init(seed: UInt64) {
        self.seed = seed
        ironNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 10))
        copperNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 11))
        coalNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 12))
        rareNoise = PerlinNoise(seed: SeededRandom.derivedSeed(from: seed, 13))
    }

    /// 座標と深さ(0 = 地表)の鉱物分布。地質が硬い(> 0.5)ほど濃い。深いほど希少が増える。
    public func minerals(at p: GridPoint, depth: Int, geology: Double) -> MineralInfo {
        let x = Double(p.x), y = Double(p.y)
        let geoBonus = geology > 0.5 ? 0.15 : 0
        let depthFactor = Double(depth) / Double(Self.maxDepth)
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

        let iron = clamp(ironNoise.sample(x * Self.ironFrequency, y * Self.ironFrequency) + geoBonus - depthFactor * 0.1)
        let copper = clamp(copperNoise.sample(x * Self.copperFrequency, y * Self.copperFrequency) + geoBonus * 0.8 + depthFactor * 0.05)
        let coal = clamp(coalNoise.sample(x * Self.coalFrequency, y * Self.coalFrequency) - depthFactor * 0.15)
        let rare = clamp(rareNoise.sample(x * Self.rareFrequency, y * Self.rareFrequency) * depthFactor * 1.5 + geoBonus * 0.5)
        return MineralInfo(iron: iron, copper: copper, coal: coal, stone: 1 - geoBonus, rare: rare)
    }

    private enum CodingKeys: String, CodingKey { case seed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(seed: try c.decode(UInt64.self, forKey: .seed))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
    }

    public static func == (a: MineralField, b: MineralField) -> Bool { a.seed == b.seed }
}
