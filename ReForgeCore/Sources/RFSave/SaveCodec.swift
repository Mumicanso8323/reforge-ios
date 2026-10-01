import Foundation
import RFKernel
import RFWorld

/// 保存ファイル 1 つ(D-save.md)。版付きの JSON。世界状態を丸ごと持つ(名前・文章は持たない。ID と数だけ)。
public struct SaveEnvelope: Codable, Equatable, Sendable {
    /// ファイルの種類の印。
    public var format: String
    /// 世界状態の形の版。形を変えたら SaveCodec.schemaVersion を上げ、移行を 1 つ足す。
    public var schemaVersion: Int
    /// どのコンテンツで遊んでいたか(層の id と版)。ID の付け替えの移行の判断に使う。
    public var content: [ContentStamp]
    /// どの保存か。
    public var slot: SaveSlot
    public var world: WorldState

    public init(slot: SaveSlot, world: WorldState, content: [ContentStamp]) {
        self.format = SaveCodec.format
        self.schemaVersion = SaveCodec.schemaVersion
        self.content = content
        self.slot = slot
        self.world = world
    }
}

public struct ContentStamp: Codable, Equatable, Sendable {
    public var layer: String
    public var version: String

    public init(layer: String, version: String) {
        self.layer = layer
        self.version = version
    }
}

/// 保存の場所(D-save.md §2)。
public enum SaveSlot: Codable, Hashable, Sendable {
    /// いまの続き(アプリを閉じる・背面に回るたびに上書き)。
    case resume
    /// 夜明けの自動セーブ(直近いくつかを残す)。巻き戻しの戻り先。
    case dawn(day: Int)
    /// 手動セーブ。
    case manual(index: Int)
}

public enum SaveCodecError: Error, Equatable {
    case notASave
    case tooNew(Int)
    case missingMigration(from: Int)
}

/// 世界状態の版の移行。古い JSON の木を 1 版ずつ新しい形に書き換える(古い struct を残さなくてよい)。
public struct SaveMigration: Sendable {
    /// この版の木を受け取り、次の版の木にする。
    public let from: Int
    public let migrate: @Sendable (inout Value) throws -> Void

    public init(from: Int, migrate: @escaping @Sendable (inout Value) throws -> Void) {
        self.from = from
        self.migrate = migrate
    }
}

public enum SaveCodec {
    public static let format = "reforge.save"
    /// 世界状態の形の版。1 = この骨組み(b7 の SaveFile とは別物。b7 のセーブは読まない)。
    public static let schemaVersion = 1
    /// 移行の並び(from の昇順)。形を変えた担当がここに 1 つ足す。
    public static let migrations: [SaveMigration] = []

    public static func encode(_ e: SaveEnvelope) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(e)
    }

    public static func decode(_ data: Data, migrations: [SaveMigration] = migrations) throws -> SaveEnvelope {
        var tree = try JSONDecoder().decode(Value.self, from: data)
        guard tree["format"]?.stringValue == format, let v = tree["schemaVersion"]?.intValue else {
            throw SaveCodecError.notASave
        }
        var version = Int(v)
        guard version <= schemaVersion else { throw SaveCodecError.tooNew(version) }
        while version < schemaVersion {
            guard let m = migrations.first(where: { $0.from == version }) else {
                throw SaveCodecError.missingMigration(from: version)
            }
            try m.migrate(&tree)
            version += 1
            if case .object(var o) = tree {
                o["schemaVersion"] = .int(Int64(version))
                tree = .object(o)
            }
        }
        return try JSONDecoder().decode(SaveEnvelope.self, from: JSONEncoder().encode(tree))
    }
}

/// 保存の置き場(アプリが FileManager で実装する。テストは辞書で)。本体は壁時計もファイルも触らない。
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
