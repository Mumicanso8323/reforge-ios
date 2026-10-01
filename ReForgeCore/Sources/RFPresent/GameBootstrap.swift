import Foundation
import RFContent
import RFKernel
import RFMap
import RFSim
import RFWorld

/// アプリが本体を立ち上げる入口(コンテンツの読み込み・新しい世界・GameHost)。
/// 画面はここと GameHost だけを使う。
public enum GameBootstrap {
    /// 地図の生成器(1 か所だけ)。地図の担当(U1)の生成器が RFMap に入ったら、統合担当がここを差し替える。
    public static var mapGenerator: any MapGenerating { SketchMapGenerator() }

    /// アプリの束に入れたコンテンツ(`content/` をそのまま同梱: `content/public` と、あれば `content/private`)。
    public static func loadContent(contentDirectory: URL) throws -> ContentDB {
        try ContentLoader.loadDefault(publicLayer: contentDirectory.appendingPathComponent("public", isDirectory: true),
                                      environment: [:])
    }

    public static func newWorld(content: ContentDB, seed: UInt64) -> WorldState {
        WorldFactory(content: content, mapGenerator: mapGenerator).newWorld(seed: seed)
    }

    public static func host(content: ContentDB, world: WorldState) -> GameHost {
        GameHost(simulation: Simulation(content: content), world: world)
    }
}

/// 仮の地図(U1 の生成器が入るまで)。乱数を使わず、座標の式で地面・川・岩場・森を置く。
/// 地形の ID はコンテンツの terrains から性質(isWater・tags)で選ぶ(無い種類は地面で代わりにする)。
public struct SketchMapGenerator: MapGenerating {
    public init() {}

    public func generate(config: MapGenConfig, terrains: [TerrainID: TerrainDef], rng: inout SeededRandom,
                         allocate: () -> EntityID) -> MapState {
        let ids = terrains.keys.sorted()
        func pick(_ ok: (TerrainDef) -> Bool) -> TerrainID? { ids.first { terrains[$0].map(ok) ?? false } }
        let ground = pick { $0.passable && !$0.isWater && ($0.tags.contains("ground") || $0.tags.contains("grass")) }
            ?? pick { $0.passable && !$0.isWater } ?? ids.first ?? "grass"
        let water = pick { $0.isWater } ?? ground
        let rock = pick { $0.tags.contains("rock") } ?? ground
        let forest = pick { $0.tags.contains("forest") } ?? ground

        let size = config.size
        let w = Double(size.width), h = Double(size.height)
        let c = GridPoint(size.width / 2, size.height / 2)
        var layer = MapLayer(size: size, palette: [ground], terrain: Array(repeating: 0, count: size.count))
        for y in 0..<size.height {
            for x in 0..<size.width {
                let p = GridPoint(x, y)
                let fx = Double(x), fy = Double(y)
                let riverX = Double(c.x) + w * 0.2 + 2 * sin(fy / 5)
                if abs(fx - riverX) < 1.2 {
                    layer.setTerrain(water, at: p)
                } else if hypot(fx - w * 0.18, fy - h * 0.2) < w * 0.14 {
                    layer.setTerrain(rock, at: p)
                } else if hypot(fx - w * 0.3, fy - h * 0.72) < w * 0.12 {
                    layer.setTerrain(forest, at: p)
                }
            }
        }
        let base = GridRect(origin: GridPoint(c.x - 5, c.y - 3), size: GridSize(width: 11, height: 7))
        for y in base.origin.y..<(base.origin.y + base.size.height) {
            for x in base.origin.x..<(base.origin.x + base.size.width) { layer.setTerrain(ground, at: GridPoint(x, y)) }
        }
        // 目印(POI)は置かない(生成器にはコンテンツの POI の定義が渡らない。本物の生成器が置く)。
        return MapState(layers: [.surface: layer], baseArea: base, spawn: WorldPoint(.surface, c))
    }
}
