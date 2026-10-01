import SwiftUI

/// S0 タイトル。
struct TitleView: View {
    @Bindable var app: AppModel
    @State private var confirmRestart = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(verbatim: "Re:Forge")
                .font(.system(size: 52, weight: .bold, design: .serif))
            Text("素材から、作り直す")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
            VStack(spacing: 12) {
                if app.hasResume {
                    Button {
                        app.continueGame()
                    } label: {
                        Text("つづきから").frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("continueButton")
                }
                if app.hasResume {
                    Button {
                        confirmRestart = true
                    } label: {
                        Text("はじめから").frame(maxWidth: 240)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("newGameButton")
                } else {
                    Button {
                        app.startNewGame()
                    } label: {
                        Text("はじめから").frame(maxWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("newGameButton")
                }
                Button {
                    showSettings = true
                } label: {
                    Text("設定").frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Spacer().frame(height: 60)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, AdLayout.contentGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("いまの記録を消して最初からはじめますか?", isPresented: $confirmRestart) {
            Button("はじめから", role: .destructive) { app.startNewGame() }
            Button("やめる", role: .cancel) {}
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(app: app)
        }
    }
}
