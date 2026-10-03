import Foundation
import ReForgeEngine

/// 保存の書き込みを 1 本に並べる。符号化済みの値だけを受け取るので、画面の主スレッドで JSON を作らない。
protocol SaveWriting: Sendable {
    func write(_ data: Data, slot: SaveSlot) async throws
    func autosaveDawn(_ data: Data) async throws
}

/// ファイルへの書き込みと夜明けの整理を actor の列で行う。
actor SaveWriter: SaveWriting {
    private let storage: any SaveStorage
    private let keepDawns: Int

    init(storage: any SaveStorage, keepDawns: Int = SavePolicy.keepDawns) {
        self.storage = storage
        self.keepDawns = keepDawns
    }

    func write(_ data: Data, slot: SaveSlot) throws {
        try storage.write(data, slot: slot)
    }

    func autosaveDawn(_ data: Data) throws {
        let envelope = try SaveCodec.decode(data)
        guard case .dawn = envelope.slot, envelope.summary.active else { return }
        try storage.write(data, slot: envelope.slot)

        var mine: [Int] = []
        for slot in try storage.list() {
            guard case .dawn(let day) = slot else { continue }
            if let data = try storage.read(slot: slot), let saved = try? SaveCodec.decode(data),
               saved.summary.seed == envelope.summary.seed {
                mine.append(day)
            } else {
                try storage.delete(slot: slot)
            }
        }
        for day in mine.sorted(by: >).dropFirst(keepDawns) {
            try storage.delete(slot: .dawn(day: day))
        }
    }
}
