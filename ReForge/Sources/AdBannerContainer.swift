import SwiftUI

/// 広告枠の寸法。AdMob の標準バナー(320x50)に合わせて高さ 50pt。
enum AdLayout {
    static let bannerHeight: CGFloat = 50
}

enum AdSlotPosition {
    case top, bottom

    var debugLabel: String {
        switch self {
        case .top: "広告枠(上) 50pt"
        case .bottom: "広告枠(下) 50pt"
        }
    }
}

/// 上下に固定高さの広告枠を確保するコンテナ。中身は残りの領域を使う。
/// 今は枠だけ(広告 SDK は未導入)。DEBUG ビルドでは枠の位置が分かるよう可視化し、
/// Release ビルドでは何も描かない空白にする。
struct AdBannerContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            AdSlotView(position: .top)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            AdSlotView(position: .bottom)
        }
    }
}

/// 広告 1 枠分の場所取り。
struct AdSlotView: View {
    let position: AdSlotPosition

    var body: some View {
        ZStack {
            #if DEBUG
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
            Rectangle()
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Text(position.debugLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            #else
            Color.clear
            #endif
        }
        .frame(maxWidth: .infinity)
        .frame(height: AdLayout.bannerHeight)
        .accessibilityHidden(true)
    }
}

#Preview {
    AdBannerContainer {
        Text("中身")
    }
}
