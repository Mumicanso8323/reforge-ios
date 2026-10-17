import Foundation
import RFContent
import RFKernel
import RFMap
import RFSim
import RFWorld

/// アプリが本体を立ち上げる入口(コンテンツの読み込み・新しい世界・GameHost)。
/// 画面はここと GameHost だけを使う。
public enum GameBootstrap {
    public struct ContentLoad: Sendable {
        public var content: ContentDB
        public var sealedFailed: Bool
        public var report: BundleReport

        public init(content: ContentDB, sealedFailed: Bool, report: BundleReport) {
            self.content = content
            self.sealedFailed = sealedFailed
            self.report = report
        }
    }

    /// 地図の生成器(1 か所だけ)。RFMap(U1)の生成器。
    public static var mapGenerator: any MapGenerating { RFMapGenerator() }

    /// アプリの束に入れたコンテンツ(`content/public` と、あれば封をした `content/private.sealed`)。
    /// 鍵が違う・封が壊れているときはエラー(呼び手が公開の層だけに落とす: `loadContentFallingBack`)。
    public static func loadContent(contentDirectory: URL, key: Data?) throws -> ContentDB {
        try loadContentReport(contentDirectory: contentDirectory, key: key).content
    }

    /// 読み込んだコンテンツと、言語ごとの本文の束の状態を返す。
    public static func loadContentReport(contentDirectory: URL, key: Data?) throws -> ContentLoad {
        do {
            let result = try ContentLoader.loadBundledReport(root: contentDirectory, key: key,
                                                             expecting: LanguageID.released)
            if result.report.failed.contains(.ja) || result.report.missing.contains(.ja) {
                guard key != nil else {
                    throw ContentLoader.LoadError.sealed("cannot open the ja text bundle")
                }
                let fallback = try ContentLoader.loadBundledReport(root: contentDirectory, key: nil,
                                                                   expecting: LanguageID.released)
                return ContentLoad(content: fallback.db, sealedFailed: true, report: result.report)
            }
            return ContentLoad(content: result.db, sealedFailed: false, report: result.report)
        } catch {
            guard key != nil else { throw error }
            let fallback = try ContentLoader.loadBundledReport(root: contentDirectory, key: nil,
                                                               expecting: LanguageID.released)
            return ContentLoad(content: fallback.db, sealedFailed: true, report: fallback.report)
        }
    }

    /// 封を開けなければ公開の層だけで読む(アプリを落とさない)。sealedFailed は画面の帯に 1 行出すための印。
    public static func loadContentFallingBack(contentDirectory: URL, key: Data?) throws
        -> (content: ContentDB, sealedFailed: Bool)
    {
        let result = try loadContentReport(contentDirectory: contentDirectory, key: key)
        return (result.content, result.sealedFailed)
    }

    public static func newWorld(content: ContentDB, seed: UInt64) -> WorldState {
        WorldFactory(content: content, mapGenerator: mapGenerator).newWorld(seed: seed)
    }

    public static func host(content: ContentDB, world: WorldState) -> GameHost {
        GameHost(simulation: Simulation(content: content), world: world)
    }
}
