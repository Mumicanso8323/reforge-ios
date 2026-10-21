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
                        DarkStartActionButton(action: action, store: store)
                    }
                    .frame(minWidth: 240)
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
                // 幅 240pt・高さ 56pt は最小(日本語はこの寸法のまま)。文が長ければ 343pt まで広がる
                .frame(minWidth: 240, maxWidth: 343)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .fill(pressing ? InkColor.accent : InkColor.panel))
                .overlay(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .stroke(InkColor.accent.opacity(reduceMotion ? 1 : borderOpacity), lineWidth: InkMetric.rule))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenText(action.label))
                .accessibilityValue(Text(verbatim: HoldRing.spokenValue(hold: action.hold) ?? ""))
                .accessibilityAddTraits(.isButton)
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
        // 進みの線はボタンの幅に揃える(線の GeometryReader が画面の幅まで広がらないよう、幅は中身(ボタン)で決める)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear { pulse() }
        // 押している間、進みに合わせて軽い振動を少しずつ強める(離したら止める)
        .onChange(of: action.progressPermille) { _, new in
            store.rampHaptic(permille: pressing ? new : nil)
        }
        .onChange(of: pressing) { _, now in
            if !now { store.rampHaptic(permille: nil) }
        }
        .onChange(of: reduceMotion) { _, _ in pulse() }
    }

    @ViewBuilder private var button: some View {
        if action.hold {
            HStack(spacing: 8) {
                HoldRing(permille: action.progressPermille, pressing: pressing)
                spokenText(action.label)
                    .font(InkFont.body)
                    .lineLimit(1)
                    .minimumScaleFactor(InkMetric.minimumScale)
            }
                .foregroundStyle(pressing ? InkColor.onAccent : InkColor.text)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 3600, maximumDistance: 40, perform: {}, onPressingChanged: { value in
                    pressing = value
                    store.act(action, pressing: value)
                })
                // 輪と名前を 1 つの押せる要素にする(輪だけが小さな別の要素として残らない)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText(action.label))
                .accessibilityAddTraits(.isButton)
        } else {
            Button { store.act(action, pressing: true) } label: {
                spokenText(action.label)
                    .font(InkFont.body)
                    .lineLimit(1)
                    .minimumScaleFactor(InkMetric.minimumScale)
                    .foregroundStyle(InkColor.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
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
