import Foundation
import ReForgeEngine

/// 保存の置き場(D-save.md §1)。Application Support/reforge/saves/ にスロットごとの JSON を置く。
/// 書くときは一時ファイル → 置き換え(.atomic。途中で落ちても前の保存が残る)。
struct FileSaveStorage: SaveStorage {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("reforge/saves", isDirectory: true)
        }
    }

    static func fileName(_ slot: SaveSlot) -> String {
        switch slot {
        case .resume: "resume.json"
        case .dawn(let day): "dawn-\(day).json"
        case .manual(let index): "manual-\(index).json"
        }
    }

    static func slot(fileName name: String) -> SaveSlot? {
        guard name.hasSuffix(".json") else { return nil }
        let stem = String(name.dropLast(5))
        if stem == "resume" { return .resume }
        if stem.hasPrefix("dawn-"), let d = Int(stem.dropFirst(5)) { return .dawn(day: d) }
        if stem.hasPrefix("manual-"), let i = Int(stem.dropFirst(7)) { return .manual(index: i) }
        return nil
    }

    private func url(_ slot: SaveSlot) -> URL { directory.appendingPathComponent(Self.fileName(slot)) }

    func write(_ data: Data, slot: SaveSlot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(slot), options: .atomic)
    }

    func read(slot: SaveSlot) throws -> Data? {
        let u = url(slot)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try Data(contentsOf: u)
    }

    func delete(slot: SaveSlot) throws {
        let u = url(slot)
        if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
    }

    func list() throws -> [SaveSlot] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap(Self.slot(fileName:))
    }

    func deleteAll() throws {
        for s in try list() { try delete(slot: s) }
    }
}
