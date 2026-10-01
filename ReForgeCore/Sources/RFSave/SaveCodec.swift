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
    /// 一覧に出す要約(世界を全部読まずに「何日目・何周目」を出すため)。世界から作る。
    public var summary: SaveSummary
    public var world: WorldState

    public init(slot: SaveSlot, world: WorldState, content: [ContentStamp]) {
        self.format = SaveCodec.format
        self.schemaVersion = SaveCodec.schemaVersion
        self.content = content
        self.slot = slot
        self.summary = SaveSummary(world)
        self.world = world
    }
}

/// 保存の要約。
public struct SaveSummary: Codable, Equatable, Sendable {
    /// どの走行か(新しく始めるたびに変わる。巻き戻し・ロードでは変わらない)。
    public var seed: UInt64
    public var day: Int
    public var phase: DayPhase
    public var at: GameTime
    /// 何周目か(巻き戻すと増える)。
    public var run: Int
    public var rewinds: Int
    /// 進行中か(失敗・結末の後の保存はセーブ地点にしない)。
    public var active: Bool

    public init(_ w: WorldState) {
        seed = w.seed
        day = w.clock.day
        phase = w.clock.phase
        at = w.clock.now
        run = w.run.index
        rewinds = w.run.rewinds
        active = w.run.isActive
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
    /// 続きに添える画面側の途中の状態(置くモードの照準・設計画面の下書き)。SaveEnvelope ではなく、画面が決めた
    /// 小さな JSON をそのまま置く(本体は中身を見ない。読めなくても遊べる。C §6・D §2)。
    case screen
    /// 夜明けの自動セーブ(直近いくつかを残す)。巻き戻しの戻り先。
    case dawn(day: Int)
    /// 手動セーブ。
    case manual(index: Int)

    /// ファイルの名前(拡張子なし)。保存の置き場が使う。
    public var fileStem: String {
        switch self {
        case .resume: "resume"
        case .screen: "resume-ui"
        case .dawn(let d): "dawn-\(d)"
        case .manual(let i): "manual-\(i)"
        }
    }

    public init?(fileStem s: String) {
        if s == "resume" { self = .resume; return }
        if s == "resume-ui" { self = .screen; return }
        if s.hasPrefix("dawn-"), let d = Int(s.dropFirst(5)) { self = .dawn(day: d); return }
        if s.hasPrefix("manual-"), let i = Int(s.dropFirst(7)) { self = .manual(index: i); return }
        return nil
    }
}

public enum SaveCodecError: Error, Equatable {
    case notASave
    case tooNew(Int)
    case missingMigration(from: Int)
    case migrationFailed(from: Int, reason: String)
}

/// 世界状態の版の移行。古い JSON の木を 1 版ずつ新しい形に書き換える(古い struct を残さなくてよい)。
///
/// 手順(D §4): 形を変えたら schemaVersion を 1 上げ、`from: 旧版` の移行を `SaveCodec.migrations` に足し、
/// 旧版の固定の JSON(Tests/RFSaveTests/Fixtures/save-v<旧版>.json)を消さずに残す(読めることをテストが見張る)。
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
    /// セーブの互換を守り始めたか(最初のリリースで true にする)。false の間は版 1 のまま形を変えてよく、
    /// 固定の JSON との突き合わせは「作り直しが要る」と知らせるだけにする(F §4)。
    public static let compatibilityFrozen = false
    /// 移行の並び(from の昇順)。形を変えた担当がここに 1 つ足す。
    public static let migrations: [SaveMigration] = []

    /// 正準の JSON(同じ値なら必ず同じバイト列。CanonicalJSON)。
    public static func encode(_ e: SaveEnvelope) throws -> Data {
        try CanonicalJSON.encode(e)
    }

    public static func decode(_ data: Data, migrations: [SaveMigration] = migrations) throws -> SaveEnvelope {
        let tree: Value
        do { tree = try JSONDecoder().decode(Value.self, from: data) } catch { throw SaveCodecError.notASave }
        return try decode(tree: tree, migrations: migrations)
    }

    /// 版を上げてから読む。
    public static func decode(tree original: Value, migrations: [SaveMigration] = migrations) throws -> SaveEnvelope {
        let tree = try migrate(original, migrations: migrations)
        return try JSONDecoder().decode(SaveEnvelope.self, from: Data(CanonicalJSON.bytes(tree)))
    }

    /// 木を今の版まで移行する(読まずに木のまま返す。テストと道具用)。
    public static func migrate(_ original: Value, migrations: [SaveMigration] = migrations) throws -> Value {
        var tree = original
        guard tree["format"]?.stringValue == format, let v = tree["schemaVersion"]?.intValue else {
            throw SaveCodecError.notASave
        }
        var version = Int(v)
        guard version <= schemaVersion else { throw SaveCodecError.tooNew(version) }
        while version < schemaVersion {
            guard let m = migrations.first(where: { $0.from == version }) else {
                throw SaveCodecError.missingMigration(from: version)
            }
            do { try m.migrate(&tree) } catch {
                throw SaveCodecError.migrationFailed(from: version, reason: "\(error)")
            }
            version += 1
            if case .object(var o) = tree {
                o["schemaVersion"] = .int(Int64(version))
                tree = .object(o)
            }
        }
        return tree
    }
}

/// 移行を書くための小さな道具(木の中の 1 か所を書き換える)。
extension Value {
    /// "world.people.persons" のような点区切りの道筋で、オブジェクトの中の値を書き換える。道筋が無ければ何もしない。
    public mutating func modify(_ path: String, _ body: (inout Value) throws -> Void) rethrows {
        try modify(path.split(separator: ".").map(String.init)[...], body)
    }

    private mutating func modify(_ path: ArraySlice<String>, _ body: (inout Value) throws -> Void) rethrows {
        guard let head = path.first else { return try body(&self) }
        guard case .object(var o) = self, var child = o[head] else { return }
        try child.modify(path.dropFirst(), body)
        o[head] = child
        self = .object(o)
    }

    /// オブジェクトのキーを足す・置き換える(nil で消す)。
    public mutating func setKey(_ key: String, _ v: Value?) {
        guard case .object(var o) = self else { return }
        o[key] = v
        self = .object(o)
    }
}
