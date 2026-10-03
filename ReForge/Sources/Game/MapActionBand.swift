import SwiftUI
import ReForgeEngine

/// 親指の届く、足元カードの直前に置く時間と選びの帯。
struct MapActionBand: View {
    let store: GameStore

    var body: some View {
        if let pending = store.decisionUndo {
            UndoBand(label: pending.label, seconds: pending.seconds, undo: store.undoDecision)
        } else if let decision = store.decision {
            HStack(spacing: 8) {
                ForEach(Array(decision.choices.enumerated()), id: \.offset) { _, choice in
                    Button { store.decide(choice.id) } label: { Text(verbatim: choice.label).frame(maxWidth: .infinity) }
                        .buttonStyle(.ink(.secondary))
                }
            }
            .padding(8)
            .background(InkColor.panel.opacity(0.96))
            .accessibilityIdentifier("decisionBand")
        } else if !store.clock.bandActions.isEmpty {
            VStack(spacing: 6) {
                if let wrap = store.dayWrap, !wrap.isEmpty { DayWrapLinesView(wrap: wrap) }
                HStack(spacing: 8) {
                    ForEach(store.clock.bandActions, id: \.self) { action in
                        Button { store.choose(action) } label: { label(action).frame(maxWidth: .infinity) }
                            .buttonStyle(.ink(action == .sleep ? .primary : .secondary))
                    }
                }
            }
            .padding(8)
            .background(InkColor.panel.opacity(0.96))
        }
    }

    @ViewBuilder private func label(_ action: BandAction) -> some View {
        switch action {
        case .startNightWork: Text("夜作業をする")
        case .sleep: Text("寝る")
        }
    }
}
