import SwiftUI
import ReForgeCore

/// S3 作る(製作)。純度・形状・英語 ID は出さない。
struct CraftSheet: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var counts: [RecipeID: Int] = [:]

    private var s: GameState { session.state }
    private var t: GameText { session.text }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.game.content.recipes, id: \.id) { recipe in
                        row(recipe)
                    }
                } header: {
                    if s.phase == .day || s.phase == .night {
                        Text(verbatim: t.actionsLabel(s))
                    }
                }
            }
            .navigationTitle(Text("作る"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: AdLayout.bottomButtonGap)
            }
        }
    }

    /// 材料と行動ポイントの両方で見た、作れる最大回数。
    private func maxTimes(_ r: RecipeDef) -> Int {
        min(s.actionPointsLeft, Crafting.maxTimes(r, in: s))
    }

    private func row(_ r: RecipeDef) -> some View {
        let maxN = maxTimes(r)
        let n = min(max(counts[r.id] ?? 1, 1), max(maxN, 1))
        let reason = session.blocker(.craft(r.id, times: 1)) ?? t.craftBlocker(r, in: s)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: r.name).font(.headline)
            Text(verbatim: t.recipeFormula(r))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let reason {
                Text(verbatim: reason)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Stepper(value: Binding(get: { n }, set: { counts[r.id] = $0 }), in: 1...max(maxN, 1)) {
                    Text(verbatim: "\(n)")
                        .monospacedDigit()
                }
                .disabled(maxN <= 1)
                .frame(maxWidth: 150)
                Spacer()
                Button {
                    if session.perform(.craft(r.id, times: n)) { counts[r.id] = 1 }
                } label: {
                    Text(verbatim: t.craftButton(times: n))
                }
                .buttonStyle(.borderedProminent)
                .disabled(reason != nil || maxN == 0)
                .accessibilityIdentifier("craft-\(r.id)")
            }
        }
        .padding(.vertical, 4)
    }
}
