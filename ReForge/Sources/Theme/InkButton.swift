import SwiftUI

/// ボタンの重さ。画面に primary は 1 つまで。
enum InkButtonKind {
    /// 主の行為(錆の地)。
    case primary
    /// 並んだ選択肢(枠だけ)。ゲームオーバーの 4 択のように同じ重さで並べるときもこれ。
    case secondary
    /// 文字だけ(閉じる・戻る)。
    case quiet
}

/// 標準の .bordered / .borderedProminent の代わり。
/// 使い方: `Button { … } label: { Text("寝る") }.buttonStyle(.ink(.primary))`
struct InkButtonStyle: ButtonStyle {
    var kind: InkButtonKind = .secondary
    /// 横幅いっぱいに広げる(一覧・札の中のボタン)。
    var fill: Bool = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .inkFitCheck(id: "InkButton.label")
            .font(InkFont.body)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: kind == .quiet ? 36 : InkMetric.buttonHeight)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: InkMetric.corner)
                    .fill(background(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: InkMetric.corner)
                    .stroke(kind == .secondary ? InkColor.rule : .clear, lineWidth: InkMetric.rule)
            )
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        guard isEnabled else { return InkColor.textFaint }
        switch kind {
        case .primary: return InkColor.onAccent
        case .secondary: return InkColor.text
        case .quiet: return InkColor.textDim
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary:
            return isEnabled ? InkColor.accent.opacity(pressed ? 0.75 : 1) : InkColor.raised
        case .secondary:
            return pressed ? InkColor.raised : InkColor.panel
        case .quiet:
            return pressed ? InkColor.raised : .clear
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static func ink(_ kind: InkButtonKind = .secondary, fill: Bool = true) -> InkButtonStyle {
        InkButtonStyle(kind: kind, fill: fill)
    }
}

/// 確かめのダイアログの代わり(オーナーの決め: 確認のダイアログは出さない)。
/// 押し続けると左から錆の帯が満ち、満ちきったときだけ action が走る。途中で離すと戻る。
/// 取り返しのつかない行為(記録を消す・はじめから)にだけ使う。説明は hint に 1 行で書く。
/// 使い方: `InkHoldButton(label: Text("記録を消す"), hint: Text("長押しで消す")) { app.deleteSave() }`
struct InkHoldButton: View {
    let label: Text
    var hint: Text? = nil
    /// hint を画面にも出すか。false なら読み上げ(accessibilityHint)だけ。最初の画面のように、画面の文を減らしたい所で使う。
    var showsHint: Bool = true
    /// 満ちるまでの秒数。
    var duration: Double = 1.2
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var pressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            label
                .inkFitCheck(id: "InkHoldButton.label")
                .font(InkFont.body)
                .lineLimit(1)
                .foregroundStyle(InkColor.alert)
                .frame(maxWidth: .infinity, minHeight: InkMetric.buttonHeight)
                .background(
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            InkColor.panel
                            InkColor.alert.opacity(0.28)
                                .frame(width: g.size.width * progress)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: InkMetric.corner))
                .overlay(
                    RoundedRectangle(cornerRadius: InkMetric.corner)
                        .stroke(InkColor.alert.opacity(0.6), lineWidth: InkMetric.rule)
                )
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: duration, maximumDistance: 40, perform: {
                    progress = 0
                    action()
                }, onPressingChanged: { p in
                    pressing = p
                    if p {
                        withAnimation(.linear(duration: duration)) { progress = 1 }
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                    }
                })
                // accessibilityAction は付けない。付けると VoiceOver の二重タップが長押しの保護を通らずに action を走らせる。
                // VoiceOver の「二回タップして長押し」は上の長押しにそのまま届く
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(hint ?? Text(verbatim: ""))
            if let hint, showsHint {
                hint
                    .font(InkFont.caption)
                    .foregroundStyle(InkColor.textDim)
            }
        }
    }
}
