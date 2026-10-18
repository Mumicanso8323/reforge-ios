import SwiftUI
import Observation
import ReForgeEngine

/// 画面の固定文言に渡す引数(L-11)。本体の `RenderedArg` に写す。
enum UIArg {
    case int(Int)
    case string(String)
    case fixed(Int64, places: Int)

    var rendered: RenderedArg {
        if case .string(let s) = self { return .string(s) }
        if case .fixed(let n, let places) = self { return .number(n, places: places) }
        if case .int(let n) = self { return .number(Int64(n), places: 0) }
        return .string("")
    }
}

/// アプリの固定文言の口(L-11)。本体と同じ「文言の表」(`ui.*` の ID → 文。差し込みは ICU の一部)から引く。
/// 言語は観察できる値で、切り替えると、これを読んでいる View が作り直されずに描き直される。
@MainActor
@Observable
final class UIText {
    static let shared = UIText()

    /// いま引いている言語。
    private(set) var language: LanguageID = .ja
    /// 表を替えた回数(観察のため。表が替わっても言語が同じなら描き直す)。
    private(set) var revision = 0
    @ObservationIgnored private var tables = TextTables()
    @ObservationIgnored private var markFallback = false

    init() {}

    /// 起動時と言語の切り替えで呼ぶ。markFallback は開発の版だけ true(表に無くて日本語に落ちた文に [ja] の印を付ける)。
    func configure(tables: TextTables, language: LanguageID, markFallback: Bool) {
        self.tables = tables
        self.markFallback = markFallback
        self.language = language
        revision += 1
    }

    /// 1 つの文を引く。表に無い ID は BootText、それも無ければ「？」(開発の版は assertionFailure)。組めなくても落とさず同じ落とし先。
    func string(_ id: TextID, _ args: [String: UIArg] = [:]) -> String {
        _ = revision // 観察の対象に入れる(language と合わせて、変わったら描き直す)
        let language = self.language
        if let pattern = tables.pattern(id, language, marker: markFallback),
           let text = try? MessageFormat.render(pattern, args: args.mapValues(\.rendered), language: language) {
            return text
        }
        if let text = BootText.string(id, language) { return text }
#if DEBUG
        assertionFailure("文言の表に無い ID: \(id.rawValue)")
#endif
        return "？"
    }
}

/// 画面の固定文言を 1 つの Text にする。`Text(verbatim:)` に表から引いた文を渡す(LocalizedStringKey を通さない)。
@MainActor
func ui(_ id: TextID, _ args: [String: UIArg] = [:]) -> Text {
    spokenText(UIText.shared.string(id, args))
}

/// 画面に出す 1 つの文を Text にする(読み上げの言語の口。ゲーム本体の文も固定文言もここを通す)。
/// 文に開発の版の印 `[ja]` があれば、その行だけ日本語で読む属性を付ける。文字は変えない(印は見せたまま)。
/// 印が無い文・日本語がアプリの言語の時は、今までと同じ `Text(verbatim:)`。
@MainActor
func spokenText(_ string: String) -> Text {
    let language = UIText.shared.language
    guard SpeechLanguage.isMarked(string),
          SpeechLanguage.identifier(for: language, composed: string) != SpeechLanguage.base(language) else {
        return Text(verbatim: string)
    }
    return Text(SpokenString.attributed(string))
}

/// 行の読み上げ言語を日本語にした属性付きの文。
enum SpokenString {
    static func attributed(_ string: String) -> AttributedString {
        var attributed = AttributedString(string)
        attributed[SpeechLanguageKey.self] = LanguageID.ja.rawValue
        attributed[AttributeScopes.FoundationAttributes.LanguageIdentifierAttribute.self] = LanguageID.ja.rawValue
        return attributed
    }

    /// 属性が付いているか(テスト用)。
    static func spokenLanguage(of attributed: AttributedString) -> String? {
        attributed[SpeechLanguageKey.self]
    }
}

/// UIKit の読み上げの言語の鍵(`UIAccessibilitySpeechAttributeLanguage`)。Swift の AttributedString の
/// AccessibilityAttributes には言語の属性が無い(iOS 17)ので、NSAttributedString に渡る名前で鍵を持つ。
enum SpeechLanguageKey: ObjectiveCConvertibleAttributedStringKey {
    typealias Value = String
    typealias ObjectiveCValue = NSString
    static let name = "UIAccessibilitySpeechAttributeLanguage"

    static func objectiveCValue(for value: String) throws -> NSString { value as NSString }
    static func value(for object: NSString) throws -> String { object as String }
}
