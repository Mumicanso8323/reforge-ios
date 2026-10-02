import SwiftUI
import ReForgeEngine

/// 主画面(order.md §5.5)。縦の並び: (上の広告枠) / 状態の帯 / 地図(残り全部) / 足元カード / タブ / (下の広告枠)。
/// 広告枠は RootView の AdBannerContainer が上下に確保する。
struct GameScreen: View {
    @Bindable var app: AppModel
    let store: GameStore
    @State private var tab: GameTab = .map

    var body: some View {
        VStack(spacing: 0) {
            StatusBandView(store: store, sealedContentFailed: app.sealedContentFailed)
            ZStack {
                // 地図は他のタブの間も残す(視点を保つ。時計も止めない)
                MapCanvasView(store: store)
                    .opacity(tab == .map ? 1 : 0)
                    .allowsHitTesting(tab == .map)
                if tab != .map {
                    PanelView(tab: tab, app: app, store: store)
                }
                if store.runEnded {
                    GameOverView(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if tab == .map {
                FootCardView(store: store)
            }
            TabBarView(tab: $tab)
        }
        .padding(.vertical, AdLayout.contentGap)
        .background(InkColor.field)
        .task { await store.run() }
    }
}

/// 地図以外のタブ。いまは枠だけ(設計の縦の工程表・ノート・拠点・仲間は各担当の中身が入ってから)。
struct PanelView: View {
    let tab: GameTab
    @Bindable var app: AppModel
    let store: GameStore
    @State private var showSettings = false

    var body: some View {
        content
            .inkCard(isPresented: $showSettings, title: Text("設定")) {
                SettingsView(app: app, close: { showSettings = false })
            }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .map:
            EmptyView()
        case .design:
            InkPanel(title: Text("設計")) {
                Text("縦の工程表で並びを決め、試したり札にしたりする画面です。まだできていません。")
                    .foregroundStyle(InkColor.textDim)
            }
        case .notes:
            InkPanel(title: Text("ノート")) {
                Text("試したこと・所見・素材の図鑑が載ります。まだできていません。")
                    .foregroundStyle(InkColor.textDim)
            }
        case .base:
            InkPanel(title: Text("拠点")) {
                Text("蓄え・建てた物・セーブが載ります。まだできていません。")
                    .foregroundStyle(InkColor.textDim)
                InkSection {
                    Button {
                        showSettings.toggle()
                    } label: {
                        InkRow(title: Text("設定"), value: Text(verbatim: "›"))
                    }
                    .buttonStyle(.inkRow)
                    Button {
                        Task { await app.backToTitle() }
                    } label: {
                        InkRow(title: Text("タイトルへ"), value: Text(verbatim: "›"))
                    }
                    .buttonStyle(.inkRow)
                }
            }
        case .crew:
            InkPanel(title: Text("仲間")) {
                InkSection {
                    ForEach(store.actors.filter(\.isMember), id: \.id) { a in
                        InkRow(glyph: a.glyph, title: Text(verbatim: a.label))
                    }
                }
            }
        }
    }
}

/// ゲームオーバーの 4 択(同じ重さで並べる。D-save.md §3)。
/// いまは「最初から」だけが動く(巻き戻し・失って続ける・セーブ地点からは保存と失敗の担当の中身が入ってから)。
/// 「最初から」は記録を消すので、確かめのダイアログの代わりに長押しで確定する。
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
