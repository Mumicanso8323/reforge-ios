import SwiftUI
import ReForgeEngine

/// 上の状態の帯: 日・昼の残り・拠点の数値(食料と水の残り日数など。見せ方は認識の層)・次の目標 1 つ。
/// 夜になったとき・寝るかどうか・決断はここで選ぶ(全画面のシートで止めない)。
struct StatusBandView: View {
    let store: GameStore
    /// 封をした物語のデータを開けず、公開の層だけで動いているとき(1 行だけ出す。遊ぶのは止めない)。
    var sealedContentFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    Text(verbatim: "\(store.clock.day)")
                    Text("日目")
                }
                .bold()
                phase
                Spacer(minLength: 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.status, id: \.key) { item in
                            HStack(spacing: 3) {
                                Text(verbatim: item.label).foregroundStyle(InkColor.textDim)
                                Text(verbatim: item.value)
                                    .foregroundStyle(item.alert ? InkColor.alert : InkColor.text)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let d = store.decision {
                HStack(spacing: 8) {
                    ForEach(Array(d.choices.enumerated()), id: \.offset) { _, c in
                        Button {
                            store.decide(c.id)
                        } label: {
                            Text(verbatim: c.label).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.ink(.secondary))
                    }
                }
            } else if !store.clock.bandActions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(store.clock.bandActions, id: \.self) { a in
                        Button {
                            store.choose(a)
                        } label: {
                            label(a).frame(maxWidth: .infinity)
                        }
                        // 寝るが主(錆)、夜作業は並びの選択肢
                        .buttonStyle(.ink(a == .sleep ? .primary : .secondary))
                        .accessibilityIdentifier(a == .sleep ? "sleepButton" : "nightWorkButton")
                    }
                }
            }
            if sealedContentFailed {
                Text("物語のデータを読めなかったので、試遊用のデータで動いています")
                    .font(InkFont.caption)
                    .foregroundStyle(InkColor.textDim)
                    .lineLimit(1)
                    .accessibilityIdentifier("sealedContentNotice")
            }
            if let o = store.objective {
                HStack(spacing: 6) {
                    Text("目標").foregroundStyle(InkColor.textDim)
                    Text(verbatim: o).lineLimit(1)
                }
            }
        }
        .font(InkFont.small)
        .foregroundStyle(InkColor.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InkColor.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(InkColor.rule).frame(height: InkMetric.rule)
        }
        .accessibilityIdentifier("statusBand")
    }

    @ViewBuilder private var phase: some View {
        switch store.clock.phase {
        case .day:
            // 昼の残り(時間数は出さない)
            ProgressView(value: Double(store.clock.dayRemainingPermille), total: 1000)
                .tint(InkColor.dusk)
                .frame(width: 64)
        case .dusk:
            Text("日没").foregroundStyle(InkColor.dusk)
        case .nightWork:
            Text("夜").foregroundStyle(InkColor.night)
        }
    }

    @ViewBuilder private func label(_ a: BandAction) -> some View {
        switch a {
        case .startNightWork: Text("夜作業をする")
        case .sleep: Text("寝る")
        }
    }
}
