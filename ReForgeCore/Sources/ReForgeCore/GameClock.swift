/// ゲーム内時間の進み方。
///
/// 「ターン制かリアルタイムか」「アプリを閉じている間も拠点が進む/飢えるか」はまだ決まっていない。
/// ゲームロジックは時間をこのプロトコル越しにしか見ないことで、方式を差し替えても他を書き換えずに済むようにする。
/// 時間の単位は「ティック」(ゲーム内の最小進行単位)。何ティック進んだかだけをロジックに渡す。
public protocol GameClock: Sendable {
    /// これまでに経過したゲーム内ティック数(単調増加)。
    var elapsedTicks: Int { get }

    /// プレイヤーの行動(ターン終了など)を通知する。進んだティック数を返す。
    mutating func playerDidAct() -> Int

    /// 実時間の経過を通知する。進んだティック数を返す。
    /// - Parameters:
    ///   - seconds: 経過した実時間(秒)。
    ///   - whileInactive: アプリを閉じて(バックグラウンドに)いた間の経過なら true。
    mutating func realTimeDidPass(seconds: Double, whileInactive: Bool) -> Int
}

/// ターン制: プレイヤーが行動したときだけ 1 ティック進む。実時間では進まない。
public struct TurnBasedClock: GameClock {
    public private(set) var elapsedTicks: Int

    public init(elapsedTicks: Int = 0) {
        self.elapsedTicks = elapsedTicks
    }

    public mutating func playerDidAct() -> Int {
        elapsedTicks += 1
        return 1
    }

    public mutating func realTimeDidPass(seconds: Double, whileInactive: Bool) -> Int {
        0
    }
}

/// リアルタイム: secondsPerTick 秒ごとに 1 ティック進む。
/// アプリを閉じていた間を進めるか(progressesWhileInactive)と、その上限(maxInactiveTicks)を選べる。
public struct RealTimeClock: GameClock {
    public let secondsPerTick: Double
    public let progressesWhileInactive: Bool
    /// 閉じていた間に進める最大ティック数。nil なら無制限。
    public let maxInactiveTicks: Int?
    public private(set) var elapsedTicks: Int = 0
    /// まだティックに満たない端数の秒。
    private var carrySeconds: Double = 0

    public init(secondsPerTick: Double, progressesWhileInactive: Bool, maxInactiveTicks: Int? = nil) {
        precondition(secondsPerTick > 0, "secondsPerTick は正の値")
        self.secondsPerTick = secondsPerTick
        self.progressesWhileInactive = progressesWhileInactive
        self.maxInactiveTicks = maxInactiveTicks
    }

    public mutating func playerDidAct() -> Int {
        0
    }

    public mutating func realTimeDidPass(seconds: Double, whileInactive: Bool) -> Int {
        guard seconds > 0, seconds.isFinite else { return 0 }
        if whileInactive {
            guard progressesWhileInactive else { return 0 }
            var ticks = Int((seconds / secondsPerTick).rounded(.down))
            if let cap = maxInactiveTicks { ticks = min(ticks, cap) }
            elapsedTicks += ticks
            return ticks
        }
        carrySeconds += seconds
        let ticks = Int((carrySeconds / secondsPerTick).rounded(.down))
        carrySeconds -= Double(ticks) * secondsPerTick
        elapsedTicks += ticks
        return ticks
    }
}
