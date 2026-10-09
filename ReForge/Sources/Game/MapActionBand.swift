import SwiftUI
import ReForgeEngine

/// 親指の届く、地図の下端に重ねて置く時間と選びの帯(GameScreen の overlay。地図の枠は動かさない)。
struct MapActionBand: View {
    let store: GameStore

    var body: some View {
        if let pending = store.decisionUndo {
            UndoBand(label: pending.label, seconds: pending.seconds, undo: store.undoDecision)
        } else if let decision = store.decision {
            VStack(spacing: 8) {
                if let prompt = decision.prompt {
                    Text(verbatim: prompt)
                        .font(InkFont.body)
                        .foregroundStyle(InkColor.text)
                        .lineSpacing(InkFont.bodyLineSpacing / 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("decisionPrompt")
                }
                HStack(spacing: 8) {
                    ForEach(Array(decision.choices.enumerated()), id: \.offset) { _, choice in
                        Button { store.decide(choice.id) } label: { Text(verbatim: choice.label).frame(maxWidth: .infinity) }
                            .buttonStyle(.ink(.secondary))
                            .frame(minHeight: InkMetric.buttonHeight)
                    }
                }
            }
            .padding(8)
            .accessibilityElement(children: .contain)
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
            .frame(maxWidth: .infinity)  // 重ねの幅は地図の領域の幅(中身の理想の幅で広がって左へはみ出さない)
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

/// 帯を地図の下端に重ねる置き方の計算(純粋な関数。重ねるので、地図の枠は帯の高さによらない)。
enum BandOverlayLayout {
    /// 地図の領域(container)の中での地図の枠。帯が出ても出なくても(band が何でも)container 全体のまま。
    static func mapFrame(container: CGSize, band: CGFloat) -> CGRect {
        CGRect(origin: .zero, size: container)
    }

    /// 帯の枠。地図の領域の下端に、帯の高さ(領域の高さまで)で重なる。
    static func bandFrame(container: CGSize, band: CGFloat) -> CGRect {
        let h = min(max(band, 0), container.height)
        return CGRect(x: 0, y: container.height - h, width: container.width, height: h)
    }

    /// 帯が出ている間だけ、地図の操作部品を帯の高さぶん上げる。
    static func controlLift(band: CGFloat) -> CGFloat {
        max(band, 0)
    }

    /// 地図の高さの半分より上へは持ち上げない。
    static func controlLift(band: CGFloat, mapHeight: CGFloat) -> CGFloat {
        min(controlLift(band: band), max(mapHeight, 0) / 2)
    }
}

/// 地図に重なる帯の実測高さを親へ渡す。
struct MapBandHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
