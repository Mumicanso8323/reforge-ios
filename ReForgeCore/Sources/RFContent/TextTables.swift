import RFKernel

public enum TextLookup: Equatable, Sendable {
    case found(String)
    case fallback(String)
    case missing
}

public struct NameJoin: Codable, Equatable, Sendable {
    public var order: [String]
    public var separator: String

    public init(order: [String], separator: String) {
        self.order = order
        self.separator = separator
    }
}

public struct TextMeta: Codable, Equatable, Sendable {
    public var nameJoin: NameJoin?

    public init(nameJoin: NameJoin? = nil) {
        self.nameJoin = nameJoin
    }
}

public struct TextTables: Equatable, Sendable {
    public var tables: [LanguageID: [TextID: String]] = [:]
    public var meta: [LanguageID: TextMeta] = [:]

    public init() {}

    /// 表を持つ言語(擬似言語は含めない)。
    public var available: Set<LanguageID> { Set(tables.keys).subtracting([.pseudo]) }

    /// 擬似言語は日本語の文を伸ばして返す。ほかの言語は日本語だけをフォールバックにする。
    public func lookup(_ id: TextID, _ lang: LanguageID) -> TextLookup {
        guard let japanese = tables[.ja]?[id] else { return .missing }
        if lang == .pseudo {
            let dots = String(repeating: "・", count: (japanese.count * 4 + 9) / 10)
            return .found("⟦" + japanese + dots + "⟧")
        }
        if let text = tables[lang]?[id] { return .found(text) }
        return .fallback(japanese)
    }

    /// 画面に出す前の文の型。日本語へのフォールバックだけを印で示せる。
    public func pattern(_ id: TextID, _ lang: LanguageID, marker: Bool) -> String? {
        switch lookup(id, lang) {
        case .found(let text): return text
        case .fallback(let text): return marker ? "[ja]" + text : text
        case .missing: return nil
        }
    }
}
