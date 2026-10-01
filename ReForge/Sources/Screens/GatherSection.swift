import SwiftUI
import ReForgeCore

/// S2 採取。拠点の画面に直接並べる。行をタップすると即実行し、右に「+4」が一瞬出る(開け閉めなしで連打できる)。
/// 日没・夜は行を薄くして、見出しに理由を出す(画面は切り替えない)。
struct GatherSection: View {
    let session: GameSession

    private var s: GameState { session.state }
    private var t: GameText { session.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                ForEach(Array(GatherKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().padding(.leading, 12) }
                    row(kind)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityIdentifier("gatherSection")
    }

    @ViewBuilder
    private var header: some View {
        switch s.phase {
        case .dusk:
            Text(verbatim: t.duskHint(canWorkAtNight: session.canStartNightWork))
        case .night, .dawn:
            Text(verbatim: t.message(for: .notAllowed(s.phase)))
        case .day:
            if s.actionPointsLeft == 0 {
                Text(verbatim: t.message(for: .noActionPoints))
            } else {
                Text("採取")
            }
        }
    }

    private func row(_ kind: GatherKind) -> some View {
        let blocked = session.blocker(.gather(kind)) != nil
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
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(blocked)
        .opacity(blocked ? 0.45 : 1)
        .accessibilityIdentifier("gather-\(kind.rawValue)")
    }
}

/// 行の押し込みを薄い背景で見せる(リストの行と同じ手ごたえ)。
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.secondary.opacity(0.25) : Color.clear)
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
