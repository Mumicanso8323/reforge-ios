import SwiftUI

/// 地図画面の操作部品を寄せる場所。横向きの値は後の表示単位で足せるように別にする。
struct HUDLayout: Equatable {
    enum Hand: String { case left, right }

    var hand: Hand
    var stickDiameter: CGFloat = 132
    var stickKnobDiameter: CGFloat = 56
    var stickInset: CGFloat = 16
    var controlSize: CGFloat = 44

    static func portrait(hand: Hand = .right) -> HUDLayout { HUDLayout(hand: hand) }

    func mapControlAlignment(_ forHand: Hand? = nil) -> Alignment {
        (forHand ?? hand) == .right ? .bottomTrailing : .bottomLeading
    }
}
