import Foundation
import os
import ReForgeCore

/// 端末内の保存(REQ-12)。Application Support/reforge/ に 2 つのファイルを置く。
/// - slot1.json: いまの状態。行動のたびに書く(アプリを開き直したときの「つづきから」)。
/// - savepoint.json: セーブ地点。新規開始・毎朝(決まった地点の自動セーブ)・手動セーブで書く。
///   ゲームオーバー後の「最後の記録から読み込む」はこちらを読む。
struct SaveStore {
    let directory: URL
    private let log = Logger(subsystem: "com.yusukedoi.reforge", category: "save")

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("reforge", isDirectory: true)
        }
    }

    private var resumeURL: URL { directory.appendingPathComponent("slot1.json") }
    private var savePointURL: URL { directory.appendingPathComponent("savepoint.json") }

    var hasResume: Bool { FileManager.default.fileExists(atPath: resumeURL.path) }

    func loadResume() -> SaveFile? { read(resumeURL) }

    func saveResume(_ state: GameState, purchases: Purchases) {
        write(SaveFile(state: state, purchases: purchases), to: resumeURL)
    }

    func loadSavePoint() -> GameState? { read(savePointURL)?.state }

    func saveSavePoint(_ state: GameState, purchases: Purchases) {
        write(SaveFile(state: state, purchases: purchases), to: savePointURL)
    }

    func deleteAll() {
        for url in [resumeURL, savePointURL] where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch {
                log.error("delete failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func read(_ url: URL) -> SaveFile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try SaveCodec.decode(Data(contentsOf: url))
        } catch {
            log.error("load failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write(_ file: SaveFile, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try SaveCodec.encode(file).write(to: url, options: .atomic)
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
