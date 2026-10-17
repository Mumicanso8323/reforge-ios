import RFKernel
import RFText

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

    public enum EntryFault: Equatable, Sendable { case format, orphan, arguments }

    /// 1 つの文の検査。読める書式で、日本語と同じ引数の名前を持つ(検証器と設定の言語の候補が同じ規則を使う)。
    /// 日本語自身は source に自分を渡す。source が nil は日本語に対応する文が無い。
    public static func entryFault(_ pattern: String, source: String?) -> EntryFault? {
        guard (try? MessageFormat.validate(pattern)) != nil else { return .format }
        guard let source else { return .orphan }
        guard let sourceNames = try? MessageFormat.argumentNames(source),
              let translatedNames = try? MessageFormat.argumentNames(pattern),
              sourceNames == translatedNames else { return .arguments }
        return nil
    }

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
