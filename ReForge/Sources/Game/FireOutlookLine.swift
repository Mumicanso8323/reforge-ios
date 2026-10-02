import SwiftUI
import ReForgeEngine

/// 焚き火の見込みの 1 行(PT-B1)。「今: 夜半に消える → 1 本くべると: 夜明けまでもつ」。
/// 固定の文言 + 4 段の言葉(時間数は出さない)。足元カードのくべるのボタンの近くに出す。
struct FireOutlookLine: View {
    let fire: FireOutlookView

    var body: some View {
        HStack(spacing: 4) {
            Text("今:")
            Self.word(fire.now)
            Text("→ 1 本くべると:")
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
        case .untilEvening: Text("夕方に消える")
        case .midnight: Text("夜半に消える")
        case .beforeDawn: Text("夜明けの前に消える")
        case .throughNight: Text("夜明けまでもつ")
        }
    }
}
