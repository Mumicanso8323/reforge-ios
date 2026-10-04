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
                    } else if store.footCard?.nothingNearby == true {
                        // 続けて採るのが止まった(PT-B1。固定の文言)
                        Text("近くにもう無い")
                            .foregroundStyle(InkColor.notice)
                            .lineLimit(1)
                            .accessibilityIdentifier("nothingNearby")
                    }
                }
                if let hint = store.footCard?.hint {
                    Text(verbatim: hint)
                        .font(InkFont.small)
                        .foregroundStyle(InkColor.textDim)
                        .lineLimit(1)
                        .accessibilityIdentifier("footCardHint")
                }
                // 焚き火の火の見込み(PT-B1。焚き火のカードだけ)
                if let fire = store.footCard?.fire {
                    FireOutlookLine(fire: fire)
                }
                HStack(spacing: 8) {
                    ForEach(store.footCard?.actions ?? [], id: \.id) { a in
                        ActionButton(action: a, store: store)
                    }
                    if let card = store.footCard, card.pageCount > 1 {
                        Button { store.nextFootCardPage() } label: {
                            Text(verbatim: "\(card.page + 1)/\(card.pageCount)  ▸").frame(minHeight: InkMetric.buttonHeight)
                        }
                        .buttonStyle(.ink(.quiet, fill: false))
                        .accessibilityIdentifier("footCardNextPage")
                    }
                    // 残骸から開く資料(段階つきの資料など。U18)
                    ForEach(store.footCard?.documents ?? [], id: \.id) { d in
                        Button { store.openPanel(d.id) } label: { Text(verbatim: d.title) }
                            .buttonStyle(.ink(.quiet, fill: false))
                            .accessibilityIdentifier("panel-\(d.id.rawValue)")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: InkMetric.buttonHeight, alignment: .leading)
            }
        }
        // 子の識別子(holdRing・footAction など)を上書きしないよう、まとめずに含む形にする
        .accessibilityElement(children: .contain)
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
            HStack(spacing: 8) {
                HoldRing(permille: action.progressPermille, pressing: pressing)
                Text(verbatim: action.label)
                    .font(InkFont.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
                .foregroundStyle(pressing ? InkColor.onAccent : InkColor.text)
                .padding(.horizontal, 14)
                .frame(minHeight: InkMetric.buttonHeight)
                .background(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .fill(pressing ? InkColor.accent : InkColor.panel))
                .overlay(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .stroke(InkColor.rule, lineWidth: InkMetric.rule))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        store.act(action, pressing: true)
                    }
                    .onEnded { _ in
                        guard pressing else { return }
                        pressing = false
                        store.act(action, pressing: false)
                    })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: action.label))
                .accessibilityValue(Text(verbatim: HoldRing.spokenValue(hold: true) ?? ""))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("holdRing")
        } else {
            Button {
                store.act(action, pressing: true)
            } label: {
                Text(verbatim: action.label)
                    .frame(minHeight: InkMetric.buttonHeight)
            }
            .buttonStyle(.ink(.secondary, fill: false))
            .accessibilityIdentifier("footAction")
        }
    }
}
