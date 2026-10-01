import Foundation
import ReForgeEngine

/// 保存の置き場(D-save.md §1)。型は本体(RFSave.FileSaveStorage)のものを使い、アプリは既定の場所と全消しだけを足す。
/// 既定の場所: Application Support/reforge/saves/。書き込みは本体側で一時ファイル → 置き換え(.atomic)。
extension FileSaveStorage {
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(directory: base.appendingPathComponent("reforge/saves", isDirectory: true))
    }

    func deleteAll() throws {
        for s in try list() { try delete(slot: s) }
    }
}
