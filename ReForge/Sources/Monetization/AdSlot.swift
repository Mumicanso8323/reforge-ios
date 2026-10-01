import SwiftUI

/// 広告枠の寸法と余白(§8.2、REQ-07)。
enum AdLayout {
    /// 枠の高さ。読み込み前から確保し、読み込みに失敗しても畳まない。
    static let bannerHeight: CGFloat = 50
    /// 枠とゲームの操作要素の間の、押せない余白(8pt 以上)。
    static let contentGap: CGFloat = 8
    /// 最下段の「休む」と下の枠の間(12pt 以上)。
    static let bottomButtonGap: CGFloat = 12
}

enum AdSlotPosition {
    case top, bottom
}

/// 広告の供給元。P1 は何も出さない NoopAdProvider(AdMob は P3)。
protocol AdProvider {
    /// 枠に広告を出せるか。false なら枠はダミー表示のまま(高さは保つ)。
    var isServing: Bool { get }
}

struct NoopAdProvider: AdProvider {
    let isServing = false
}

/// 上下に固定高さの広告枠を確保するコンテナ。中身は残りの領域を使う。
/// 広告を消す購入をしたら枠の高さを 0 に畳む(S11)。
struct AdBannerContainer<Content: View>: View {
    let adsRemoved: Bool
    private let content: Content

    init(adsRemoved: Bool, @ViewBuilder content: () -> Content) {
        self.adsRemoved = adsRemoved
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if !adsRemoved { AdSlot(position: .top) }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !adsRemoved { AdSlot(position: .bottom) }
        }
    }
}

/// 広告 1 枠分の場所取り。P1 はダミー(灰色の枠に「広告」)。
struct AdSlot: View {
    let position: AdSlotPosition

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.25))
            Text("広告")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: AdLayout.bannerHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("広告"))
        .accessibilityIdentifier(position == .top ? "adSlotTop" : "adSlotBottom")
    }
}

#Preview {
    AdBannerContainer(adsRemoved: false) {
        Color.clear
    }
}
