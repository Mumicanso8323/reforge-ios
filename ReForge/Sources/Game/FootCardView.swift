import SwiftUI
import ReForgeEngine

/// 足元カード: 注目しているマス(タップ・長押ししたマス、無ければノアの足元)の名前と、できること 1〜2 個(FootCard.maxActions。名前は 2 行まで折り返す)。
/// 断られた理由はここに 1 行出す(ダイアログは出さない)。高さは 84pt を下限に内容に合わせて伸びる(日本語では 84pt のまま)。
struct FootCardView: View {
    let store: GameStore

    var body: some View {
        InkBand(edge: .top, minHeight: 84) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    spokenText(store.footCard?.title ?? " ")
                        .font(InkFont.body)
                        .bold()
                        .pulseGlow(store.pulsePlayer.doneTick)
                        // 名前は 2 行まで(日本語は 1 行のまま。高さは minHeight 84 から内容に合わせて伸びる)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let banner = store.pulsePlayer.banner {
                        spokenText(banner).font(InkFont.caption).foregroundStyle(InkColor.accent)
                    }
                    // 断りの文・「近くにもう無い」の類は出さない(説明で補わない)。押した事実への応えはボタンの揺れと触覚
                }
                // できない理由の一文(card.hint)は出さない: 押せない物はボタンを置かず、説明でも補わない(INV-F1)
                // 焚き火の火の見込み(PT-B1。焚き火のカードだけ)
                if let fire = store.footCard?.fire {
                    FireOutlookLine(fire: fire)
                }
                HStack(spacing: 8) {
                    ForEach(store.footCard?.actions ?? [], id: \.key) { a in
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
                        Button { store.openPanel(d.id) } label: { spokenText(d.title) }
                            .buttonStyle(.ink(.quiet, fill: false))
                            .accessibilityIdentifier("panel-\(d.id.rawValue)")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: InkMetric.buttonHeight, alignment: .leading)
            }
        }
        .pulseBulge(store.pulsePlayer.placedTick)
        .overlay(alignment: .topTrailing) { FloatingPulseText(player: store.pulsePlayer) }
        // 子の識別子(holdRing・footAction など)を上書きしないよう、まとめずに含む形にする
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("footCard")
    }
}

/// 手作業の 1 単位の「+1 〈物〉」。足元カードの上に 0.5 秒浮かぶ(同時に 5 個まで。「動きを減らす」では作られない)。
struct FloatingPulseText: View {
    let player: PulsePlayer

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(player.floaters) { floater in
                spokenText(floater.text)
                    .font(InkFont.body)
                    .foregroundStyle(InkColor.accent)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: player.floaters)
        .offset(y: -26)
        .padding(.trailing, 12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                spokenText(action.label)
                    .font(InkFont.body)
                    // 名前は省略せず、2 行まで折り返す
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
                .foregroundStyle(pressing ? InkColor.onAccent : InkColor.text)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: InkMetric.buttonHeight)
                .background(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .fill(pressing ? InkColor.accent : InkColor.panel))
                .overlay(RoundedRectangle(cornerRadius: InkMetric.corner)
                    .stroke(InkColor.rule, lineWidth: InkMetric.rule))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        store.pulsePlayer.press()
                        store.act(action, pressing: true)
                    }
                    .onEnded { _ in
                        guard pressing else { return }
                        pressing = false
                        store.act(action, pressing: false)
                    })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText(action.label))
                .accessibilityValue(Text(verbatim: HoldRing.spokenValue(hold: true) ?? ""))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("holdRing")
                .pulseGlow(store.pulsePlayer.unitTick)
                .refusalShake(store.refusals)
        } else {
            Button {
                store.pulsePlayer.press()
                store.act(action, pressing: true)
            } label: {
                spokenText(action.label)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: InkMetric.buttonHeight)
            }
            .buttonStyle(.ink(.secondary, fill: true))
            .accessibilityIdentifier("footAction")
            .pulseGlow(store.pulsePlayer.unitTick)
            .refusalShake(store.refusals)
        }
    }
}

extension View {
    /// 押したが受け付けられなかった時(回数が増えた時)の、短い横の揺れ。文は出さない。「動きを減らす」でも触覚は鳴る。
    func refusalShake(_ count: Int) -> some View {
        keyframeAnimator(initialValue: 0.0, trigger: count) { view, dx in
            view.offset(x: dx)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0, duration: 0.01)
                LinearKeyframe(-5, duration: 0.03)
                LinearKeyframe(5, duration: 0.04)
                LinearKeyframe(-3, duration: 0.03)
                LinearKeyframe(0, duration: 0.03)
            }
        }
    }
}

/// 1 度ふくらむ(置いた所)。「動きを減らす」では何もしない。
private struct PulseBulge: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(1.04, duration: 0.08)
                    LinearKeyframe(1.0, duration: 0.14)
                }
            }
        }
    }
}

/// 1 度明るく光って戻る(色の変化だけ。「動きを減らす」でも同じ)。
private struct PulseGlow: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, glow in
            view.overlay { InkColor.accent.opacity(glow).allowsHitTesting(false) }
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.35, duration: 0.05)
                LinearKeyframe(0, duration: 0.35)
            }
        }
    }
}

extension View {
    func pulseBulge(_ trigger: Int) -> some View { modifier(PulseBulge(trigger: trigger)) }
    func pulseGlow(_ trigger: Int) -> some View { modifier(PulseGlow(trigger: trigger)) }
}
