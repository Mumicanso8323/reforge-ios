import Foundation
import Observation
import ReForgeEngine

/// アプリの言語の状態(L-10b)。選びは UserDefaults(`reforge.language`)に置き、セーブには入れない
/// (「記録を消す」でも消えない)。設定が端末の言語より優先。選んだらその場で切り替わる。
@MainActor
@Observable
final class AppLanguage {
    private(set) var choice: LanguageChoice
    /// 設定に出してよい言語(出す言語に入っていて、表が最後までそろっている物。日本語は常に入る)。
    let offered: [LanguageID]
    /// 端末の言語の並び(起動時に決める)。
    @ObservationIgnored private let preferred: [String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tables: TextTables
    /// その実行だけの固定(DEBUG の起動引数)。あれば effective は常にこれ。select も上書きしない。保存しない。
    @ObservationIgnored private let pinned: LanguageID?

    /// 実際に使う言語。
    private(set) var effective: LanguageID

    /// 選べる言語が 2 つ以上のときだけ言語の節を置く(1 つしか選べない節は置かない)。
    var showsSection: Bool { offered.count >= 2 }

    /// pinned が nil でなければ、その実行だけ effective をその言語に固定する(offered に無くてもよい。保存しない。開発の版の起動引数)。
    init(defaults: UserDefaults = .standard, tables: TextTables,
         preferred: [String] = AppLanguage.devicePreferred(),
         includePseudo: Bool = AppLanguage.includesPseudo,
         pinned: LanguageID? = AppLanguage.pinnedLanguage) {
        self.defaults = defaults
        self.tables = tables
        self.preferred = preferred
        let offered = LanguageOffer.offered(tables: tables, includePseudo: includePseudo)
        self.offered = offered
        self.pinned = pinned
        let choice = LanguageChoice(stored: defaults.string(forKey: LanguageChoice.defaultsKey))
        self.choice = choice
        self.effective = LanguageResolver.effective(choice, pinned: pinned, preferred: preferred, offered: offered)
    }

    /// 選びを保存し、字体を替える。ゲーム中の文の引き直しは AppModel が続けて呼ぶ。
    func select(_ choice: LanguageChoice) {
        guard pinned == nil else { return } // 固定の実行では選びを変えず、保存もしない
        defaults.set(choice.stored, forKey: LanguageChoice.defaultsKey)
        self.choice = choice
        effective = LanguageResolver.resolve(choice, preferred: preferred, offered: offered)
        InkFont.setLanguage(effective.rawValue)
    }

    /// `Bundle.main.preferredLocalizations` の後ろに `Locale.preferredLanguages` を重複なしで足した並び。
    static func devicePreferred() -> [String] {
        var out: [String] = []
        for identifier in Bundle.main.preferredLocalizations + Locale.preferredLanguages where !out.contains(identifier) {
            out.append(identifier)
        }
        return out
    }

    /// 擬似言語を節に出すか(開発の版の起動引数だけ。製品では常に false)。
    static var includesPseudo: Bool {
#if DEBUG
        ScreenshotMode.offersPseudo
#else
        false
#endif
    }

    /// その実行だけ固定する言語(開発の版の起動引数だけ。無ければ nil)。
    static var pinnedLanguage: LanguageID? {
#if DEBUG
        ScreenshotMode.pinnedLanguage
#else
        nil
#endif
    }

    /// 名前の表の 1 項目。訳す文ではないので Localizable.xcstrings に入れない(gen-xcstrings は verbatim: の引数を拾わない)。
    private static func endonym(verbatim name: String) -> String { name }

    /// 言語の名前(その言語自身の書き方)。訳す文ではなく名前の表。
    static func name(_ language: LanguageID) -> String {
        switch language {
        case .ja: Self.endonym(verbatim: "日本語") // endonym
        case .en: Self.endonym(verbatim: "English") // endonym
        case .zhHans: Self.endonym(verbatim: "简体中文") // endonym
        case .zhHant: Self.endonym(verbatim: "繁體中文") // endonym
        case .ko: Self.endonym(verbatim: "한국어") // endonym
        case .pseudo: Self.endonym(verbatim: "Pseudo") // endonym
        }
    }

    /// 文言の表から 1 文を引く(L-11 が入るまでの小さな口。入ったら ui(…) に置き換える)。
    func text(_ id: TextID, args: [String: RenderedArg] = [:]) -> String {
        guard let pattern = tables.pattern(id, effective, marker: false) else { return id.rawValue }
        return (try? MessageFormat.render(pattern, args: args, language: effective)) ?? pattern
    }

    /// 「端末に合わせる({language})」の行の文。
    var systemRowTitle: String {
        text("ui.button.language_system", args: ["language": .string(Self.name(effective))])
    }

    var sectionTitle: String { text("ui.body.language") }
}
