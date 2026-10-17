import RFContent
import RFKernel

/// 設定で選ぶ言語。アプリ内の設定が端末より優先。保存はセーブの外(UserDefaults)。
public enum LanguageChoice: Equatable, Sendable {
    case system
    case language(LanguageID)

    public static let defaultsKey = "reforge.language"

    /// nil・"system"・知らない値は .system。
    public init(stored: String?) {
        if let stored, let language = LanguageID(rawValue: stored) {
            self = .language(language)
        } else {
            self = .system
        }
    }

    public var stored: String {
        switch self {
        case .system: return "system"
        case .language(let language): return language.rawValue
        }
    }
}

/// 設定に出してよい言語。見せた物は使える(表が最後までそろっている言語だけ)。
public enum LanguageOffer {
    public struct Problem: Equatable, Sendable {
        public enum Kind: Sendable { case missing, arguments, format, nameJoin }
        public var kind: Kind
        public var count: Int

        public init(kind: Kind, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    /// その言語の表が最後までそろっているか。日本語は原文なので常に空。
    /// 1 つの文の検査は `TextTables.entryFault`(検証器と同じ規則)。
    public static func problems(_ lang: LanguageID, in tables: TextTables) -> [Problem] {
        guard lang != .ja else { return [] }
        let japanese = tables.tables[.ja] ?? [:]
        let table = tables.tables[lang] ?? [:]
        var missing = 0, arguments = 0, format = 0
        for (id, source) in japanese {
            guard let pattern = table[id] else {
                missing += 1
                continue
            }
            switch TextTables.entryFault(pattern, source: source) {
            case .format?: format += 1
            case .arguments?: arguments += 1
            case .orphan?, nil: break
            }
        }
        var out: [Problem] = []
        if missing > 0 { out.append(Problem(kind: .missing, count: missing)) }
        if arguments > 0 { out.append(Problem(kind: .arguments, count: arguments)) }
        if format > 0 { out.append(Problem(kind: .format, count: format)) }
        if tables.meta[.ja]?.nameJoin != nil, tables.meta[lang]?.nameJoin == nil {
            out.append(Problem(kind: .nameJoin, count: 1))
        }
        return out
    }

    /// 設定に出してよい言語(出す言語の順)。日本語は常に含める。
    /// 日本語以外は、released に入っていて problems が空のものだけ。includePseudo は開発の版だけ true。
    public static func offered(released: [LanguageID] = LanguageID.released, tables: TextTables,
                               includePseudo: Bool = false) -> [LanguageID]
    {
        var out: [LanguageID] = [.ja]
        for language in released where language != .ja && language != .pseudo && !out.contains(language) {
            if problems(language, in: tables).isEmpty { out.append(language) }
        }
        if includePseudo { out.append(.pseudo) }
        return out
    }
}

public enum LanguageResolver {
    /// 端末の言語の識別子("zh-Hant-TW"・"zh_TW"・"en-GB"・"ja" など)→ 5 言語のどれか(合わなければ nil)。
    public static func language(forPreferred identifier: String) -> LanguageID? {
        let parts = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let head = parts.first else { return nil }
        switch head {
        case "ja": return .ja
        case "en": return .en
        case "ko": return .ko
        case "zh":
            let rest = parts.dropFirst()
            if rest.contains("hant") || rest.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return .zhHant }
            return .zhHans
        default: return nil
        }
    }

    /// 実際に使う言語。choice が .language(x) で x が offered にあればそれ。そうでなければ system として決める。
    /// offered に無い言語は返さない。
    public static func resolve(_ choice: LanguageChoice, preferred: [String], offered: [LanguageID]) -> LanguageID {
        if case .language(let chosen) = choice, offered.contains(chosen) { return chosen }
        for identifier in preferred {
            if let language = language(forPreferred: identifier), offered.contains(language) { return language }
        }
        if offered.contains(.en) { return .en }
        return .ja
    }
}
