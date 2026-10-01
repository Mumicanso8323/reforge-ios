import Foundation

/// 購入状態のキャッシュ(正は StoreKit の権利情報。§5.5)。
public struct Purchases: Codable, Equatable, Sendable {
    public var adsRemoved: Bool

    public init(adsRemoved: Bool = false) {
        self.adsRemoved = adsRemoved
    }
}

/// 保存ファイル 1 つ分(REQ-12)。
public struct SaveFile: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var state: GameState
    public var purchases: Purchases

    public init(state: GameState, purchases: Purchases = Purchases()) {
        self.schemaVersion = SaveCodec.schemaVersion
        self.state = state
        self.purchases = purchases
    }
}

public enum SaveCodecError: Error, Equatable {
    case unsupportedSchema(Int)
}

public enum SaveCodec {
    public static let schemaVersion = 1

    public static func encode(_ file: SaveFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    public static func decode(_ data: Data) throws -> SaveFile {
        let file = try JSONDecoder().decode(SaveFile.self, from: data)
        guard file.schemaVersion == schemaVersion else { throw SaveCodecError.unsupportedSchema(file.schemaVersion) }
        return file
    }
}
