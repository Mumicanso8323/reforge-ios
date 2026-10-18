import SwiftUI
import ReForgeEngine

/// 焚き火の見込みの 1 行(PT-B1)。「今: 夜半に消える → 1 本くべると: 夜明けまでもつ」。
/// 固定の文言 + 4 段の言葉(時間数は出さない)。足元カードのくべるのボタンの近くに出す。
struct FireOutlookLine: View {
    let fire: FireOutlookView

    var body: some View {
        // 4 つの断片を左から並べ、収まらない時は縮めず省略もせず、断片の切れ目で次の行へ折り返す
        InkFlowLayout(spacing: 4, lineSpacing: 2) {
            ui("ui.card.fire_now").inkFitCheck(id: "InkFireOutlook.now")
            Self.word(fire.now).inkFitCheck(id: "InkFireOutlook.nowWord")
            ui("ui.card.fire_after").inkFitCheck(id: "InkFireOutlook.after")
            Self.word(fire.afterOneMore).inkFitCheck(id: "InkFireOutlook.afterWord")
        }
        .font(InkFont.small)
        .foregroundStyle(InkColor.textDim)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fireOutlook")
    }

    /// 4 段の言葉。
    static func word(_ o: FireOutlook) -> Text {
        switch o {
        case .untilEvening: ui("ui.card.fire_until_evening")
        case .midnight: ui("ui.card.fire_midnight")
        case .beforeDawn: ui("ui.card.fire_before_dawn")
        case .throughNight: ui("ui.card.fire_through_night")
        }
    }
}
