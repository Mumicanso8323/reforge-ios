import SwiftUI

/// 下の広告枠の寸法と余白(§8.2、REQ-07)。
enum AdLayout {
    /// 枠の高さ。読み込み前から確保し、読み込みに失敗しても畳まない。
    static let bannerHeight: CGFloat = 50
    /// 最下段の「休む」と下の枠の間(12pt 以上)。
    static let bottomButtonGap: CGFloat = 12
}

/// 広告を出すか(オーナーの決定 2026-10-02 で広告はやめた。型の整理は M-01 で行い、それまでは枠も設定の節も出さない)。
enum AdPolicy {
    static let shown = false
}

/// 広告の供給元。P1 は何も出さない NoopAdProvider(AdMob は P3)。
protocol AdProvider {
    /// 枠に広告を出せるか。false なら枠はダミー表示のまま(高さは保つ)。
    var isServing: Bool { get }
}

struct NoopAdProvider: AdProvider {
    let isServing = false
}

/// 下に固定高さの広告枠を 1 つ確保するコンテナ。中身は残りの領域を使う。
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
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if AdPolicy.shown && !adsRemoved { AdSlot() }
        }
    }
}

/// 広告 1 枠分の場所取り。P1 はダミー(灰色の枠に「広告」)。
struct AdSlot: View {
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
        .accessibilityIdentifier("adSlotBottom")
    }
}

#Preview {
    AdBannerContainer(adsRemoved: false) {
        Color.clear
    }
}
