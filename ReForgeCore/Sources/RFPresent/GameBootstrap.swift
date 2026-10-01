import Foundation
import RFContent
import RFKernel
import RFMap
import RFSim
import RFWorld

/// アプリが本体を立ち上げる入口(コンテンツの読み込み・新しい世界・GameHost)。
/// 画面はここと GameHost だけを使う。
public enum GameBootstrap {
    /// 地図の生成器(1 か所だけ)。RFMap(U1)の生成器。
    public static var mapGenerator: any MapGenerating { RFMapGenerator() }

    /// アプリの束に入れたコンテンツ(`content/public` と、あれば封をした `content/private.sealed`)。
    /// 鍵が違う・封が壊れているときはエラー(呼び手が公開の層だけに落とす: `loadContentFallingBack`)。
    public static func loadContent(contentDirectory: URL, key: Data?) throws -> ContentDB {
        try ContentLoader.loadBundled(root: contentDirectory, key: key)
    }

    /// 封を開けなければ公開の層だけで読む(アプリを落とさない)。sealedFailed は画面の帯に 1 行出すための印。
    public static func loadContentFallingBack(contentDirectory: URL, key: Data?) throws
        -> (content: ContentDB, sealedFailed: Bool)
    {
        do {
            return (try loadContent(contentDirectory: contentDirectory, key: key), false)
        } catch {
            guard key != nil else { throw error }
            return (try loadContent(contentDirectory: contentDirectory, key: nil), true)
        }
    }

    public static func newWorld(content: ContentDB, seed: UInt64) -> WorldState {
        WorldFactory(content: content, mapGenerator: mapGenerator).newWorld(seed: seed)
    }

    public static func host(content: ContentDB, world: WorldState) -> GameHost {
        GameHost(simulation: Simulation(content: content), world: world)
    }
}
