import SwiftUI
import UIKit
import ReForgeEngine

/// 触れた場所を中立にする操作棒。台の外まで追い、離したら止める。
struct StickControl: View {
    let store: GameStore
    let layout: HUDLayout
    @State private var neutral: CGPoint?
    @State private var offset = CGSize.zero
    @State private var sent: StickDirection?
    @State private var blocked = false

    var body: some View {
        let radius = layout.stickDiameter / 2
        Circle()
            .fill(InkColor.ground.opacity(0.72))
            .overlay(Circle().stroke(blocked ? InkColor.alert : InkColor.rule, lineWidth: 1))
            .overlay(Circle().stroke(InkColor.text.opacity(neutral == nil ? 0.25 : 0.7), lineWidth: 2).padding(3))
            .overlay {
                Circle()
                    .fill(InkColor.panel)
                    .shadow(color: .black.opacity(0.65), radius: 3, y: 2)
                    .frame(width: layout.stickKnobDiameter, height: layout.stickKnobDiameter)
                    .offset(StickMath.knobOffset(offset))
            }
            .frame(width: layout.stickDiameter, height: layout.stickDiameter)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if neutral == nil { neutral = value.startLocation }
                    let n = neutral ?? value.startLocation
                    offset = CGSize(width: value.location.x - n.x, height: value.location.y - n.y)
                    let next = StickMath.direction(offset: offset, previous: sent,
                                                   directions: MapTouchSettings.directions(),
                                                   neutralRadius: MapTouchSettings.neutralRadius())
                    guard next != sent else { return }
                    if sent == nil, next != nil { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    sent = next
                    store.steer(next, reason: next == nil ? "neutral" : "direction")
                }
                .onEnded { _ in
                    neutral = nil
                    offset = .zero
                    guard sent != nil else { return }
                    sent = nil
                    store.steer(nil, reason: "released")
                })
            .accessibilityLabel(Text("移動の操作棒"))
            .accessibilityIdentifier("stickControl")
            .onChange(of: store.lastSteerBlocked) { _, value in
                guard value else { return }
                blocked = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { blocked = false }
            }
    }
}
