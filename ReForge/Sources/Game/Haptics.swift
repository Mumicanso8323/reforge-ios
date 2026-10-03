import Foundation
import UIKit
import ReForgeEngine

/// 振動を鳴らす出来事(A-01 §4)。5 つだけ。音は足さない。
enum HapticCue: Equatable, CaseIterable {
    /// 火が点いた(火床の段が「消えている」から変わった)。
    case fireLit
    /// 採取で物を得た(行為の終わりに物が入った)。
    case gathered
    /// 火床にくべた。
    case hearthFed
    /// 置いた物・場所の部品の状態が変わった(setPart など)。
    case partOpened
    /// 建った(建造が完了した)。
    case built
}

/// 本体の出来事(DomainEvent)から、鳴らす合図を決める。画面の推測では鳴らさない。
/// 火の「点いた」は段の変わり目から決めるので、火床ごとの前の段を覚える(保存には入れない)。
struct HapticJudge {
    private var levels: [EntityID: HearthLevel] = [:]

    /// 1 歩み分の出来事から合図を返す。同じ合図は 1 回だけ(順は CaseIterable の並び)。
    mutating func cues(for events: [DomainEvent]) -> [HapticCue] {
        var found = Set<Int>()
        var interacted = false
        var gained = false
        func mark(_ cue: HapticCue) { found.insert(HapticCue.allCases.firstIndex(of: cue)!) }
        for event in events {
            switch event {
            case .hearthLevelChanged(let placement, let level):
                let before = levels[placement] ?? .out
                levels[placement] = level
                if before == .out, level != .out { mark(.fireLit) }
            case .hearthStoked: mark(.hearthFed)
            case .partChanged: mark(.partOpened)
            case .built: mark(.built)
            case .interacted: interacted = true
            case .itemGained: gained = true
            default: break
            }
        }
        // 採取の行為の終わり(行為が終わり、同じ歩みで物が入った)
        if interacted, gained { mark(.gathered) }
        return found.sorted().map { HapticCue.allCases[$0] }
    }
}

/// 暗い場面の長押しの間の、少しずつ強まる軽い振動の出し方(押し始めは弱く、終わりに近いほど強く。間隔は 0.25 秒)。
struct HapticRamp {
    static let interval: TimeInterval = 0.25
    private var last: TimeInterval?

    /// 進み(0〜1000)と実時刻から、いま鳴らす強さ(0.2〜1.0)を返す。鳴らさないときは nil。
    mutating func intensity(permille: Int?, at time: TimeInterval) -> Double? {
        guard let permille else {
            last = nil
            return nil
        }
        if let last, time - last < Self.interval { return nil }
        last = time
        return 0.2 + 0.8 * Double(min(max(permille, 0), 1000)) / 1000
    }
}

/// 振動の口。実機は SystemHaptics、試験は数えるだけの物に差し替える。
@MainActor
protocol HapticFiring: AnyObject {
    func fire(_ cue: HapticCue)
    /// 暗い場面の長押しの進みに合わせた軽い振動。intensity は 0〜1。
    func ramp(intensity: Double)
}

/// 振動の出し方を 1 か所にまとめる(UIImpactFeedbackGenerator と UINotificationFeedbackGenerator)。
/// 「動きを減らす」の設定・シミュレータでは何もしない。
@MainActor
final class SystemHaptics: HapticFiring {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    private var enabled: Bool {
#if targetEnvironment(simulator)
        false
#else
        !UIAccessibility.isReduceMotionEnabled
#endif
    }

    func fire(_ cue: HapticCue) {
        guard enabled else { return }
        switch cue {
        case .fireLit: medium.impactOccurred()
        case .gathered: light.impactOccurred()
        case .hearthFed: light.impactOccurred()
        case .partOpened: medium.impactOccurred()
        case .built: notification.notificationOccurred(.success)
        }
    }

    func ramp(intensity: Double) {
        guard enabled else { return }
        light.impactOccurred(intensity: CGFloat(intensity))
    }
}
