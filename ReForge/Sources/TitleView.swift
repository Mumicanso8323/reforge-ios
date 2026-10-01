import SwiftUI

/// タイトル画面。
struct TitleView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Re:Forge")
                .font(.system(size: 52, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onStart) {
                Text("はじめる")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("startButton")
            Spacer()
                .frame(height: 80)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    TitleView {}
}
