import SwiftUI
import UIKit

/// どの画面・札・シートの上でも見える、右上の設定のボタン(L-10a)。
/// SwiftUI のシートは画面の木の上に重なるので、木の根に重ねたボタンはシートに隠れる。
/// そこで、ボタンだけを載せた透明の窓(UIWindow。通常より上)をシーンごとに 1 つ作る。
/// 押せる範囲は 44×44pt、周りに 4pt の余白で、右上の安全な領域の内側の 52×52pt を「設定の角」とする(InkMetric.settingsReserve)。
/// ボタンの外の押下は下の窓へ通す。設定はゲームのコマンドではない(本体には何も送らない)。
enum SettingsCorner {
    static let side: CGFloat = InkMetric.settingsReserve
    static let hitSize: CGFloat = 44
    static let margin: CGFloat = (InkMetric.settingsReserve - 44) / 2
}

/// 角のボタン。開閉で見た目の絵と読み上げのラベルは替わるが、識別子は替えない。
struct SettingsCornerButton: View {
    @Bindable var app: AppModel

    var body: some View {
        Button {
            app.settingsOpen.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 20))
                .foregroundStyle(InkColor.text)
                .frame(width: SettingsCorner.hitSize, height: SettingsCorner.hitSize)
                .background(Circle().fill(InkColor.ground.opacity(0.78)))
                .overlay(Circle().stroke(InkColor.rule, lineWidth: InkMetric.rule))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.settingsOpen ? Text("設定を閉じる") : Text("設定を開く"))
        .accessibilityIdentifier("settingsButton")
        .padding(SettingsCorner.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

/// ボタンの外の押下を通す窓。
final class SettingsCornerWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let corner = CGRect(x: bounds.maxX - SettingsCorner.side,
                            y: bounds.minY + safeAreaInsets.top,
                            width: SettingsCorner.side, height: SettingsCorner.side)
        guard corner.contains(point) else { return nil }
        let hit = super.hitTest(point, with: event)
        // 何も無い所(土台の面そのもの)に当たったなら、下の窓へ通す
        return hit === rootViewController?.view ? nil : hit
    }
}

/// シーンごとに 1 つの窓を作って持つ。
@MainActor
enum SettingsCornerWindows {
    private static var windows: [ObjectIdentifier: SettingsCornerWindow] = [:]

    /// 角のボタンを出すか(序の間は隠す。窓ごと isHidden。PT-B6)。
    static func setVisible(_ visible: Bool, in scene: UIWindowScene) {
        windows[ObjectIdentifier(scene)]?.isHidden = !visible
    }

    static func install(in scene: UIWindowScene, app: AppModel, visible: Bool = true) {
        let key = ObjectIdentifier(scene)
        if windows[key] != nil { return }
        let window = SettingsCornerWindow(windowScene: scene)
        let host = UIHostingController(rootView: SettingsCornerButton(app: app).preferredColorScheme(.dark))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.backgroundColor = .clear
        window.windowLevel = UIWindow.Level.normal + 1
        window.isHidden = !visible
        windows[key] = window
    }
}

/// RootView の背面に置き、シーンが分かった時点で角の窓を入れる。
struct SettingsCornerInstaller: UIViewRepresentable {
    let app: AppModel
    /// 角のボタンを出すか(AppModel.cornerButtonVisible。序の間は false)。
    var visible = true

    func makeUIView(context: Context) -> InstallerView {
        let v = InstallerView()
        v.app = app
        v.visible = visible
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        return v
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {
        uiView.app = app
        uiView.visible = visible
        uiView.installIfPossible()
    }

    final class InstallerView: UIView {
        var app: AppModel?
        var visible = true

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installIfPossible()
        }

        func installIfPossible() {
            guard let scene = window?.windowScene, let app else { return }
            let visible = visible
            MainActor.assumeIsolated {
                SettingsCornerWindows.install(in: scene, app: app, visible: visible)
                SettingsCornerWindows.setVisible(visible, in: scene)
            }
        }
    }
}
