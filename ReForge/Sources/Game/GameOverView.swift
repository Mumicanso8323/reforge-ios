import SwiftUI
import ReForgeEngine

/// ゲームオーバーの 4 択(同じ重さで並べる。D-save.md §3)。担当: U18。見た目は Theme(InkPlate)。
/// いまは「最初から」だけが動く(巻き戻し・失って続ける・セーブ地点からは保存と失敗の担当の中身が入ってから)。
/// 「最初から」は記録を消すので、確かめのダイアログの代わりに長押しで確定する(InkHoldButton)。
struct GameOverView: View {
    @Bindable var app: AppModel

    var body: some View {
        InkPlate(title: Text("ここまで")) {
            InkHoldButton(label: Text("最初から"), hint: Text("長押しで、いまの記録を消して最初から")) {
                app.startNewGame()
            }
            .accessibilityIdentifier("restartHold")
            choice(Text("記憶を持って巻き戻す"))
            choice(Text("失って続ける"))
            choice(Text("セーブ地点からロード"))
        }
        .accessibilityIdentifier("gameOver")
    }

    private func choice(_ label: Text) -> some View {
        Button {} label: { label }
            .buttonStyle(.ink(.secondary))
            .disabled(true)
    }
}
