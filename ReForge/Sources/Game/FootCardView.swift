import SwiftUI
import ReForgeEngine

/// 足元カード: 注目しているマス(タップ・長押ししたマス、無ければノアの足元)の名前と、できること 1〜3 個。
/// 断られた理由はここに 1 行出す(ダイアログは出さない)。高さは固定して、地図が上下に揺れないようにする。
struct FootCardView: View {
    let store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: store.footCard?.title ?? " ")
                    .bold()
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let n = store.notice {
                    Text(verbatim: n)
                        .foregroundStyle(Color(red: 1, green: 0.65, blue: 0.3))
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
        .font(.custom(FontBook.mapFont, size: 15))
        .foregroundStyle(Color(white: 0.92))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(Color(white: 0.07))
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
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(pressing ? Color(red: 0.55, green: 0.45, blue: 0.2) : Color(white: 0.18)))
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
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18)))
            }
            .buttonStyle(.plain)
        }
    }
}
