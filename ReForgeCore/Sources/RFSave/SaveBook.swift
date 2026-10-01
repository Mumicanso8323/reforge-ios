import Foundation
import RFKernel
import RFWorld

/// 保存の置き場(アプリは FileSaveStorage、テストは MemorySaveStorage)。本体は壁時計を読まない。
public protocol SaveStorage: Sendable {
    func write(_ data: Data, slot: SaveSlot) throws
    func read(slot: SaveSlot) throws -> Data?
    func delete(slot: SaveSlot) throws
    func list() throws -> [SaveSlot]
}

/// 夜明けの自動セーブを何日分残すか(巻き戻しの戻り先は最新の 1 つ。残りは「セーブ地点からロード」用)。
public enum SavePolicy {
    public static let keepDawns = 3
}

/// 一覧の 1 行(セーブ地点からロードの選択肢)。
public struct SavePoint: Equatable, Sendable {
    public var slot: SaveSlot
    /// 読めなかったときは nil(problem に理由)。黙って一覧から落とさない。
    public var summary: SaveSummary?
    public var problem: String?
}

/// 保存の帳簿。どの時点で・どの場所に書くか、どれを消すかの規則をここにまとめる(GameHost が呼ぶ)。
///
/// - 続き(resume): 背面に回る・閉じるたびに上書き。画面側の途中の状態(ui)を添える。
/// - 夜明け(dawn): 夜明けごとに 1 つ。同じ走行(seed)の直近 keepDawns 日を残す。巻き戻しの戻り先。
/// - 手動(manual): プレイヤーが選んだ番号に上書き。最初からやり直しても消さない。
/// - 時間軸を捨てたとき(ロード・巻き戻し・最初から)、その先の夜明けは消す(戻り先が別の未来にならないように)。
public struct SaveBook: Sendable {
    public let storage: any SaveStorage
    /// いま遊んでいるコンテンツの版(保存に残す)。
    public let content: [ContentStamp]
    public let keepDawns: Int

    public init(storage: any SaveStorage, content: [ContentStamp], keepDawns: Int = SavePolicy.keepDawns) {
        self.storage = storage
        self.content = content
        self.keepDawns = keepDawns
    }

    // MARK: 書く

    /// 続きを書く(アプリが背面に回るとき・閉じるとき)。失敗・結末の後の世界もそのまま書く(開き直すと 4 択に戻る)。
    public func writeResume(_ w: WorldState, ui: Value? = nil) throws {
        try write(SaveEnvelope(slot: .resume, world: w, content: content, ui: ui))
    }

    public func readResume() throws -> SaveEnvelope? { try load(.resume) }

    /// 夜明けの自動セーブ(GameHost が DomainEvent.dawn を見たら呼ぶ)。進行中の世界だけ書く。
    /// 同じ日の夜明けは上書き(巻き戻した後の夜明けも、その日の戻り先になる)。
    @discardableResult
    public func autosaveDawn(_ w: WorldState) throws -> Bool {
        guard w.run.isActive else { return false }
        try write(SaveEnvelope(slot: .dawn(day: w.clock.day), world: w, content: content))
        try pruneDawns(keeping: w)
        return true
    }

    public func saveManual(_ w: WorldState, index: Int) throws {
        try write(SaveEnvelope(slot: .manual(index: index), world: w, content: content))
    }

    /// 新しく始めた(最初から): 前の走行の夜明けと続きを消し、1 日目の夜明けを書く。手動セーブは残す。
    public func startNew(_ w: WorldState) throws {
        for s in try storage.list() {
            switch s {
            case .dawn, .resume: try storage.delete(slot: s)
            case .manual: break
            }
        }
        try autosaveDawn(w)
        try writeResume(w)
    }

    // MARK: 読む

    public func load(_ slot: SaveSlot) throws -> SaveEnvelope? {
        guard let d = try storage.read(slot: slot) else { return nil }
        return try SaveCodec.decode(d)
    }

    /// セーブ地点の一覧(夜明けの新しい順 → 手動の番号順)。続きは含めない。
    public func savePoints() throws -> [SavePoint] {
        let slots = try storage.list().filter { $0 != .resume }.sorted(by: Self.order)
        return slots.map { s in
            do {
                guard let e = try load(s) else { return SavePoint(slot: s, summary: nil, problem: "missing") }
                return SavePoint(slot: s, summary: e.summary, problem: nil)
            } catch {
                return SavePoint(slot: s, summary: nil, problem: "\(error)")
            }
        }
    }

    /// 記憶を持って巻き戻すときの戻り先: 同じ走行の、失敗した日以前で最新の夜明け。
    public func rewindTarget(for failed: WorldState) throws -> SaveEnvelope? {
        let days = try storage.list().compactMap { s -> Int? in
            if case .dawn(let d) = s, d <= failed.clock.day { d } else { nil }
        }.sorted(by: >)
        for d in days {
            guard let e = try? load(.dawn(day: d)) else { continue }
            if e.summary.seed == failed.seed, e.summary.active { return e }
        }
        return nil
    }

    /// 時間軸を w に切り替えた(ロード・巻き戻し): 別の走行の夜明けと、w より先の日の夜明けを消す。
    public func adoptTimeline(_ w: WorldState) throws {
        for s in try storage.list() {
            guard case .dawn(let d) = s else { continue }
            if d > w.clock.day {
                try storage.delete(slot: s)
            } else if let e = try? load(s), e.summary.seed != w.seed {
                try storage.delete(slot: s)
            }
        }
    }

    // MARK: 内部

    func write(_ e: SaveEnvelope) throws {
        try storage.write(SaveCodec.encode(e), slot: e.slot)
    }

    func pruneDawns(keeping w: WorldState) throws {
        var mine: [Int] = []
        for s in try storage.list() {
            guard case .dawn(let d) = s else { continue }
            if let e = try? load(s), e.summary.seed == w.seed { mine.append(d) } else { try storage.delete(slot: s) }
        }
        for d in mine.sorted(by: >).dropFirst(keepDawns) { try storage.delete(slot: .dawn(day: d)) }
    }

    static func order(_ a: SaveSlot, _ b: SaveSlot) -> Bool {
        switch (a, b) {
        case (.dawn(let x), .dawn(let y)): x > y
        case (.dawn, _): true
        case (.manual(let x), .manual(let y)): x < y
        case (.manual, .dawn): false
        case (.manual, _): true
        case (.resume, _): false
        }
    }
}

// MARK: - 置き場の実装

/// メモリの置き場(テスト・プレビュー用)。
public final class MemorySaveStorage: SaveStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [SaveSlot: Data] = [:]

    public init() {}

    public func write(_ data: Data, slot: SaveSlot) throws { lock.withLock { files[slot] = data } }
    public func read(slot: SaveSlot) throws -> Data? { lock.withLock { files[slot] } }
    public func delete(slot: SaveSlot) throws { _ = lock.withLock { files.removeValue(forKey: slot) } }
    public func list() throws -> [SaveSlot] { lock.withLock { Array(files.keys) } }
}

/// ファイルの置き場(アプリは Application Support/reforge/saves を渡す)。書き込みは一時ファイルからの置き換え(atomic)。
public struct FileSaveStorage: SaveStorage {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    func url(_ s: SaveSlot) -> URL { directory.appendingPathComponent(s.fileStem + ".json") }

    public func write(_ data: Data, slot: SaveSlot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(slot), options: .atomic)
    }

    public func read(slot: SaveSlot) throws -> Data? {
        let u = url(slot)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try Data(contentsOf: u)
    }

    public func delete(slot: SaveSlot) throws {
        let u = url(slot)
        if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
    }

    public func list() throws -> [SaveSlot] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .compactMap { SaveSlot(fileStem: String($0.dropLast(5))) }
    }
}
