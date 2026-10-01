import SwiftUI

@main
struct ReForgeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 画面遷移の行き先。
enum Route: Hashable {
    case game
}

/// 全画面の共通の土台。広告枠コンテナの内側に NavigationStack を置くので、
/// どの画面に遷移しても上下の広告枠はそのまま残る。
struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        AdBannerContainer {
            NavigationStack(path: $path) {
                TitleView { path.append(.game) }
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .game:
                            GameView()
                        }
                    }
            }
        }
    }
}

#Preview {
    RootView()
}
