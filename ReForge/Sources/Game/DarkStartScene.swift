import SwiftUI
import ReForgeEngine

struct DarkStartScene: View {
    let action: FootCard.Action
    let store: GameStore

    var body: some View {
        GeometryReader { geo in
            // 序と同じ地の色(PT-B6 の PrologueScene)。序の覆いが消えると、そのままこの場面になる
            InkColor.prologueGround
                .overlay(alignment: .bottom) {
                    VStack(spacing: 10) {
                        if let notice = store.notice {
                            Text(verbatim: notice)
                                .font(InkFont.small)
                                .foregroundStyle(InkColor.notice)
                                .lineLimit(1)
                        }
                        DarkStartActionButton(action: action, store: store)
                    }
                    .frame(width: 240)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 72)
                }
        }
        .ignoresSafeArea()
        // 入れ物の識別子は、中の行為のボタン(darkStartAct)の識別子を上書きしないよう、入れ物を 1 つの要素にしてから付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("darkStartScene")
    }
}

private struct DarkStartActionButton: View {
    let action: FootCard.Action
    let store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressing = false
    @State private var borderOpacity = 1.0

    var body: some View {
        VStack(spacing: 6) {
            button
                .frame(width: 240, height: 56)
                .background(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .fill(pressing ? InkColor.accent : InkColor.panel))
                .overlay(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .stroke(InkColor.accent.opacity(reduceMotion ? 1 : borderOpacity), lineWidth: InkMetric.rule))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("darkStartAct")
            if let progress = action.progressPermille {
                GeometryReader { geo in
                    Rectangle()
                        .fill(InkColor.accent)
                        .frame(width: geo.size.width * CGFloat(progress) / 1000)
                }
                .frame(height: 3)
                .background(InkColor.rule)
            }
        }
        .onAppear { pulse() }
        .onChange(of: reduceMotion) { _, _ in pulse() }
    }

    @ViewBuilder private var button: some View {
        if action.hold {
            Text(verbatim: action.label)
                .font(InkFont.body)
                .foregroundStyle(pressing ? InkColor.onAccent : InkColor.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 3600, maximumDistance: 40, perform: {}, onPressingChanged: { value in
                    pressing = value
                    store.act(action, pressing: value)
                })
                .accessibilityAddTraits(.isButton)
        } else {
            Button { store.act(action, pressing: true) } label: {
                Text(verbatim: action.label)
                    .font(InkFont.body)
                    .foregroundStyle(InkColor.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private func pulse() {
        borderOpacity = 1
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            borderOpacity = 0.4
        }
    }
}
