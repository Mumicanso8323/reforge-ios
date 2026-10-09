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

/// 録画の確かめ用の数え(完了の印の 4 行目に出す)。地図の画が作れなかった回数・直前の画で補った回数・世界の差し替えの回数。
@MainActor
enum ReplayStats {
    static var renderFailures = 0
    static var fallbackDraws = 0
    static var replaces = 0
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
        /// 断られた命令を再試行する長さ(秒)。
        var retryWindow: TimeInterval = 30
        /// 歩みが進まないまま、これだけ(秒)たったら場面を送る。
        var stallAdvance: TimeInterval = 4
        /// 1 つの命令にこれだけ(秒)かけても届かなければ飛ばす。
        var giveUp: TimeInterval = 120
        /// 次の命令に届くまでこれだけ(秒)待ったら、次の合わせ直しの点まで世界を進めて先へ行く(確かめ用の録画で、待ちの間延びを詰める)。
        var maxGap: TimeInterval = 60
    }

    static func run(script: ReplayScript, store: GameStore, donePath: String?, pacing: Pacing = Pacing(),
                    uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) async {
        try? await Task.sleep(for: pacing.warmup)
        var index = 0
        var lastSend = -TimeInterval.infinity
        var lastAdvance = -TimeInterval.infinity
        var entryStart = uptime()
        var seenStep: Int64 = -1
        var stepChangedAt = uptime()
        var skipped: [Int] = []
        // 区間 = 何番目の合わせ直しの点を過ぎたか(0 = 最初の点の前)。区間ごとに飛ばした本数を印に残す
        var section = 0
        var restored = 0
        var jumps = 0
        // 区画の中身の数(store.chunks)を見張る: 最小と、空だった回数(地図が黒く見える間の手がかり)
        var chunksMin = Int.max
        var chunksZero = 0
        var sceneOpen = 0   // 全面の場面(prologue/stage)が開いていた周の数
        var allUnknown = 0  // 場面が無いのに、持っている区画のマスが全部未踏(黒)だった周の数
        var skippedBySection: [Int: Int] = [:]
        var checkpoints: [Int: Data] = [:]
        for cp in script.checkpoints ?? [] where checkpoints[cp.index] == nil { checkpoints[cp.index] = cp.save }
        while index < script.commands.count, !Task.isCancelled {
            // ボットの世界へ合わせ直す点(命令だけでは、世界の小さな差が積もって途中から合わなくなる)
            if let save = checkpoints.removeValue(forKey: index) {
                await restore(save, into: store)
                restored += 1
                section = restored
            }
            let entry = script.commands[index]
            let step = await store.host.step
            let chunkCount = store.chunks.count
            chunksMin = min(chunksMin, chunkCount)
            if chunkCount == 0 { chunksZero += 1 }
            if store.prologue != nil { sceneOpen += 1 }
            else if chunkCount > 0, !store.chunks.values.contains(where: { $0.tiles.contains { $0.fog != .unknown } }) { allUnknown += 1 }
            if step != seenStep { seenStep = step; stepChangedAt = uptime() }
            let isScene = entry.command == .narrative(.advanceScene)
            let waited = uptime() - lastSend
            // 時計が保留の間は歩みが進まない。長押しなどの「間」は、台本の after(前の命令からの実時間)で待つ
            let afterOK = entry.after.map { waited >= $0 } ?? true
            if Int64(entry.step) <= step, afterOK, !isScene || waited >= pacing.sceneGap {
                var rejection = await store.perform(entry.command)
                // 命令が少し早く届いただけで断られる(前の長押しが 1 歩で終わる・場面を読んでいる最中)ので、しばらく再試行する。
                // 場面が開いていて読んでいる最中なら、人が画面をタップするのと同じく場面を送ってから。場面の送りの命令は再試行しない。
                if rejection != nil, !isScene {
                    let began = uptime()
                    while rejection != nil, uptime() - began < pacing.retryWindow, !Task.isCancelled {
                        try? await Task.sleep(for: pacing.poll)
                        if await sceneIsOpen(store), uptime() - lastAdvance >= pacing.sceneGap {
                            _ = await store.perform(.narrative(.advanceScene))
                            lastAdvance = uptime()
                        }
                        rejection = await store.perform(entry.command)
                    }
                }
                if isScene { lastAdvance = uptime() }
                // 断られ続けた命令は飛ばして先へ進む(止めない。次の合わせ直しの点で世界が戻る)。何番目かだけを残す
                if rejection != nil { skipped.append(index + 1); skippedBySection[section, default: 0] += 1 }
                lastSend = uptime()
                index += 1
                entryStart = uptime()
                continue
            }
            // 歩みが進まない(全画面の場面を読んでいる)間は、人がタップするように場面を送る
            if uptime() - stepChangedAt >= pacing.stallAdvance, uptime() - lastAdvance >= pacing.sceneGap,
               await sceneIsOpen(store) {
                _ = await store.perform(.narrative(.advanceScene))
                lastAdvance = uptime()
            }
            // 待ちが長い(再採取の間置き・夜の眠り・長押しの完了待ち)なら、次の合わせ直しの点へ進める。
            // 点で世界がボットのものに戻るので、飛ばした間の命令は要らない。点が無ければ待つ。
            if uptime() - entryStart >= pacing.maxGap, let next = checkpoints.keys.filter({ $0 > index }).min(),
               let save = checkpoints.removeValue(forKey: next) {
                await restore(save, into: store)
                restored += 1
                section = restored
                jumps += 1
                index = next
                entryStart = uptime()
                continue
            }
            // 届かない命令に居続けない
            if uptime() - entryStart >= pacing.giveUp {
                skipped.append(index + 1); skippedBySection[section, default: 0] += 1
                index += 1
                entryStart = uptime()
                continue
            }
            try? await Task.sleep(for: pacing.poll)
        }
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .seconds(pacing.tail))
        // 完了の印: 1 行目は結果、2 行目は合わせ直しの点をいくつ越えたか・待ちを詰めて飛んだ回数、3 行目は区間ごとの飛ばした本数(区間:本数)
        let head = skipped.first.map { "skipped \(skipped.count)/\(script.commands.count) first \($0)" } ?? "ok \(script.commands.count)"
        let total = script.checkpoints?.count ?? 0
        let bySection = skippedBySection.keys.sorted().map { "\($0):\(skippedBySection[$0] ?? 0)" }.joined(separator: " ")
        writeMark("\(head)\ncheckpoints \(restored)/\(total) jumps \(jumps)\nby-section \(bySection.isEmpty ? "-" : bySection)\nmap render-failures \(ReplayStats.renderFailures) fallbacks \(ReplayStats.fallbackDraws) replaces \(ReplayStats.replaces) chunks-min \(chunksMin == Int.max ? 0 : chunksMin) chunks-zero \(chunksZero) scene-open \(sceneOpen) all-unknown \(allUnknown)", to: donePath)
    }

    /// 全画面の場面・ふきだしの場面が開いているか(開いていれば、人は画面をタップして送る)。
    private static func sceneIsOpen(_ store: GameStore) async -> Bool {
        let f = await store.host.frame
        return !f.sceneLines.isEmpty || f.prologue != nil
    }

    /// 台本の合わせ直しの点の世界に入れ替える。読めなければ何もしない。
    private static func restore(_ save: Data, into store: GameStore) async {
        guard let envelope = try? SaveCodec.decode(save) else { return }
        await store.replaceWorld(envelope.world)
    }

    /// 完了の印(1 行)。
    private static func writeMark(_ line: String, to path: String?) {
        guard let path else { return }
        try? (line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
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
