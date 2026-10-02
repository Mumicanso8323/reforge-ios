import Foundation

struct PlayLogEvent: Codable {
    var t: Date
    var kind: String
    var day: Int
    var minute: Int
    var fields: [String: String]
}

/// 端末内だけに追記する軽い操作記録。ゲーム状態と保存には入れない。
final class PlayLog {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.yusukedoi.reforge.playlog")
    private let encoder = JSONEncoder()

    init?(fileManager: FileManager = .default) {
        guard let base = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true) else { return nil }
        directory = base.appendingPathComponent("playlog", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
    }

    func append(_ event: PlayLogEvent) {
        queue.async { [directory, encoder] in
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
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
    }
}
