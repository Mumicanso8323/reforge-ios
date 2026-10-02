import SwiftUI
import ReForgeEngine

/// 足元カード: 注目しているマス(タップ・長押ししたマス、無ければノアの足元)の名前と、できること 1〜3 個。
/// 断られた理由はここに 1 行出す(ダイアログは出さない)。高さは固定して、地図が上下に揺れないようにする。
struct FootCardView: View {
    let store: GameStore

    var body: some View {
        InkBand(edge: .top, minHeight: 84) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(verbatim: store.footCard?.title ?? " ")
                        .font(InkFont.body)
                        .bold()
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let n = store.notice {
                        Text(verbatim: n)
                            .foregroundStyle(InkColor.notice)
                            .lineLimit(1)
                            .accessibilityIdentifier("notice")
                    }
                }
                HStack(spacing: 8) {
                    ForEach(store.footCard?.actions ?? [], id: \.id) { a in
                        ActionButton(action: a, store: store)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
        }
        .accessibilityIdentifier("footCard")
    }
}

/// 足元カードの 1 つの行為。押し続ける行為は押している間だけ進む(原作の手作業クリック方式)。
struct ActionButton: View {
    let action: FootCard.Action
    let store: GameStore
    @State private var pressing = false

    var body: some View {
        if action.hold {
            Text(verbatim: action.label)
                .font(InkFont.body)
                .foregroundStyle(pressing ? InkColor.onAccent : InkColor.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .fill(pressing ? InkColor.accent : InkColor.panel))
                .overlay(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .stroke(InkColor.rule, lineWidth: InkMetric.rule))
                .onLongPressGesture(minimumDuration: 3600, maximumDistance: 40, perform: {}, onPressingChanged: { p in
                    pressing = p
                    store.act(action, pressing: p)
                })
                .accessibilityAddTraits(.isButton)
        } else {
            Button {
                store.act(action, pressing: true)
            } label: {
                Text(verbatim: action.label)
                    .frame(height: 36)
            }
            .buttonStyle(.ink(.secondary, fill: false))
        }
    }
}

enum GameTab: String, CaseIterable, Identifiable {
    case map, design, notes, base, crew
    var id: String { rawValue }
}

/// 下のタブ(地図・設計・ノート・拠点・仲間)。
struct TabBarView: View {
    @Binding var tab: GameTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GameTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    title(t)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(tab == t ? InkColor.text : InkColor.textDim)
                        .overlay(alignment: .top) {
                            // いま開いているタブにだけ錆の線
                            Rectangle().fill(tab == t ? InkColor.accent : .clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-\(t.rawValue)")
            }
        }
        .font(InkFont.body)
        .background(InkColor.ground)
        .overlay(alignment: .top) {
            Rectangle().fill(InkColor.rule).frame(height: InkMetric.rule)
        }
    }

    @ViewBuilder private func title(_ t: GameTab) -> some View {
        switch t {
        case .map: Text("地図")
        case .design: Text("設計")
        case .notes: Text("ノート")
        case .base: Text("拠点")
        case .crew: Text("仲間")
        }
    }
}
