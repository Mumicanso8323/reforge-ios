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
                    ui("ui.band.made_label").foregroundStyle(InkColor.textDim)
                        .lineLimit(1).fixedSize().layoutPriority(1)  // 見出しは縮めない(縮めるのは物の名前の並びだけ)
                        .accessibilityIdentifier("dayWrapMadeLabel")
                    spokenText(wrap.made.map { UIText.shared.string("ui.band.made_item", ["name": .string($0.name), "count": .int($0.count)]) }.joined(separator: UIText.shared.string("ui.band.made_sep")))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("dayWrapMade")
                }
            }
            if let running = wrap.running {
                spokenText(running).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dayWrapRunning")
            }
            if let outlook = wrap.outlook {
                HStack(spacing: 6) {
                    ui("ui.band.tomorrow_label").foregroundStyle(InkColor.textDim)
                        .lineLimit(1).fixedSize().layoutPriority(1)
                        .accessibilityIdentifier("dayWrapOutlookLabel")
                    spokenText(outlook).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("dayWrapOutlook")
                }
            }
        }
        // 親が決めた幅の中に収める(中身の理想の幅が親より広いと、中央寄せの重ねで左へはみ出して切れる)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 再開の 1 行(PT-B2)。「前回: 〈last〉。次: 〈next〉」。last が無ければ「前回:」の部分を出さない。
struct ResumeBannerView: View {
    let line: ResumeLine

    var body: some View {
        Group {
            if let last = line.last, let next = line.next {
                ui("ui.band.resume_both", ["last": .string(last), "next": .string(next)])
            } else if let last = line.last {
                ui("ui.band.resume_last", ["last": .string(last)])
            } else if let next = line.next {
                ui("ui.band.resume_next", ["next": .string(next)])
            }
        }
        .lineLimit(2)
        .foregroundStyle(InkColor.textDim)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("resumeBanner")
    }
}
