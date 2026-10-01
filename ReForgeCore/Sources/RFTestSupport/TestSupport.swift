import Foundation
import ReForgeEngine

/// テストの道具。アプリには入れない。
public enum TestContent {
    /// リポジトリの根(このファイルから 4 つ上)。
    public static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// 公開の試験用コンテンツ(content/public)。ネタバレの無い最小の集まり。
    public static let publicLayer = repoRoot.appendingPathComponent("content/public", isDirectory: true)

    /// 公開の層だけ(CI の公開ジョブと同じ条件)。
    public static func publicOnly() throws -> ContentDB {
        try ContentLoader.load(layers: [publicLayer])
    }

    /// 公開 + 非公開(環境変数か content/private があれば)。非公開が無ければ公開だけ。
    public static func full() throws -> ContentDB {
        try ContentLoader.loadDefault(publicLayer: publicLayer)
    }

    /// 非公開の層があるか(本物のコンテンツを要るテストは、無ければ飛ばす)。
    public static var hasPrivateLayer: Bool {
        ContentLoader.privateLayer(publicLayer: publicLayer, environment: ProcessInfo.processInfo.environment) != nil
    }
}

/// 試験用の平らな地図(地図の担当の生成ができるまでの代わり。以後もシステムの単体テストで使う)。
public struct FlatMapGenerator: MapGenerating {
    public let terrain: TerrainID
    public init(terrain: TerrainID = "grass") { self.terrain = terrain }

    public func generate(config: MapGenConfig, terrains: [TerrainID: TerrainDef], rng: inout SeededRandom,
                         allocate: () -> EntityID) -> MapState {
        let layer = MapLayer(size: config.size, palette: [terrain], terrain: Array(repeating: 0, count: config.size.count))
        let c = GridPoint(config.size.width / 2, config.size.height / 2)
        return MapState(layers: [.surface: layer],
                        baseArea: GridRect(origin: GridPoint(c.x - 5, c.y - 3), size: GridSize(width: 11, height: 7)),
                        spawn: WorldPoint(.surface, c))
    }
}

/// 試験用の一式(コンテンツ・本体・新しい世界)。
public struct TestRig {
    public let content: ContentDB
    public let simulation: Simulation
    public let factory: WorldFactory

    public init(content: ContentDB) {
        self.content = content
        self.simulation = Simulation(content: content)
        self.factory = WorldFactory(content: content, mapGenerator: FlatMapGenerator())
    }

    public static func publicOnly() throws -> TestRig { TestRig(content: try TestContent.publicOnly()) }

    /// 昼を 1 日ぶん、実時間 dt 刻みで進める(画面のタイマーの代わり)。
    public func playDay(_ w: inout WorldState, dt: Double = 1.0 / 10) -> StepReport {
        var r = StepReport()
        var guardCount = 0
        while w.clock.phase == .day && w.run.isActive && guardCount < 100_000 {
            r.merge(simulation.advance(&w, realSeconds: dt))
            guardCount += 1
        }
        return r
    }
}
