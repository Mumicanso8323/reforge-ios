import SwiftUI
import UIKit
import ReForgeEngine

/// 封をした絵(立ち絵・山場の絵)を引く(docs/art/README.md §6)。
/// 束の content/ から ContentLoader.loadBundledArt で一度だけ読み、開けなければ空にする(絵なしで文字だけで遊べる)。
/// 公開の絵(タイトル)はここを通さず Resources/Art/ から読む。
@MainActor
final class ArtProvider {
    static let shared = ArtProvider(bundle: .main)

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

    /// 絵(無ければ nil)。
    func image(_ id: ArtID) -> UIImage? {
        if let c = cache[id] { return c }
        guard let d = files[id], let img = UIImage(data: d) else { return nil }
        cache[id] = img
        return img
    }
}

/// 封をした絵を 1 枚置く。絵が無ければ何も描かない(場所も取らない)。
/// 使い方: `ArtView(id: "p03")` (ID は中立の番号)
struct ArtView: View {
    let id: ArtID

    var body: some View {
        if let img = ArtProvider.shared.image(id) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }
}
