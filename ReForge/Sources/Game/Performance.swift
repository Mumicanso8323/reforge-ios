import Foundation
import os

/// 遅い処理を記録へ渡す口。後の記録機能はこの実装を差し替えて受け取れる。
protocol PerfSink {
    func recordStep(milliseconds: Int, steps: Int, rebuilt: Bool)
    func recordApply(milliseconds: Int)
}

struct LoggerPerfSink: PerfSink {
    private let logger = Logger(subsystem: "reforge", category: "perf")

    func recordStep(milliseconds: Int, steps: Int, rebuilt: Bool) {
        let rebuiltValue = rebuilt ? "yes" : "no"
        logger.info("kind: step ms: \(milliseconds, privacy: .public) steps: \(steps, privacy: .public) rebuilt: \(rebuiltValue, privacy: .public)")
    }

    func recordApply(milliseconds: Int) {
        logger.info("kind: apply ms: \(milliseconds, privacy: .public)")
    }
}

/// 開発中に設定へ出す、直近の遅い歩み。
struct SlowStep: Equatable {
    var milliseconds: Int
    var steps: Int
    var rebuilt: Bool
}
