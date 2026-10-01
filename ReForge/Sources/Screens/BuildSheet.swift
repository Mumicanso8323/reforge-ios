import SwiftUI
import ReForgeCore

/// S4 建てる(建造)。
struct BuildSheet: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss

    private var s: GameState { session.state }
    private var t: GameText { session.text }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.game.content.blueprints, id: \.id) { bp in
                        row(bp)
                    }
                } header: {
                    if s.phase == .day {
                        Text(verbatim: t.actionsLabel(s))
                    } else {
                        Text(verbatim: t.message(for: .notAllowed(s.phase)))
                    }
                }
            }
            .navigationTitle(Text("建てる"))
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

    private func row(_ bp: BlueprintDef) -> some View {
        let built = s.has(bp.id)
        let blocker = session.blocker(.build(bp.id))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: bp.name).font(.headline)
                Spacer()
                if built {
                    Text("建設済み")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.3)))
                }
            }
            HStack(spacing: 10) {
                ForEach(bp.cost, id: \.item) { c in
                    Text(verbatim: "\(t.name(c.item)) \(c.quantity)")
                        .font(.subheadline)
                        .foregroundStyle(!built && s.quantity(c.item) < c.quantity ? Color.red : Color.secondary)
                }
            }
            Text(verbatim: bp.effect)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !built {
                Button {
                    session.perform(.build(bp.id))
                } label: {
                    Text("建てる(1 行動)")
                }
                .buttonStyle(.borderedProminent)
                .disabled(blocker != nil)
                .accessibilityIdentifier("build-\(bp.id)")
            }
        }
        .padding(.vertical, 4)
        .opacity(built ? 0.6 : 1)
    }
}
