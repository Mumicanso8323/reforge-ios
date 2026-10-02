import Foundation
import RFKernel

/// 非公開の絵の封(E-content.md §4.5)。本文の封(ContentSeal)と同じ鍵・同じ暗号で、別のファイル art.sealed にする
/// (起動時のコンテンツの読み込みを絵の大きさで重くしないため)。
///
/// 置き場: 非公開の層の `art/<ArtID>.png`(.jpg も可)。ファイル名(拡張子を除く)が ArtID。
/// 形式: 合図 "RFA1"(4) + nonce(12) + 暗号文 + 認証タグ(16)。AES-256-GCM、追加認証データ = 合図。
/// 平文: {"version": 1, "files": {"<ArtID>": "<中身の base64>", …}}。
public enum ArtSeal {
    public static let fileName = "art.sealed"
    public static let magic = Data("RFA1".utf8)
    public static let directory = "art"
    static let extensions: Set<String> = ["png", "jpg", "jpeg"]

    /// 層の art/ から絵を集める(ArtID → 中身)。無ければ空。
    public static func collect(layer: URL) throws -> [ArtID: Data] {
        let dir = layer.resolvingSymlinksInPath().appendingPathComponent(directory, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return [:] }
        var out: [ArtID: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name)
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            let id = ArtID(url.deletingPathExtension().lastPathComponent)
            if out[id] != nil { throw ContentLoader.LoadError.sealed("同じ ArtID の絵が 2 つある: \(id.rawValue)") }
            out[id] = try Data(contentsOf: url)
        }
        return out
    }

    public static func seal(_ art: [ArtID: Data], key: Data) throws -> Data {
        var strings: [String: Data] = [:]
        for (id, data) in art { strings[id.rawValue] = Data(data.base64EncodedString().utf8) }
        return try ContentSeal.seal(strings, key: key, magic: magic)
    }

    public static func open(_ sealed: Data, key: Data) throws -> [ArtID: Data] {
        var out: [ArtID: Data] = [:]
        for (id, b64) in try ContentSeal.open(sealed, key: key, magic: magic) {
            guard let s = String(data: b64, encoding: .utf8), let d = Data(base64Encoded: s) else {
                throw ContentLoader.LoadError.sealed("絵の中身が base64 でない: \(id)")
            }
            out[ArtID(id)] = d
        }
        return out
    }
}

extension ContentLoader {
    /// アプリの束から絵を読む: <root>/private/art(平文。手元の開発)があればそれ → 無くて <root>/art.sealed と鍵があれば開封。
    /// どちらも無ければ空(公開の層だけのビルド。画面は絵なしの文字だけで出す)。鍵違い・壊れた封はエラー。
    public static func loadBundledArt(root: URL, key: Data? = nil) throws -> [ArtID: Data] {
        let priv = root.appendingPathComponent("private", isDirectory: true)
        if isDirectory(priv) { return try ArtSeal.collect(layer: priv) }
        let sealed = root.appendingPathComponent(ArtSeal.fileName)
        if let key, FileManager.default.fileExists(atPath: sealed.path) {
            return try ArtSeal.open(Data(contentsOf: sealed), key: key)
        }
        return [:]
    }
}
