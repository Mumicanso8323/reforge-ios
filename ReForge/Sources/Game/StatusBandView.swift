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
                        ForEach(store.status.filter { !$0.label.isEmpty && !$0.value.isEmpty }, id: \.key) { item in
                            HStack(spacing: 3) {
                                Text(verbatim: item.label).foregroundStyle(InkColor.textDim)
                                Text(verbatim: item.value)
                                    .foregroundStyle(item.alert ? InkColor.alert : InkColor.text)
                                if let g = item.gauge {
                                    // 棒と、意味の書かれていない目盛り(§10 HNT-05。U18)
                                    Text(verbatim: GaugeText.render(g, width: 12))
                                        .foregroundStyle(InkColor.textDim)
                                        .accessibilityIdentifier("gauge-\(item.key)")
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text(verbatim: item.label))
                            .accessibilityValue(Text(verbatim: item.value))
                            .accessibilityIdentifier("status-item-\(item.key)")
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            // 日没の火の見込みは見るだけの帯に残す。
            if store.decision == nil, !store.clock.bandActions.isEmpty, let o = store.clock.fireOutlook {
                HStack(spacing: 4) {
                    Text("火:")
                    FireOutlookLine.word(o)
                }
                .foregroundStyle(InkColor.textDim)
                .accessibilityIdentifier("duskFireOutlook")
            }
            if let r = store.resumeBanner {
                ResumeBannerView(line: r)
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
                    Text(verbatim: o)
                }
                .accessibilityIdentifier("statusObjective")
            }
        }
        .font(InkFont.small)
        .foregroundStyle(InkColor.text)
        .padding(.leading, 12)
        // 右上は設定のボタンの場所(InkMetric.settingsReserve)
        .padding(.trailing, InkMetric.settingsReserve)
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
            // 昼の残り(時間数は出さない)。時計を止めている間・門が閉じている間は出さない(U20)
            if store.clock.showsDayLeft {
                ProgressView(value: Double(store.clock.dayRemainingPermille), total: 1000)
                    .tint(InkColor.dusk)
                    .frame(width: 64)
            }
        case .dusk:
            Text("日没").foregroundStyle(InkColor.dusk)
        case .nightWork:
            Text("夜").foregroundStyle(InkColor.night)
        }
    }

}
