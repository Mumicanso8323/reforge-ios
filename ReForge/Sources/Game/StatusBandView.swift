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
            // 日・昼の残り・数値の項目は、帯の幅(右は設定の角の分を空けた幅)で折り返す。横に流して切らない。
            StatusFlowLayout(spacing: 10, lineSpacing: 4) {
                HStack(spacing: 0) {
                    Text(verbatim: "\(store.clock.day)")
                    Text("日目")
                }
                .bold()
                phase
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
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(verbatim: item.label))
                    .accessibilityValue(Text(verbatim: item.value))
                    .accessibilityIdentifier("status-item-\(item.key)")
                }
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

/// 子を左から並べ、幅に収まらなければ次の行へ折り返す(帯の項目用)。どの子も提案の幅より広くしない。
private struct StatusFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowH + lineSpacing
                rowH = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + rowH))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let r = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? r.size.width, height: r.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (sub, f) in zip(subviews, r.frames) {
            sub.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                      anchor: .topLeading, proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}
