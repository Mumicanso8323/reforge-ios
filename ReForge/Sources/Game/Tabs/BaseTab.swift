import SwiftUI
import ReForgeEngine

/// 拠点のタブ(蓄え・建てた物・研究・セーブ)。担当: U18。
struct BaseTabView: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var showSettings = false

    var body: some View {
        PlaceholderPanel {
            Text("拠点").font(InkFont.heading)
            Text("蓄え・建てた物・セーブが載ります。まだできていません。")
            Button {
                showSettings.toggle()
            } label: {
                Text("設定")
            }
            .buttonStyle(.ink(.secondary))
            Button {
                Task { await app.backToTitle() }
            } label: {
                Text("タイトルへ")
            }
            .buttonStyle(.ink(.secondary))
        }
        .inkCard(isPresented: $showSettings, title: Text("設定")) {
            SettingsView(app: app, close: { showSettings = false })
        }
    }
}
