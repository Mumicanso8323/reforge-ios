import SwiftUI
import ReForgeEngine

/// 夜の締めの 3 行(PT-B2)。日没の「夜作業 / 寝る」の 2 つのボタンの上に出す。シートも確認も使わない。
/// ボタンを押すと日没が終わり、Frame の dayWrap が消えるので、この行も消える。
/// 文言は固定の文言と、数・物の名前だけ。
struct DayWrapLinesView: View {
    let wrap: DayWrapView
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 見出しと中身の並べ方。大きい文字(アクセシビリティの大きさ)では見出しを上に置き、中身に幅を全部渡す
    /// (横に並べると見出しが幅を取り、中身が 1 字ずつ折り返して縦に長く伸びる)。
    private var row: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 6))
    }

    /// 見出し。横に並べる時は縮めない(縮めるのは中身の並びだけ)。上に置く時は幅に合わせて折り返す。
    @ViewBuilder private func label(_ text: Text, _ identifier: String) -> some View {
        if typeSize.isAccessibilitySize {
            text.foregroundStyle(InkColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        } else {
            text.foregroundStyle(InkColor.textDim)
                .lineLimit(1).fixedSize().layoutPriority(1)
                .accessibilityIdentifier(identifier)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !wrap.made.isEmpty {
                row {
                    label(ui("ui.band.made_label"), "dayWrapMadeLabel")
                    // 物の名前の並びは省略せず折り返す(長い名前・多い品でも全部読める)
                    spokenText(wrap.made.map { UIText.shared.string("ui.band.made_item", ["name": .string($0.name), "count": .int($0.count)]) }.joined(separator: UIText.shared.string("ui.band.made_sep")))
                        .inkFitCheck(id: "InkDayWrap.made")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("dayWrapMade")
                }
            }
            if let running = wrap.running {
                spokenText(running)
                    .inkFitCheck(id: "InkDayWrap.running")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("dayWrapRunning")
            }
            if let outlook = wrap.outlook {
                row {
                    label(ui("ui.band.tomorrow_label"), "dayWrapOutlookLabel")
                    spokenText(outlook)
                        .inkFitCheck(id: "InkDayWrap.outlook")
                        .fixedSize(horizontal: false, vertical: true)
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
