import SwiftUI

/// 長押しの行為の左に置く輪(A-04c)。押すだけの行為には付けない。
/// 直径 22pt の細い円(縁 2pt)。押している間、縁が進みに合わせて 12 時の位置から時計回りに満ちる。
/// 満ちる動きは補間のアニメにしない(`Frame` の値に合わせて刻む)。「動きを減らす」でも満ちる(進み具合の表示)。
struct HoldRing: View {
    static let diameter: CGFloat = 22
    static let lineWidth: CGFloat = 2

    let permille: Int?
    let pressing: Bool

    var body: some View {
        ZStack {
            Circle().stroke(InkColor.rule, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: Self.trim(permille: permille, pressing: pressing))
                .stroke(InkColor.accent, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .animation(nil, value: permille)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityHidden(true)
    }

    /// 進み(0...1000)→ 描く弧の長さ(0...1)。押していなければ 0、押していて値が無ければ 0(押した瞬間は画面が 0 として描く)。
    static func trim(permille: Int?, pressing: Bool) -> CGFloat {
        guard pressing, let permille else { return 0 }
        return CGFloat(min(max(permille, 0), 1000)) / 1000
    }

    /// 読み上げの値の文。長押しの行為だけ「長押し」。押すだけなら nil(この版は日本語だけ)。
    static func spokenValue(hold: Bool) -> String? {
        hold ? "長押し" : nil
    }
}
