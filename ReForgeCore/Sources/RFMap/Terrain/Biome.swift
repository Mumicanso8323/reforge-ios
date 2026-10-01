/// 地表の地形(原作 `BiomeType`)。5 バイオーム + 拠点の整地。
/// 表示名は持たない(名前は Perception 層が引く)。
public enum Biome: UInt8, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case plain = 0
    case forest = 1
    case rock = 2
    case water = 3
    case ruins = 4
    /// 拠点の整地(建造できる草地)。
    case cleared = 5

    /// 自然に生まれる 5 バイオーム(整地を除く)。
    public static let natural: [Biome] = [.plain, .forest, .rock, .water, .ruins]
}

/// 地図の大きさ(マス)。
public struct MapSize: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "地図の大きさは正の値")
        self.width = width
        self.height = height
    }

    /// R1 の地図(96×96)。
    public static let r1 = MapSize(width: 96, height: 96)
    /// 原作の既定(10000×10000)。
    public static let original = MapSize(width: 10000, height: 10000)

    public var cellCount: Int { width * height }

    public func contains(_ p: GridPoint) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
    }

    /// 行優先の通し番号。
    @inlinable
    public func index(_ p: GridPoint) -> Int { p.y * width + p.x }

    @inlinable
    public func point(_ index: Int) -> GridPoint { GridPoint(index % width, index / width) }

    /// 中央のマス。
    public var center: GridPoint { GridPoint(width / 2, height / 2) }

    public var description: String { "\(width)x\(height)" }
}

/// 環境パラメータ(4 軸。原作 `EnvironmentParams`)。各 0.0〜1.0。
public struct EnvironmentParams: Codable, Equatable, Sendable {
    /// 温度(0 = 極寒, 1 = 灼熱)
    public var temperature: Double
    /// 水分(0 = 乾燥, 1 = 湿潤)
    public var moisture: Double
    /// 地質の硬さ(0 = 軟土, 1 = 硬岩)
    public var geology: Double
    /// 汚れ(0 = 清浄, 1 = 高い)。拠点から離れるほど上がる。
    public var contamination: Double

    public init(temperature: Double, moisture: Double, geology: Double, contamination: Double) {
        self.temperature = temperature
        self.moisture = moisture
        self.geology = geology
        self.contamination = contamination
    }

    /// パラメータからバイオームを導く(原作 `BiomeLayer.DeriveBiome` の判定表)。
    public var biome: Biome { BiomeThresholds.original.biome(self) }
}

/// バイオームの判定の閾値(原作 `DeriveBiome` の判定を優先順に: 遺跡 → 岩場 → 水辺 → 森 → 草原)。
public struct BiomeThresholds: Codable, Equatable, Sendable {
    public var ruinsContamination: Double
    public var rockGeology: Double
    public var waterMoisture: Double
    public var forestTemperature: Double
    public var forestMoisture: Double

    public init(ruinsContamination: Double, rockGeology: Double, waterMoisture: Double,
                forestTemperature: Double, forestMoisture: Double) {
        self.ruinsContamination = ruinsContamination
        self.rockGeology = rockGeology
        self.waterMoisture = waterMoisture
        self.forestTemperature = forestTemperature
        self.forestMoisture = forestMoisture
    }

    /// 原作の値(汚れ > 0.7 / 地質 > 0.65 / 水分 > 0.75 / 温度 > 0.3 かつ 水分 > 0.4)。
    public static let original = BiomeThresholds(ruinsContamination: 0.7, rockGeology: 0.65, waterMoisture: 0.75,
                                                 forestTemperature: 0.3, forestMoisture: 0.4)

    /// R1 の 96×96 用。原作の値のままだと狭い地図の大半が森と遺跡になり、
    /// 目印(拠点と岩山の間の森・川・岩山)が埋もれるので、下地の森と遺跡を減らす。
    public static let r1 = BiomeThresholds(ruinsContamination: 0.76, rockGeology: 0.68, waterMoisture: 0.77,
                                           forestTemperature: 0.3, forestMoisture: 0.6)

    /// 拠点のまわり(R1 の「家の草地」)。岩場と遺跡を出さず、森と水辺は濃いところだけにする。
    /// 岩山・森・川の目印がこの中ではっきり見えるようにするため(R1 の追加)。
    public static let home = BiomeThresholds(ruinsContamination: 2, rockGeology: 2, waterMoisture: 0.8,
                                             forestTemperature: 0.3, forestMoisture: 0.7)

    /// 2 つの閾値の間を t(0〜1)で補間する。
    public static func blend(_ a: BiomeThresholds, _ b: BiomeThresholds, _ t: Double) -> BiomeThresholds {
        let k = min(1, max(0, t))
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * k }
        return BiomeThresholds(ruinsContamination: l(a.ruinsContamination, b.ruinsContamination),
                               rockGeology: l(a.rockGeology, b.rockGeology),
                               waterMoisture: l(a.waterMoisture, b.waterMoisture),
                               forestTemperature: l(a.forestTemperature, b.forestTemperature),
                               forestMoisture: l(a.forestMoisture, b.forestMoisture))
    }

    public func biome(_ p: EnvironmentParams) -> Biome {
        if p.contamination > ruinsContamination { return .ruins }
        if p.geology > rockGeology { return .rock }
        if p.moisture > waterMoisture { return .water }
        if p.temperature > forestTemperature && p.moisture > forestMoisture { return .forest }
        return .plain
    }
}
