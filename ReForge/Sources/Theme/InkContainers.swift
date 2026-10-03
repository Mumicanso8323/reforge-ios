import SwiftUI

/// タブの中身の土台(設計・ノート・拠点・仲間)。見出し 1 行と、縦に流れる中身。
/// 使い方: `InkPanel(title: Text("拠点")) { InkSection(title: Text("蓄え")) { … } }`
/// 中身が長いときは自分でスクロールする(ScrollView を中に置かなくてよい)。
struct InkPanel<Content: View>: View {
    var title: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let title {
                    title
                        .font(InkFont.heading)
                        .tracking(InkFont.headingTracking)
                        .foregroundStyle(InkColor.text)
                        .inkFitCheck(id: "InkPanel.title")
                        .accessibilityAddTraits(.isHeader)
                        .padding(.trailing, InkMetric.settingsReserve)
                }
                content
            }
            .padding(InkMetric.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(InkFont.body)
        .foregroundStyle(InkColor.text)
        .lineSpacing(InkFont.bodyLineSpacing / 2)
        .background(InkColor.ground)
    }
}

/// パネルの中の一まとまり。小さな見出しと罫線、その下に行を並べる。
struct InkSection<Content: View>: View {
    var title: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                title
                    .font(InkFont.small)
                    .foregroundStyle(InkColor.textDim)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            Rectangle().fill(InkColor.rule).frame(height: InkMetric.rule)
            content
        }
    }
}

/// 一覧の 1 行(高さ 44 以上・下に罫線)。左に記号 1 文字、名前、右に値。
/// 使い方: `InkRow(glyph: TilePalette.noahGlyph, title: Text(verbatim: name), value: Text(verbatim: "3"))`
/// 押せる行は Button の label に入れる(`Button { … } label: { InkRow(…) }.buttonStyle(.inkRow)`)。
struct InkRow: View {
    var glyph: String? = nil
    /// 記号の色(遊びの面の色。Color(rgb:) で本体の色を渡す)。
    var glyphColor: Color = InkColor.text
    let title: Text
    var detail: Text? = nil
    var value: Text? = nil
    var selected = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let glyph {
                Text(verbatim: glyph)
                    .font(.custom(FontBook.mapFont, size: 17))
                    .foregroundStyle(glyphColor)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                title.inkFitCheck(id: "InkRow.title").lineLimit(1)
                if let detail {
                    detail
                        .font(InkFont.small)
                        .foregroundStyle(InkColor.textDim)
                        .inkFitCheck(id: "InkRow.detail")
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                value
                    .foregroundStyle(InkColor.textDim)
                    .monospacedDigit()
                    .inkFitCheck(id: "InkRow.value")
                    .lineLimit(1)
            }
        }
        .font(InkFont.body)
        .foregroundStyle(InkColor.text)
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: InkMetric.rowHeight, alignment: .leading)
        .background(selected ? InkColor.raised : .clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(InkColor.accent).frame(width: 2) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(InkColor.rule.opacity(0.6)).frame(height: InkMetric.rule)
        }
        .contentShape(Rectangle())
    }
}

/// 押せる一覧の行(押している間だけ地が上がる)。
struct InkRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? InkColor.raised : .clear)
    }
}

extension ButtonStyle where Self == InkRowButtonStyle {
    static var inkRow: InkRowButtonStyle { InkRowButtonStyle() }
}

/// 帯(画面の上下に張りつく細長い面)。状態の帯・足元カード・タブはこれに載せる。
/// edge は罫線を引く側(上の帯なら .bottom)。
struct InkBand<Content: View>: View {
    var edge: VerticalEdge = .bottom
    var minHeight: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(InkFont.small)
            .foregroundStyle(InkColor.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(InkColor.ground)
            .overlay(alignment: edge == .bottom ? .bottom : .top) {
                Rectangle().fill(InkColor.rule).frame(height: InkMetric.rule)
            }
    }
}

/// 中央に置く札(ゲームオーバーのように、地図の上に重ねて選ばせるもの)。
/// 背景は暗く沈め、札そのものは画面の幅から 16pt ずつ内側。
struct InkPlate<Content: View>: View {
    var title: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            InkColor.field.opacity(0.82).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                if let title {
                    title
                        .font(InkFont.heading)
                        .tracking(InkFont.headingTracking)
                        .inkFitCheck(id: "InkPlate.title")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                }
                content
            }
            .font(InkFont.body)
            .foregroundStyle(InkColor.text)
            .padding(20)
            .frame(maxWidth: 360)
            .background(InkColor.panel)
            .overlay(Rectangle().stroke(InkColor.rule, lineWidth: InkMetric.rule))
            .padding(.horizontal, InkMetric.gutter)
        }
    }
}
