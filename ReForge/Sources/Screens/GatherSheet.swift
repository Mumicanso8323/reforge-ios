import SwiftUI
import ReForgeCore

/// S2 採取。タップで即実行し、シートは閉じない(連打できる)。
struct GatherSheet: View {
    @Bindable var session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRest = false

    private var s: GameState { session.state }
    private var t: GameText { session.text }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(GatherKind.allCases, id: \.self) { kind in
                        row(kind)
                    }
                    Button {
                        if s.actionPointsLeft > 0 { confirmRest = true } else { rest() }
                    } label: {
                        Text("休む")
                    }
                    .disabled(s.phase != .day)
                } header: {
                    header
                }
            }
            .navigationTitle(Text("採取する"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: AdLayout.bottomButtonGap)
            }
            .confirmationDialog(Text(verbatim: t.restConfirm(s)), isPresented: $confirmRest, titleVisibility: .visible) {
                Button("休む") { rest() }
                Button("やめる", role: .cancel) {}
            }
        }
    }

    private func rest() {
        session.perform(.rest)
    }

    @ViewBuilder
    private var header: some View {
        if s.phase != .day {
            Text(verbatim: t.message(for: .notAllowed(s.phase)))
        } else if s.actionPointsLeft == 0 {
            Text(verbatim: t.message(for: .noActionPoints))
        } else {
            Text(verbatim: t.actionsLabel(s))
        }
    }

    private func row(_ kind: GatherKind) -> some View {
        let blocker = session.blocker(.gather(kind))
        let exhausted = kind == .scavenge && s.scavengeRemaining == 0
        return Button {
            session.perform(.gather(kind))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: t.gatherName(kind))
                        .foregroundStyle(.primary)
                    Text(verbatim: exhausted ? t.message(for: .scavengeExhausted) : t.gatherPreview(kind, in: s))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let flash = session.flash, flash.kind == kind {
                    GainFlash(text: flash.text, id: flash.id)
                }
            }
        }
        .disabled(blocker != nil)
        .accessibilityIdentifier("gather-\(kind.rawValue)")
    }
}

/// 行の右に出る「+4」。少しして消える。
struct GainFlash: View {
    let text: String
    let id: Int
    @State private var visible = false

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline.bold().monospacedDigit())
            .foregroundStyle(.green)
            .opacity(visible ? 1 : 0)
            .task(id: id) {
                visible = true
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeOut(duration: 0.3)) { visible = false }
            }
    }
}
