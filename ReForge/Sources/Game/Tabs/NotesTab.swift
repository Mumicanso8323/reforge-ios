import SwiftUI
import ReForgeEngine

/// ノートのタブ(試したこと・所見・素材の図鑑・資料)。担当: U17。
struct NotesTabView: View {
    @Bindable var app: AppModel
    let store: GameStore

    var body: some View {
        PlaceholderPanel {
            Text("ノート").font(.custom(FontBook.mapFont, size: 20)).bold()
            Text("試したこと・所見・素材の図鑑が載ります。まだできていません。")
        }
    }
}
