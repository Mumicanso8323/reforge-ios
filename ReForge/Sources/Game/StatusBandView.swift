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
            InkFlowLayout(spacing: 10, lineSpacing: 4) {
                ui("ui.band.day", ["day": .int(store.clock.day)])
                    .bold()
                phase
                if let g = store.fireGauge, store.ui.isOpen(UIElements.bandFire) {
                    fireGauge(g)
                }
                ForEach(store.status.filter { !$0.label.isEmpty && !$0.value.isEmpty }, id: \.key) { item in
                    HStack(spacing: 3) {
                        spokenText(item.label).foregroundStyle(InkColor.textDim)
                        spokenText(item.value)
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
                    .accessibilityLabel(spokenText(item.label))
                    .accessibilityValue(spokenText(item.value))
                    .accessibilityIdentifier("status-item-\(item.key)")
                }
            }
            if let r = store.resumeBanner {
                ResumeBannerView(line: r)
            }
            if sealedContentFailed {
                ui("ui.band.sealed_failed")
                    .font(InkFont.caption)
                    .foregroundStyle(InkColor.textDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sealedContentNotice")
            }
            if let o = store.objective {
                HStack(spacing: 6) {
                    ui("ui.band.objective").foregroundStyle(InkColor.textDim)
                    spokenText(o)
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
        // 子の識別子(status-item-*)を上書きしないよう、まとめずに含む形にする(折り返しのレイアウトでは項目が直の子になる)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("statusBand")
    }

    /// 火のゲージ: 見出し + 5 段の言葉。状態の表示で、押せる物ではない。
    private func fireGauge(_ g: FireGaugeView) -> some View {
        let word = Self.fireWord(g.level)
        return HStack(spacing: 3) {
            ui("ui.band.fire").foregroundStyle(InkColor.textDim)
            spokenText(word).foregroundStyle(Self.fireColor(g))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(spokenText(word))
        .accessibilityIdentifier("fireGauge")
    }

    /// 5 段の固定の言葉(日本語は画面の側)。
    @MainActor private static func fireWord(_ l: HearthLevel) -> String {
        switch l {
        case .out: UIText.shared.string("ui.band.fire_out")
        case .smoldering: UIText.shared.string("ui.band.fire_smoldering")
        case .flickering: UIText.shared.string("ui.band.fire_flickering")
        case .burning: UIText.shared.string("ui.band.fire_burning")
        case .roaring: UIText.shared.string("ui.band.fire_roaring")
        }
    }

    private static func fireColor(_ g: FireGaugeView) -> Color {
        if g.level == .out { return InkColor.alert }
        switch g.outlook {
        case .throughNight: return InkColor.text
        case .beforeDawn, .midnight: return InkColor.notice
        case .untilEvening: return InkColor.alert
        }
    }

    @ViewBuilder private var phase: some View {
        switch store.clock.phase {
        case .day:
            // 昼の残り(時間数は出さない)。時計を止めている間・門が閉じている間は出さない(U20)
            if store.clock.showsDayLeft {
                DayBarView(elapsedPermille: 1000 - store.clock.dayRemainingPermille, dots: store.dayBarDots, word: store.timeWord)
            }
        case .dusk:
            ui("ui.band.dusk").foregroundStyle(InkColor.dusk)
        case .nightWork:
            ui("ui.band.night").foregroundStyle(InkColor.night)
        }
    }

}
