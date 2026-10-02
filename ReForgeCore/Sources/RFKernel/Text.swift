/// プレイヤーに見せる文言を指す ID と、文言に渡す保存可能な引数。
public enum LanguageID: String, Codable, CaseIterable, Sendable {
    case ja, en, zhHans = "zh-Hans", zhHant = "zh-Hant", ko
    /// 開発版とテストだけで使う擬似言語。
    case pseudo = "x-pseudo"

    public static let shipped: [LanguageID] = [.ja, .en, .zhHans, .zhHant, .ko]
    public static let source: LanguageID = .ja
}

public indirect enum TextArg: Codable, Equatable, Hashable, Sendable {
    case int(Int64)
    /// 整数を 10^places で割った固定小数。浮動小数は保存しない。
    case fixed(Int64, places: Int)
    case text(TextID)
    case subject(SubjectID)
    case person(PersonID)
    case ref(TextRef)
}

public struct TextRef: Codable, Equatable, Hashable, Sendable {
    public var id: TextID
    public var args: [String: TextArg]

    public init(_ id: TextID, _ args: [String: TextArg] = [:]) {
        self.id = id
        self.args = args
    }
}
