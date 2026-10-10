import Foundation
import ReForgeEngine

/// PT-B2 再開の 1 行と、考える画面の時計(開発の設定だけ)。
/// 前回の操作の実時刻は保存の外(UserDefaults)に持つ。WorldState にも保存にも入れない。
extension GameStore {
    /// 前回の操作からこれだけ(実時間の分)たって戻ったら、再開の 1 行を出す。
    nonisolated static let resumeAfterMinutes = 10
    nonisolated static let lastOperationKey = "lastOperationAt"
    /// 開発の設定「設計とノートを開いている間、時計を止める」(既定は切)。
    nonisolated static let devHoldClockKey = "devHoldClockOnBench"

    /// 開発の設定を出せるビルドか(DEBUG だけ。配る dev の ipa は Release の REFORGE_DEV なので false。A-01)。
    static var devSettingsAvailable: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    /// 設計かノートを開いている間、アプリが本体の時計を呼ばないか。設定が切(既定)なら常に false で、今と同じに動く。
    var benchHoldsClock: Bool {
        Self.devSettingsAvailable && benchOpen && defaults.bool(forKey: Self.devHoldClockKey)
    }

    /// 命令を出した。再開の 1 行を消し、操作の実時刻を覚える。
    func noteOperation() {
        if resumeBanner != nil { resumeBanner = nil }
        defaults.set(now().timeIntervalSince1970, forKey: Self.lastOperationKey)
    }

    /// 前に出たとき(と、保存から読んで始めたとき)に呼ぶ。前回の操作から 10 分以上たっていれば帯に出す。
    func evaluateResume() async {
#if DEBUG
        // 撮る起動は、端末に残った前回の操作の時刻(別の起動・別の試験の物)で写真が変わらないよう、再開の 1 行を出さない
        if ScreenshotMode.screen != nil { return }
#endif
        guard resumeBanner == nil, !runEnded,
              let at = defaults.object(forKey: Self.lastOperationKey) as? Double else { return }
        guard now().timeIntervalSince1970 - at >= Double(Self.resumeAfterMinutes * 60) else { return }
        let line = await host.resumeLine()
        // 待っている間に命令が来た(操作の時刻が替わった)なら出さない
        guard (defaults.object(forKey: Self.lastOperationKey) as? Double) == at, resumeBanner == nil, !runEnded else { return }
        guard line.last != nil || line.next != nil else { return }
        resumeBanner = line
    }

    /// 新しい遊びを始める・記録を消すとき、前の遊びの操作の時刻を忘れる。
    static func forgetLastOperation(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastOperationKey)
    }
}
