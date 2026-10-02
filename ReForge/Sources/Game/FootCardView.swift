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
                    // 残骸から開く資料(段階つきの資料など。U18)
                    ForEach(store.footCard?.documents ?? [], id: \.id) { d in
                        Button { store.openPanel(d.id) } label: { Text(verbatim: d.title) }
                            .buttonStyle(.ink(.quiet, fill: false))
                            .accessibilityIdentifier("panel-\(d.id.rawValue)")
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
