import SwiftUI
import ReForgeEngine

/// 仲間のタブ(割り当て・関係)。担当: U18。
struct CrewTabView: View {
    @Bindable var app: AppModel
    let store: GameStore

    var body: some View {
        PlaceholderPanel {
            Text("仲間").font(InkFont.heading)
            ForEach(store.actors.filter(\.isMember), id: \.id) { a in
                HStack(spacing: 8) {
                    Text(verbatim: a.glyph).frame(width: 24)
                    Text(verbatim: a.label)
                }
            }
        }
    }
}
