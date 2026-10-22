import Foundation

struct PlayLogEvent: Codable {
    var t: Date
    var kind: String
    var day: Int
    var minute: Int
    var fields: [String: String]
}

/// 端末内だけに追記する軽い操作記録。ゲーム状態と保存には入れない。
/// 開発用の組み(DEBUG・dev の ipa)だけが書く。店に出す Release(TestFlight 含む)は何も書かない。
/// 書く組みでも、全部で 2 MB を超えたら古い日のファイルから消す。
final class PlayLog {
    static let maxTotalBytes = 2 * 1024 * 1024
    /// 書く組みか(DEBUG と dev の ipa だけ)。
    static let isEnabled: Bool = {
        #if DEBUG || REFORGE_DEV
        return true
        #else
        return false
        #endif
    }()
    /// 記録を取るかの入切(設定。既定は入)。
    static let recordingKey = "reforge.playlog.recording"
    let directory: URL
    private let queue = DispatchQueue(label: "com.yusukedoi.reforge.playlog")
    private let encoder = JSONEncoder()
    private let defaults: UserDefaults
    private let maxBytes: Int

    /// 切のとき、何も書かない。
    var isRecording: Bool { defaults.object(forKey: Self.recordingKey) as? Bool ?? true }

    /// 試験は directory と defaults を差し替える(差し替えたときは、書く組みかの判定を見ない)。
    init?(fileManager: FileManager = .default, directory override: URL? = nil, defaults: UserDefaults = .standard,
          maxBytes: Int = PlayLog.maxTotalBytes) {
        self.defaults = defaults
        self.maxBytes = maxBytes
        if let override {
            directory = override
        } else {
            guard Self.isEnabled, let base = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true) else { return nil }
            directory = base.appendingPathComponent("playlog", isDirectory: true)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        let dir = directory
        let cap = maxBytes
        queue.async { Self.prune(dir, maxBytes: cap) }
    }

    /// 全部の大きさが上限を超えていたら、古い日(ファイル名の順)から消す。いま書いている新しい日は残す。
    static func prune(_ directory: URL, maxBytes: Int = maxTotalBytes) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let files = names.filter { $0.hasSuffix(".jsonl") }.sorted()
        var sizes: [(name: String, bytes: Int)] = files.map { n in
            let a = try? fm.attributesOfItem(atPath: directory.appendingPathComponent(n).path)
            return (n, (a?[.size] as? Int) ?? 0)
        }
        var total = sizes.reduce(0) { $0 + $1.bytes }
        while total > maxBytes, sizes.count > 1 {
            let oldest = sizes.removeFirst()
            try? fm.removeItem(at: directory.appendingPathComponent(oldest.name))
            total -= oldest.bytes
        }
    }

    func append(_ event: PlayLogEvent) {
        guard isRecording else { return }
        queue.async { [directory, encoder, maxBytes] in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let url = directory.appendingPathComponent(formatter.string(from: event.t) + ".jsonl")
            guard let data = try? encoder.encode(event), var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                // 新しい日のファイルを作る時に、全体の上限を見る
                Self.prune(directory, maxBytes: maxBytes)
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
    }

    /// 書き込みが全部終わるのを待つ(書き出し・試験用)。
    func flush() { queue.sync {} }

    /// 日付順に連結した JSON Lines を 1 つのファイルにして返す(共有シートへ渡す)。ファイルは端末の外へは自動では出ない。
    func export() throws -> URL {
        try queue.sync {
            let fm = FileManager.default
            let names = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".jsonl") }.sorted()
            var all = Data()
            for n in names { all.append((try? Data(contentsOf: directory.appendingPathComponent(n))) ?? Data()) }
            let out = fm.temporaryDirectory.appendingPathComponent("reforge-playlog.jsonl")
            try all.write(to: out, options: .atomic)
            return out
        }
    }

    /// 記録を全部消す(設定の確認の後)。
    func clear() {
        queue.sync {
            let fm = FileManager.default
            // 節目の印(marks.json)は残す。消すと同じ節目がもう一度出る
            for n in ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []) where n.hasSuffix(".jsonl") {
                try? fm.removeItem(at: directory.appendingPathComponent(n))
            }
        }
    }
}
