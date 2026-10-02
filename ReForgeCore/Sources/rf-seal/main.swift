import Foundation
import RFContent
import RFKernel

// 非公開の層に封をして、アプリに埋める鍵の Swift ファイルを書く(E-content.md §4.5。CI の ios ジョブで使う)。
//
//   swift run --package-path ReForgeCore rf-seal <非公開の層> <出力の private.sealed> <出力の ContentKey.swift> [<出力の art.sealed>]
//
// - 4 つ目を渡すと、非公開の層の art/ の絵に同じ鍵で封をする(絵が無ければ前の残りを消す)。
//
// - 鍵はこの実行ごとに新しく作る。鍵・本文・見張りの文字列は表示しない(公開の CI のログに出さない)。
// - 非公開の層が無い(ディレクトリが無い・JSON が無い)ときは、鍵 nil の ContentKey.swift を書き、private.sealed は作らない
//   (前の実行の残りがあれば消す)。
// - 封をした後、開き直して同じ中身になること・見張りの文字列が封の中に平文で無いことを確かめる。

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("rf-seal: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments.dropFirst()
guard args.count == 3 || args.count == 4 else {
    fail("使い方: rf-seal <非公開の層> <出力の private.sealed> <出力の ContentKey.swift> [<出力の art.sealed>]")
}
let layer = URL(fileURLWithPath: args[args.startIndex], isDirectory: true)
let sealedOut = URL(fileURLWithPath: args[args.startIndex + 1])
let keyOut = URL(fileURLWithPath: args[args.startIndex + 2])
let artOut = args.count == 4 ? URL(fileURLWithPath: args[args.startIndex + 3]) : nil

func write(_ data: Data, to url: URL) {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    } catch {
        fail("書けない: \(url.path)")
    }
}

var files: [String: Data] = [:]
var isDir: ObjCBool = false
if FileManager.default.fileExists(atPath: layer.path, isDirectory: &isDir), isDir.boolValue {
    do { files = try ContentSeal.collect(layer: layer) } catch { fail("非公開の層を読めない") }
}

if files.isEmpty {
    try? FileManager.default.removeItem(at: sealedOut)
    if let artOut { try? FileManager.default.removeItem(at: artOut) }
    write(Data(ContentSeal.keySource(nil).utf8), to: keyOut)
    print("rf-seal: 非公開の層なし。公開の層だけのビルド(鍵 nil)")
    exit(0)
}

// 読み込みと同じ規則で読めること(知らないキー・同じ層の重なり)を先に確かめる
do {
    _ = try ContentLoader.load(sources: [.memory(name: "private", files: files)])
} catch {
    fail("非公開の層がコンテンツとして読めない(手元で swift test を回して直す)")
}

let key = ContentSeal.newKey()
let sealed: Data
do { sealed = try ContentSeal.seal(files, key: key) } catch { fail("封ができない") }
guard (try? ContentSeal.open(sealed, key: key)) == files else { fail("開き直した中身が一致しない") }

// 見張りの文字列(bundle.json の canary)が封の中に平文で現れないこと
if let b = files["bundle.json"],
   let obj = try? JSONSerialization.jsonObject(with: b) as? [String: Any],
   let canary = (obj["bundle"] as? [String: Any])?["canary"] as? String, !canary.isEmpty,
   sealed.range(of: Data(canary.utf8)) != nil
{
    fail("見張りの文字列が封の中に平文で見える")
}

write(sealed, to: sealedOut)
write(Data(ContentSeal.keySource(key).utf8), to: keyOut)
print("rf-seal: \(files.count) ファイルに封をした(\(sealed.count) バイト)")

if let artOut {
    let art: [ArtID: Data]
    do { art = try ArtSeal.collect(layer: layer) } catch { fail("非公開の絵を読めない") }
    if art.isEmpty {
        try? FileManager.default.removeItem(at: artOut)
        print("rf-seal: 非公開の絵なし")
    } else {
        let sealedArt: Data
        do { sealedArt = try ArtSeal.seal(art, key: key) } catch { fail("絵の封ができない") }
        guard (try? ArtSeal.open(sealedArt, key: key)) == art else { fail("開き直した絵が一致しない") }
        write(sealedArt, to: artOut)
        print("rf-seal: 絵 \(art.count) 枚に封をした(\(sealedArt.count) バイト)")
    }
}
