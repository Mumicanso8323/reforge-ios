import SwiftUI
import ReForgeEngine

/// 設計のタブ(縦の工程表で並びを決め、試す・札にする)。担当: U17。
struct DesignTabView: View {
    @Bindable var app: AppModel
    let store: GameStore

    var body: some View {
        PlaceholderPanel {
            Text("設計").font(InkFont.heading)
            Text("縦の工程表で並びを決め、試したり札にしたりする画面です。まだできていません。")
        }
    }
}
