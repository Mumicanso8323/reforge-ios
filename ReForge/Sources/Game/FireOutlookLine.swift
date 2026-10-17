import SwiftUI
import ReForgeEngine

/// 焚き火の見込みの 1 行(PT-B1)。「今: 夜半に消える → 1 本くべると: 夜明けまでもつ」。
/// 固定の文言 + 4 段の言葉(時間数は出さない)。足元カードのくべるのボタンの近くに出す。
struct FireOutlookLine: View {
    let fire: FireOutlookView

    var body: some View {
        HStack(spacing: 4) {
            ui("ui.card.fire_now")
            Self.word(fire.now)
            ui("ui.card.fire_after")
            Self.word(fire.afterOneMore)
        }
        .font(InkFont.small)
        .foregroundStyle(InkColor.textDim)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fireOutlook")
    }

    /// 4 段の言葉。
    @ViewBuilder static func word(_ o: FireOutlook) -> some View {
        switch o {
        case .untilEvening: ui("ui.card.fire_until_evening")
        case .midnight: ui("ui.card.fire_midnight")
        case .beforeDawn: ui("ui.card.fire_before_dawn")
        case .throughNight: ui("ui.card.fire_through_night")
        }
    }
}
