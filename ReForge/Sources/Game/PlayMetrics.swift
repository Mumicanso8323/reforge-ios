import Foundation
import QuartzCore
import UIKit

/// 操作性の印(PT-B4。latency・hitch)の数え方。時刻は呼び手が渡す(試験は差し替えた時刻で数える)。
/// 描画の時間は測るだけで、変えない。
struct PlayMetrics {
    static let latencyPerMinute = 6
    static let hitchThreshold: TimeInterval = 0.1

    struct Emitted: Equatable { var kind: String; var fields: [String: String] }

    private var pendingTouch: TimeInterval?
    private var lastFrame: TimeInterval?
    private var latencyWindowStart: TimeInterval?
    private var latencyInWindow = 0
    private var hitchWindowStart: TimeInterval?
    private var hitchCount = 0
    private var hitchLongest = 0

    /// 触れた(命令を出した)時刻。次に描かれた時刻との差が latency。
    mutating func touch(at t: TimeInterval) { pendingTouch = t }

    /// 前に出ている間、描画のたびに呼ぶ。
    mutating func frame(at t: TimeInterval) -> [Emitted] {
        var out: [Emitted] = []
        if let touched = pendingTouch {
            pendingTouch = nil
            if latencyWindowStart == nil || t - (latencyWindowStart ?? t) >= 60 { latencyWindowStart = t; latencyInWindow = 0 }
            if latencyInWindow < Self.latencyPerMinute {
                latencyInWindow += 1
                out.append(Emitted(kind: "latency", fields: ["ms": "\(Int(((t - touched) * 1000).rounded()))"]))
            }
        }
        if hitchWindowStart == nil { hitchWindowStart = t }
        if let last = lastFrame, t - last > Self.hitchThreshold {
            hitchCount += 1
            hitchLongest = max(hitchLongest, Int(((t - last) * 1000).rounded()))
        }
        lastFrame = t
        if let start = hitchWindowStart, t - start >= 60 {
            out.append(Emitted(kind: "hitch", fields: ["count": "\(hitchCount)", "longestMs": "\(hitchLongest)"]))
            hitchWindowStart = t
            hitchCount = 0
            hitchLongest = 0
        }
        return out
    }

    /// 後ろに下がった。戻ったときの空白を引っかかりに数えない。
    mutating func suspend() {
        lastFrame = nil
        pendingTouch = nil
        hitchWindowStart = nil
        hitchCount = 0
        hitchLongest = 0
    }
}

/// 描画の合図(CADisplayLink)を受けて PlayMetrics に渡す。前に出ている間だけ回す。
@MainActor
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    var onFrame: ((TimeInterval) -> Void)?

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) { onFrame?(l.timestamp) }
}

/// 端末の設定と状態(build・session・power の行に足す)。名前や識別子は含めない。
enum DeviceSnapshot {
    @MainActor
    static func settings() -> [String: String] {
        [
            "textSize": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "reduceMotion": "\(UIAccessibility.isReduceMotionEnabled)",
            "boldText": "\(UIAccessibility.isBoldTextEnabled)",
            "highContrast": "\(UIAccessibility.isDarkerSystemColorsEnabled)",
            "differentiateWithoutColor": "\(UIAccessibility.shouldDifferentiateWithoutColor)",
        ]
    }

    @MainActor
    static func orientation() -> String {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.interfaceOrientation.isLandscape == true ? "landscape" : "portrait"
    }

    @MainActor
    static func power() -> [String: String] {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return [
            "battery": level < 0 ? "unknown" : "\(Int((level * 100).rounded()))",
            "thermal": "\(ProcessInfo.processInfo.thermalState.rawValue)",
        ]
    }
}
