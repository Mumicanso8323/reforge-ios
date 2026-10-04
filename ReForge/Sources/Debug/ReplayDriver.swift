#if DEBUG
import SwiftUI
import ReForgeEngine

/// 10 分の通しの台本の流し込み(A-07)。起動引数 `-ReForgeReplay <台本のパス>`(と `-ReForgeReplayDone <完了の印のパス>`)のときだけ働く。
/// 台本の seed で、保存を読まず(書き先は使い捨ての場所)新しい世界を開き、本物の GameStore を実時間のループで動かす。
/// 世界の歩みが台本の step に届くたびに、その命令を送る。通常の起動・撮る起動(-ReForgeScreenshot)には何も起きない。
enum ReplayMode {
    static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// 台本を読む。パスが無い・ファイルが無い・壊れている時は nil(何もしない)。
    static func load(path: String?) -> ReplayScript? {
        guard let path else { return nil }
        return try? ReplayScript.read(from: URL(fileURLWithPath: path))
    }

    static let script: ReplayScript? = load(path: argument("-ReForgeReplay"))
    static let donePath: String? = argument("-ReForgeReplayDone")

    static var isActive: Bool { script != nil }

    /// 流し込みの起動なら、台本の seed の新しい世界を開いた AppModel を返す(保存は使い捨ての場所)。
    @MainActor
    static func makeModel(script: ReplayScript) -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reforge-replay-\(UUID().uuidString)", isDirectory: true)
        let model = AppModel(saves: FileSaveStorage(directory: dir))
        model.startReplayGame(seed: UInt64(truncatingIfNeeded: script.seed))
        return model
    }
}

/// 台本を GameStore へ流し込む。実時間の待ちと時刻は差し替えられる(テスト用)。
@MainActor
enum ReplayDriver {
    struct Pacing {
        /// 歩みを見に行く間隔。
        var poll: Duration = .milliseconds(50)
        /// 始める前の待ち(GameStore の読み込みが済むまで)。
        var warmup: Duration = .milliseconds(500)
        /// 場面の送り(.narrative(.advanceScene))どうしの最短の間(人が読む間。秒)。
        var sceneGap: TimeInterval = 1.5
        /// 最後の命令から完了の印を書くまで(秒)。
        var tail: TimeInterval = 5
    }

    static func run(script: ReplayScript, store: GameStore, donePath: String?, pacing: Pacing = Pacing(),
                    uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) async {
        try? await Task.sleep(for: pacing.warmup)
        var index = 0
        var lastSend = -TimeInterval.infinity
        while index < script.commands.count, !Task.isCancelled {
            let entry = script.commands[index]
            let step = await store.host.step
            let isScene = entry.command == .narrative(.advanceScene)
            let waited = uptime() - lastSend
            if Int64(entry.step) <= step, !isScene || waited >= pacing.sceneGap {
                _ = await store.perform(entry.command)
                lastSend = uptime()
                index += 1
                continue
            }
            try? await Task.sleep(for: pacing.poll)
        }
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .seconds(pacing.tail))
        if let donePath {
            try? "done\n".write(toFile: donePath, atomically: true, encoding: .utf8)
        }
    }
}

extension View {
    /// 流し込みの起動のときだけ、画面の操作を受けず(録画に操作を混ぜない)、台本を流し込む。
    func replaySupport(app: AppModel) -> some View {
        allowsHitTesting(!ReplayMode.isActive)
            .task {
                guard let script = ReplayMode.script, let store = app.game else { return }
                await ReplayDriver.run(script: script, store: store, donePath: ReplayMode.donePath)
            }
    }
}
#endif
