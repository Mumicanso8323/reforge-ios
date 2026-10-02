import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// ipa に入れる非公開の層の封(E-content.md §4.5)。
///
/// 公開の dev リリースの ipa は誰でも落とせるので、非公開の層(物語の本文)は平文で入れず、ビルドごとの使い捨ての
/// 鍵で暗号化した 1 ファイル(private.sealed)にする。鍵はアプリ本体のバイナリにだけ埋める。
/// 守れるのは「ipa を展開・grep しただけで本文が読める」状態まで。バイナリを解析して鍵を取り出す人からは守れない
/// (方式もこの公開のコードにある前提)。
///
/// 形式: 合図 "RFS1"(4) + nonce(12) + 暗号文(n) + 認証タグ(16)。AES-256-GCM、追加認証データ = 合図の 4 バイト。
/// 平文: {"version": 1, "files": {"<層の中の相対パス>": "<ファイルの中身(UTF-8)>", …}}。
/// 入れるのは読み込みと同じ *.json だけ(ContentLoader.isContentPath。materials/・tools/・隠しは入れない)。
public enum ContentSeal {
    public static let fileName = "private.sealed"
    public static let magic = Data("RFS1".utf8)
    public static let version = 1
    public static let keyBytes = 32

    struct Payload: Codable {
        var version: Int
        var files: [String: String]
    }

    /// 層のディレクトリ → 平文(相対パス → 中身)。読み込みと同じファイルを、同じ相対パスで。
    public static func collect(layer: URL) throws -> [String: Data] {
        let root = layer.resolvingSymlinksInPath()
        var out: [String: Data] = [:]
        for rel in try ContentLoader.relativeJSONPaths(in: layer) {
            out[rel] = try Data(contentsOf: root.appendingPathComponent(rel))
        }
        return out
    }

    /// 封をする。nonce は毎回乱数。
    public static func seal(_ files: [String: Data], key: Data) throws -> Data {
        try seal(files, key: key, magic: magic)
    }

    /// 合図を変えて封をする(絵の封 ArtSeal と共用)。
    static func seal(_ files: [String: Data], key: Data, magic: Data) throws -> Data {
        guard key.count == keyBytes else { throw ContentLoader.LoadError.sealed("鍵の長さが違う") }
        var strings: [String: String] = [:]
        for (path, data) in files {
            guard let s = String(data: data, encoding: .utf8) else {
                throw ContentLoader.LoadError.sealed("UTF-8 でないファイル \(path)")
            }
            strings[path] = s
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let plain = try enc.encode(Payload(version: version, files: strings))
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(),
                                   authenticating: magic)
        guard let combined = box.combined else { throw ContentLoader.LoadError.sealed("封の形が作れない") }
        return magic + combined
    }

    /// 開封する。鍵違い・1 バイトでも変わった・形式が違う、はすべてエラー。
    public static func open(_ sealed: Data, key: Data) throws -> [String: Data] {
        try open(sealed, key: key, magic: magic)
    }

    static func open(_ sealed: Data, key: Data, magic: Data) throws -> [String: Data] {
        guard key.count == keyBytes else { throw ContentLoader.LoadError.sealed("鍵の長さが違う") }
        guard sealed.count >= magic.count + 12 + 16, sealed.prefix(magic.count) == magic else {
            throw ContentLoader.LoadError.sealed("合図が無い・短すぎる")
        }
        let plain: Data
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(magic.count))
            plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: magic)
        } catch {
            throw ContentLoader.LoadError.sealed("開けない(鍵が違うか、壊れている)")
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: plain), p.version == version else {
            throw ContentLoader.LoadError.sealed("中身の形式が違う")
        }
        return p.files.mapValues { Data($0.utf8) }
    }

    /// 新しい鍵(ビルドごと)。
    public static func newKey() -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<keyBytes).map { _ in UInt8.random(in: .min ... .max, using: &g) })
    }

    /// アプリに埋める鍵の Swift ファイル。鍵をそのまま書かず、乱数の覆いとの XOR の 2 つの配列に分ける
    /// (バイナリの文字列検索で鍵の並びがそのまま見えないように)。鍵が nil なら「非公開なし」のファイル。
    public static func keySource(_ key: Data?) -> String {
        let header = """
        // 生成物(rf-seal。docs/architecture/E-content.md §4.5)。手で直さない・コミットしない。
        import Foundation

        enum ContentKey {

        """
        guard let key else {
            return header + "    /// 非公開の層が無いビルド。公開の層だけで動く。\n    static let key: Data? = nil\n}\n"
        }
        let mask = newKey()
        let masked = zip(key, mask).map { $0 ^ $1 }
        func array(_ bytes: some Sequence<UInt8>) -> String {
            "[" + bytes.map { String(format: "0x%02x", $0) }.joined(separator: ", ") + "]"
        }
        return header + """
            private static let a: [UInt8] = \(array(masked))
            private static let b: [UInt8] = \(array(mask))
            /// 封をした非公開の層(private.sealed)を開く鍵。
            static var key: Data? { Data(zip(a, b).map { $0 ^ $1 }) }
        }

        """
    }
}
