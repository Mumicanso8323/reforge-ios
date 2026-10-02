import SwiftUI
import ReForgeEngine

/// 主画面(order.md §5.5)。縦の並び: 状態の帯 / 地図(残り全部) / 足元カード / タブ / (下の広告枠)。
/// 広告枠は RootView の AdBannerContainer が下に 1 つ確保する。
struct GameScreen: View {
    @Bindable var app: AppModel
    let store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mapVisible = false
#if DEBUG
    // 撮る起動(Debug/ScreenshotMode.swift)は、最初のタブと設定の札を外から決める
    @State private var tab: GameTab = ScreenshotMode.firstTab
    @State private var showScreenshotSettings = ScreenshotMode.opensSettings
#else
    @State private var tab: GameTab = .map
#endif

    var body: some View {
        Group {
            if let darkStart = store.darkStart {
                DarkStartScene(action: darkStart.action, store: store)
            } else {
                game
            }
        }
        .background(InkColor.field)
        .task { await store.run() }
        .onAppear { mapVisible = store.darkStart == nil }
        .onChange(of: store.darkStart) { old, new in
            guard old != nil, new == nil else { return }
            mapVisible = false
            withAnimation(.easeOut(duration: reduceMotion ? 0.3 : 0.8)) {
                mapVisible = true
            }
        }
        .onChange(of: store.requestedTab) { _, t in
            // パネルからの切り替え(置くモードで地図へ。U18)
            if let t { tab = t; store.requestedTab = nil }
        }
    }

    private var game: some View {
        VStack(spacing: 0) {
            if store.prologue == nil {
                StatusBandView(store: store, sealedContentFailed: app.sealedContentFailed || ArtProvider.shared.failed)
                BattleBandView(store: store)
            }
            ZStack {
                // 地図は他のタブの間も残す(視点を保つ。時計も止めない)
                MapCanvasView(store: store)
                    .opacity(tab == .map ? 1 : 0)
                    .allowsHitTesting(tab == .map)
                    .opacity(mapVisible ? 1 : 0)
                    .mask {
                        if reduceMotion {
                            Rectangle()
                        } else {
                            GeometryReader { geo in
                                Circle()
                                    .scale(mapVisible ? 4 : 0.001)
                                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            }
                        }
                    }
                if tab != .map {
                    PanelView(tab: tab, app: app, store: store)
                }
                if store.runEnded {
                    GameOverView(app: app, store: store)
                }
                if let prologue = store.prologue {
                    PrologueLayer(prologue: prologue, store: store)
                        .transition(.opacity.animation(.easeOut(duration: 0.8)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if tab == .map, store.prologue == nil {
                FootCardView(store: store)
            }
            if store.prologue == nil {
                TabBarView(tab: $tab, ui: store.ui)
            }
        }
        .padding(.vertical, AdLayout.contentGap)
#if DEBUG
        .inkCard(isPresented: $showScreenshotSettings, title: Text("設定")) {
            SettingsView(app: app, close: { showScreenshotSettings = false })
        }
#endif
    }
}

/// 地図以外のタブ。中身はタブごとのファイルに分ける(担当がぶつからないように。F §4):
/// - 設計 `Tabs/DesignTab.swift`・ノート `Tabs/NotesTab.swift`: U17
/// - 拠点 `Tabs/BaseTab.swift`・仲間 `Tabs/CrewTab.swift`・`GameOverView.swift`・`TabBarView.swift`: U18
/// - 色・書体・部品 `Theme/`: art-director
/// このファイル(並べ方)は統合担当。タブを足すときは GameTab に case を足し、ここに 1 行足す。
struct PanelView: View {
    let tab: GameTab
    @Bindable var app: AppModel
    let store: GameStore

    var body: some View {
        switch tab {
        case .map: EmptyView()
        case .design: DesignTabView(app: app, store: store)
        case .notes: NotesTabView(app: app, store: store)
        case .base: BaseTabView(app: app, store: store)
        case .crew: CrewTabView(app: app, store: store)
        }
    }
}

/// タブの中身の仮の枠(各担当が置き換えるまでの共通の見た目)。
struct PlaceholderPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // 見た目は Theme の InkPanel(各担当は InkPanel を直接使ってよい)
        InkPanel {
            content
        }
    }
}
