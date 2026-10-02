import RFKernel

/// 文言の組み立てに渡す、名前への解決後の値。
public enum RenderedArg: Equatable, Sendable {
    case string(String)
    case number(Int64, places: Int)
}

public enum PluralCategory: String, Sendable {
    case zero, one, two, few, many, other
}

/// 指定された言語の複数形を、この製品で必要な範囲だけ判定する。
public enum PluralRule {
    public static func category(_ n: Int64, places: Int, _ lang: LanguageID) -> PluralCategory {
        switch lang {
        case .en, .pseudo:
            return places == 0 && n == 1 ? .one : .other
        case .ja, .zhHans, .zhHant, .ko:
            return .other
        }
    }
}

/// 固定小数の決定的な表示。現時点では全言語で同じ口を使う。
public enum NumberText {
    public static func format(_ n: Int64, places: Int, language: LanguageID) -> String {
        // 言語別の表記を追加するときの入口を残す。現在は仕様どおり同じ表記。
        switch language {
        case .ja, .en, .zhHans, .zhHant, .ko, .pseudo:
            return decimal(n, places: places)
        }
    }

    private static func decimal(_ n: Int64, places: Int) -> String {
        let sign = n < 0 ? "-" : ""
        let digits = String(n.magnitude)
        guard places > 0 else { return sign + digits }

        if digits.count <= places {
            return sign + "0." + String(repeating: "0", count: places - digits.count) + digits
        }

        let split = digits.index(digits.endIndex, offsetBy: -places)
        return sign + String(digits[..<split]) + "." + String(digits[split...])
    }
}

/// 韓国語の助詞を、直前の語の最後の書記素から選ぶ。
public enum Josa {
    public static func pick(after word: String, pair: (String, String)) -> String {
        guard let last = word.last else { return "\(pair.0)(\(pair.1))" }
        let scalars = last.unicodeScalars

        if scalars.count == 1, let scalar = scalars.first {
            let value = scalar.value
            if (0xAC00...0xD7A3).contains(value) {
                let jongseong = (value - 0xAC00) % 28
                if jongseong == 0 { return pair.1 }
                if jongseong == 8 && pair.0 == "으로" && pair.1 == "로" { return pair.1 }
                return pair.0
            }

            switch value {
            case 48, 49, 51, 54, 55, 56: return pair.0
            case 50, 52, 53, 57: return pair.1
            default: break
            }
        }

        return "\(pair.0)(\(pair.1))"
    }
}

/// ICU MessageFormat の、この製品で許可する小さな部分集合のレンダラー。
public enum MessageFormat {
    public static func render(_ pattern: String, args: [String: RenderedArg], language: LanguageID) throws -> String {
        var parser = PatternParser(pattern)
        let nodes = try parser.parse()
        return render(nodes, args: args, language: language, pound: nil)
    }

    private static func render(
        _ nodes: [PatternNode],
        args: [String: RenderedArg],
        language: LanguageID,
        pound: (Int64, Int)?
    ) -> String {
        nodes.map { node in
            switch node {
            case let .literal(value):
                return value
            case let .argument(name):
                return string(for: args[name], name: name, language: language)
            case let .plural(name, choices):
                guard case let .number(number, places)? = args[name] else { return missing(name) }
                let exact = "=\(normalized(number, places: places))"
                let category = PluralRule.category(number, places: places, language).rawValue
                guard let branch = choices[exact] ?? choices[category] ?? choices["other"] else {
                    return missing(name)
                }
                return render(branch, args: args, language: language, pound: (number, places))
            case let .select(name, choices):
                guard case let .string(value)? = args[name] else { return missing(name) }
                guard let branch = choices[value] ?? choices["other"] else { return missing(name) }
                return render(branch, args: args, language: language, pound: pound)
            case let .josa(name, pair):
                guard case let .string(value)? = args[name] else { return missing(name) }
                return value + Josa.pick(after: value, pair: pair)
            case let .cap(name):
                guard case let .string(value)? = args[name] else { return missing(name) }
                return capitalizedLatinInitial(value)
            case .pound:
                guard let pound else { return "#" }
                return NumberText.format(pound.0, places: pound.1, language: language)
            }
        }.joined()
    }

    private static func string(for arg: RenderedArg?, name: String, language: LanguageID) -> String {
        guard let arg else { return missing(name) }
        switch arg {
        case let .string(value): return value
        case let .number(number, places): return NumberText.format(number, places: places, language: language)
        }
    }

    private static func missing(_ name: String) -> String { "⟦?\(name)⟧" }

    /// 完全一致の選択子は 1.0 と 1 を同じ値として扱う。
    private static func normalized(_ number: Int64, places: Int) -> String {
        let formatted = NumberText.format(number, places: places, language: .en)
        guard let dot = formatted.firstIndex(of: ".") else { return formatted }
        var end = formatted.endIndex
        while end > dot {
            let before = formatted.index(before: end)
            guard formatted[before] == "0" else { break }
            end = before
        }
        return end == dot ? String(formatted[..<dot]) : String(formatted[..<end])
    }

    private static func capitalizedLatinInitial(_ word: String) -> String {
        guard let first = word.first, first.unicodeScalars.count == 1, let scalar = first.unicodeScalars.first else {
            return word
        }
        guard (97...122).contains(scalar.value) else { return word }
        return String(first).uppercased() + String(word.dropFirst())
    }
}

private indirect enum PatternNode {
    case literal(String)
    case argument(String)
    case plural(String, [String: [PatternNode]])
    case select(String, [String: [PatternNode]])
    case josa(String, (String, String))
    case cap(String)
    case pound
}

private enum PatternError: Error {
    case malformed
}

private struct PatternParser {
    private let characters: [Character]
    private var position = 0

    init(_ pattern: String) {
        characters = Array(pattern)
    }

    mutating func parse() throws -> [PatternNode] {
        try sequence(untilClosingBrace: false, inPlural: false)
    }

    private mutating func sequence(untilClosingBrace: Bool, inPlural: Bool) throws -> [PatternNode] {
        var nodes: [PatternNode] = []
        var literal = ""

        func flushLiteral() {
            if !literal.isEmpty {
                nodes.append(.literal(literal))
                literal = ""
            }
        }

        while position < characters.count {
            let character = characters[position]
            if character == "'", position + 2 < characters.count,
                (characters[position + 1] == "{" || characters[position + 1] == "}"), characters[position + 2] == "'"
            {
                literal.append(characters[position + 1])
                position += 3
            } else if character == "{" {
                flushLiteral()
                position += 1
                nodes.append(try placeholder())
            } else if character == "}" {
                guard untilClosingBrace else { throw PatternError.malformed }
                flushLiteral()
                position += 1
                return nodes
            } else if character == "#", inPlural {
                flushLiteral()
                nodes.append(.pound)
                position += 1
            } else {
                literal.append(character)
                position += 1
            }
        }

        guard !untilClosingBrace else { throw PatternError.malformed }
        flushLiteral()
        return nodes
    }

    private mutating func placeholder() throws -> PatternNode {
        let name = try token()
        guard position < characters.count else { throw PatternError.malformed }
        if characters[position] == "}" {
            position += 1
            return .argument(name)
        }

        try consume(",")
        let form = try token()
        switch form {
        case "plural", "select":
            try consume(",")
            let choices = try options(inPlural: form == "plural")
            if form == "plural", choices["other"] == nil { throw PatternError.malformed }
            return form == "plural" ? .plural(name, choices) : .select(name, choices)
        case "josa":
            try consume(",")
            let pairText = try remainder()
            let pieces = pairText.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty else { throw PatternError.malformed }
            return .josa(name, (pieces[0], pieces[1]))
        case "cap":
            guard position < characters.count, characters[position] == "}" else { throw PatternError.malformed }
            position += 1
            return .cap(name)
        default:
            throw PatternError.malformed
        }
    }

    private mutating func options(inPlural: Bool) throws -> [String: [PatternNode]] {
        var result: [String: [PatternNode]] = [:]
        while true {
            skipWhitespace()
            guard position < characters.count else { throw PatternError.malformed }
            if characters[position] == "}" {
                position += 1
                return result
            }
            let selector = try token()
            guard result[selector] == nil else { throw PatternError.malformed }
            guard position < characters.count, characters[position] == "{" else { throw PatternError.malformed }
            position += 1
            result[selector] = try sequence(untilClosingBrace: true, inPlural: inPlural)
        }
    }

    private mutating func token() throws -> String {
        skipWhitespace()
        let start = position
        while position < characters.count {
            let character = characters[position]
            if character.isWhitespace || character == "," || character == "{" || character == "}" { break }
            position += 1
        }
        guard start < position else { throw PatternError.malformed }
        let value = String(characters[start..<position])
        skipWhitespace()
        return value
    }

    private mutating func remainder() throws -> String {
        skipWhitespace()
        let start = position
        while position < characters.count, characters[position] != "}" {
            guard characters[position] != "{" else { throw PatternError.malformed }
            position += 1
        }
        guard position < characters.count else { throw PatternError.malformed }
        let value = String(characters[start..<position]).trimmingWhitespace()
        guard !value.isEmpty else { throw PatternError.malformed }
        position += 1
        return value
    }

    private mutating func consume(_ character: Character) throws {
        guard position < characters.count, characters[position] == character else { throw PatternError.malformed }
        position += 1
        skipWhitespace()
    }

    private mutating func skipWhitespace() {
        while position < characters.count, characters[position].isWhitespace {
            position += 1
        }
    }
}

private extension String {
    func trimmingWhitespace() -> String {
        let characters = Array(self)
        guard let first = characters.firstIndex(where: { !$0.isWhitespace }) else { return "" }
        guard let last = characters.lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(characters[first...last])
    }
}
