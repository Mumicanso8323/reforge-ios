import SwiftUI
import ReForgeEngine

/// 夜の締めの 3 行(PT-B2)。日没の「夜作業 / 寝る」の 2 つのボタンの上に出す。シートも確認も使わない。
/// ボタンを押すと日没が終わり、Frame の dayWrap が消えるので、この行も消える。
/// 文言は固定の文言と、数・物の名前だけ。
struct DayWrapLinesView: View {
    let wrap: DayWrapView

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !wrap.made.isEmpty {
                HStack(spacing: 6) {
                    Text("今日できた物").foregroundStyle(InkColor.textDim)
                    Text(verbatim: wrap.made.map { "\($0.name) \($0.count)" }.joined(separator: "\u{30FB}")).lineLimit(1)
                }
            }
            if let running = wrap.running {
                Text(verbatim: running).lineLimit(1)
            }
            if let outlook = wrap.outlook {
                HStack(spacing: 6) {
                    Text("明日").foregroundStyle(InkColor.textDim)
                    Text(verbatim: outlook).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("dayWrap")
    }
}

/// 再開の 1 行(PT-B2)。「前回: 〈last〉。次: 〈next〉」。last が無ければ「前回:」の部分を出さない。
struct ResumeBannerView: View {
    let line: ResumeLine

    var body: some View {
        Group {
            if let last = line.last, let next = line.next {
                Text("前回: \(last)。次: \(next)")  // xcstrings: @,@
            } else if let last = line.last {
                Text("前回: \(last)")  // xcstrings: @
            } else if let next = line.next {
                Text("次: \(next)")  // xcstrings: @
            }
        }
        .lineLimit(2)
        .foregroundStyle(InkColor.textDim)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("resumeBanner")
    }
}
