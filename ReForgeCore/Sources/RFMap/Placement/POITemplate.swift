/// POI テンプレートの ID(原作 `POITemplate.Id` と同じ文字列)。
public struct POITemplateID: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }
    public static func < (a: POITemplateID, b: POITemplateID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// POI(遺跡・巣・環境)のテンプレート(原作 `POITemplate`)。名前は持たない。
public struct POITemplate: Codable, Equatable, Sendable {
    public let id: POITemplateID
    public let kind: PlacementKind
    /// 置いてよいバイオーム(アンカーのマスで判定)。
    public let biomes: [Biome]
    /// 抽選の重み(原作の Rarity × 100)。
    public let weight: Int
    public let footprint: TileFootprint
    /// 遺跡で漁れる回数の範囲。
    public let scrap: ClosedRange<Int>?
    /// 巣の脅威の段階と、湧く獣の種の ID。
    public let threatLevel: Int?
    public let spawnSpecies: String?

    public init(id: POITemplateID, kind: PlacementKind, biomes: [Biome], weight: Int,
                footprint: TileFootprint = .single, scrap: ClosedRange<Int>? = nil,
                threatLevel: Int? = nil, spawnSpecies: String? = nil) {
        self.id = id
        self.kind = kind
        self.biomes = biomes
        self.weight = weight
        self.footprint = footprint
        self.scrap = scrap
        self.threatLevel = threatLevel
        self.spawnSpecies = spawnSpecies
    }
}

/// POI テンプレートの一覧(原作 `POITemplateDatabase` の 11 種)。
public enum POICatalog {
    public static let all: [POITemplate] = [
        // 遺跡
        POITemplate(id: POITemplateID("ruins_factory"), kind: .ruins, biomes: [.ruins, .rock], weight: 30,
                    footprint: .rect(width: 2, height: 1), scrap: 3...7),
        POITemplate(id: POITemplateID("ruins_military"), kind: .ruins, biomes: [.ruins], weight: 20,
                    footprint: .rect(width: 2, height: 1), scrap: 4...8),
        POITemplate(id: POITemplateID("ruins_lab"), kind: .ruins, biomes: [.ruins], weight: 15,
                    footprint: .rect(width: 2, height: 1), scrap: 3...6),
        POITemplate(id: POITemplateID("ruins_residential"), kind: .ruins, biomes: [.ruins, .plain], weight: 35,
                    footprint: .rect(width: 2, height: 1), scrap: 2...5),
        // 巣
        POITemplate(id: POITemplateID("wolf_nest"), kind: .nest, biomes: [.forest, .plain], weight: 40,
                    threatLevel: 2, spawnSpecies: "wolf"),
        POITemplate(id: POITemplateID("bear_den"), kind: .nest, biomes: [.forest, .rock], weight: 25,
                    threatLevel: 3, spawnSpecies: "bear"),
        POITemplate(id: POITemplateID("golem_cave"), kind: .nest, biomes: [.rock], weight: 20,
                    threatLevel: 4, spawnSpecies: "golem"),
        // 環境
        POITemplate(id: POITemplateID("water_source"), kind: .aquifer, biomes: [.water, .forest], weight: 30),
        POITemplate(id: POITemplateID("fertile_land"), kind: .fertileLand, biomes: [.plain, .forest], weight: 30),
        POITemplate(id: POITemplateID("geothermal_vent"), kind: .geothermal, biomes: [.rock], weight: 10),
        // 汚れた区域
        POITemplate(id: POITemplateID("contamination_zone"), kind: .contamination, biomes: [.ruins], weight: 25),
    ]

    private static let byID: [POITemplateID: POITemplate] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func template(_ id: POITemplateID) -> POITemplate? { byID[id] }

    /// そのバイオームに置けるテンプレート(一覧の順)。
    public static func templates(for biome: Biome) -> [POITemplate] {
        all.filter { $0.biomes.contains(biome) }
    }
}
