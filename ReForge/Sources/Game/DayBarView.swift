import SwiftUI

/// 帯の昼の残り(UI-03)。細い棒 1 本に、目印の点(言葉が替わる所と日没)と今の印、右に今の目印の言葉。
/// 今の位置から右(残り)を夕の色、左(過ぎた分)を罫の色で塗る(残りが縮んで見える)。
/// 色は全部 `InkColor` の固定の札で、時刻にも端末の外観にも依らない。数・時刻・説明は出さない。
struct DayBarView: View {
    /// 昼のうち過ぎた分(‰。0...1000)。
    let elapsedPermille: Int
    /// 点の位置(‰。昇順)。4 つまで描く。
    let dots: [Int]
    /// 今の目印の言葉(内容の表から。無ければ出さない)。
    let word: String?

    static let barWidth: CGFloat = 80
    static let barHeight: CGFloat = 3
    static let dotSize: CGFloat = 4
    static let markSize = CGSize(width: 2, height: 10)

    private func x(_ permille: Int) -> CGFloat {
        Self.barWidth * CGFloat(max(0, min(1000, permille))) / 1000
    }

    var body: some View {
        HStack(spacing: 6) {
            bar
            if let word, !word.isEmpty {
                Text(verbatim: word)
                    .font(InkFont.small)
                    .foregroundStyle(InkColor.textDim)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: word ?? ""))
        .accessibilityIdentifier("dayBar")
    }

    private var bar: some View {
        ZStack(alignment: .leading) {
            // 過ぎた分(左)と残り(右)
            Rectangle().fill(InkColor.rule)
                .frame(width: x(elapsedPermille), height: Self.barHeight)
            Rectangle().fill(InkColor.dusk)
                .frame(width: Self.barWidth - x(elapsedPermille), height: Self.barHeight)
                .offset(x: x(elapsedPermille))
            ForEach(Array(dots.prefix(4).enumerated()), id: \.offset) { _, dot in
                Circle().fill(InkColor.textDim)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .offset(x: x(dot) - Self.dotSize / 2)
                    .accessibilityHidden(true)
            }
            Rectangle().fill(InkColor.text)
                .frame(width: Self.markSize.width, height: Self.markSize.height)
                .offset(x: x(elapsedPermille) - Self.markSize.width / 2)
                .accessibilityHidden(true)
        }
        .frame(width: Self.barWidth, height: Self.markSize.height, alignment: .leading)
    }
}
