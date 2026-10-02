import SwiftUI
import ReForgeEngine

/// ゲームオーバーの 4 択(同じ重さで並べる。D-save.md §3)。
/// いまは「最初から」だけが動く(巻き戻し・失って続ける・セーブ地点からは保存と失敗の担当の中身が入ってから)。
struct GameOverView: View {
    @Bindable var app: AppModel
    @State private var confirmRestart = false

    var body: some View {
        VStack(spacing: 12) {
            Text("ここまで").font(.custom(FontBook.mapFont, size: 24)).bold()
            choice(Text("最初から"), enabled: true) { confirmRestart = true }
            choice(Text("記憶を持って巻き戻す"), enabled: false) {}
            choice(Text("失って続ける"), enabled: false) {}
            choice(Text("セーブ地点からロード"), enabled: false) {}
        }
        .font(.custom(FontBook.mapFont, size: 16))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
        .accessibilityIdentifier("gameOver")
        .alert(Text("いまの記録を消して最初からはじめますか?"), isPresented: $confirmRestart) {
            Button(role: .destructive) {
                app.startNewGame()
            } label: {
                Text("最初から")
            }
            Button(role: .cancel) {} label: { Text("やめる") }
        }
    }

    private func choice(_ label: Text, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label.frame(maxWidth: 280, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
    }
}
