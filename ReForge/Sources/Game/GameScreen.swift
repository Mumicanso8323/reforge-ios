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
        .background(Color.black)
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
        VStack(alignment: .leading, spacing: 14) {
            switch tab {
            case .map:
                EmptyView()
            case .design:
                Text("設計").font(.custom(FontBook.mapFont, size: 20)).bold()
                Text("縦の工程表で並びを決め、試したり札にしたりする画面です。まだできていません。")
            case .notes:
                Text("ノート").font(.custom(FontBook.mapFont, size: 20)).bold()
                Text("試したこと・所見・素材の図鑑が載ります。まだできていません。")
            case .base:
                Text("拠点").font(.custom(FontBook.mapFont, size: 20)).bold()
                Text("蓄え・建てた物・セーブが載ります。まだできていません。")
                Button {
                    showSettings = true
                } label: {
                    Text("設定")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await app.backToTitle() }
                } label: {
                    Text("タイトルへ")
                }
                .buttonStyle(.bordered)
            case .crew:
                Text("仲間").font(.custom(FontBook.mapFont, size: 20)).bold()
                ForEach(store.actors.filter(\.isMember), id: \.id) { a in
                    HStack(spacing: 8) {
                        Text(verbatim: a.glyph).frame(width: 24)
                        Text(verbatim: a.label)
                    }
                }
            }
            Spacer()
        }
        .font(.custom(FontBook.mapFont, size: 15))
        .foregroundStyle(Color(white: 0.92))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .sheet(isPresented: $showSettings) {
            SettingsView(app: app)
        }
    }
}

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
