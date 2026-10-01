import SwiftUI

/// ゲーム画面(仮)。ReForgeCore がアプリから使えることを確かめるための置き場。
struct GameView: View {
    @State private var session = GameSession()

    var body: some View {
        VStack(spacing: 24) {
            Text("ゲーム画面(準備中)")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("経過 \(session.elapsedTicks)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("elapsedLabel")
                Text("資源(仮) \(session.resource.amount) / \(session.resource.capacity)")
                    .font(.title2.monospacedDigit())
                    .accessibilityIdentifier("resourceLabel")
            }

            HStack(spacing: 16) {
                Button("集める") { session.gather() }
                    .buttonStyle(.bordered)
                    .disabled(session.resource.isFull)
                Button("ターン終了") { session.endTurn() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Re:Forge")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GameView()
    }
}
