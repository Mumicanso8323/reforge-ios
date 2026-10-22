import SwiftUI
import UIKit
import ReForgeEngine

/// 封をした絵(立ち絵・山場の絵)を引く(docs/art/README.md §6)。
/// 束の content/ から ContentLoader.loadBundledArt で一度だけ読み、開けなければ空にする(絵なしで文字だけで遊べる)。
/// 公開の絵(タイトル)はここを通さず Resources/Art/ から読む。
@MainActor
final class ArtProvider {
    private(set) static var shared = ArtProvider(bundle: .main)

    private let files: [ArtID: Data]
    private var cache: [ArtID: UIImage] = [:]
    /// 封を開けなかった(鍵違い・壊れた封)。帯の sealedContentFailed と同じ扱いで 1 行出す。
    let failed: Bool

    init(bundle: Bundle) {
        guard let root = bundle.url(forResource: "content", withExtension: nil) else {
            files = [:]
            failed = false
            return
        }
        do {
            files = try ContentLoader.loadBundledArt(root: root, key: ContentKey.key)
            failed = false
        } catch {
            files = [:]
            failed = true
        }
    }

    /// 試験・見本用の差し替え口(本番の束の経路は通らない)。
    init(files: [ArtID: Data], failed: Bool = false) {
        self.files = files
        self.failed = failed
    }

    #if DEBUG
    /// `shared` を差し替える(画面の試験と ScreenshotMode だけ)。
    static func install(_ provider: ArtProvider) { shared = provider }
    #endif

    /// 絵(無ければ nil)。
    func image(_ id: ArtID) -> UIImage? {
        if let c = cache[id] { return c }
        guard let d = files[id], let img = UIImage(data: d) else { return nil }
        cache[id] = img
        return img
    }
}

/// 絵の出し方。`.full` は縦横比のまま全体(仲間のタブ。既定)、`.scene` は場面・決断の帯の切り出し。
enum ArtStyle { case full, scene }

/// 封をした絵を 1 枚置く。絵が無ければ何も描かない(場所も取らない)。
/// 使い方: `ArtView(id: "p03")` (ID は中立の番号)
/// `.scene`: 縦長(高さ/幅 2.0 以上。全身)は上から 45% を幅いっぱいで切り出す。それ未満は全体を収める。
struct ArtView: View {
    let id: ArtID
    var style: ArtStyle = .full

    /// 縦長とみなす縦横比(高さ/幅)と、切り出す割合。
    static let tallRatio: CGFloat = 2.0
    static let cropFraction: CGFloat = 0.45

    var body: some View {
        if let img = ArtProvider.shared.image(id) {
            let ratio = img.size.width > 0 ? img.size.height / img.size.width : 1
            if style == .scene, ratio >= Self.tallRatio {
                Color.clear
                    .aspectRatio(1 / (ratio * Self.cropFraction), contentMode: .fit)
                    .overlay(alignment: .top) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    .accessibilityHidden(true)
            } else {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            }
        }
    }
}
