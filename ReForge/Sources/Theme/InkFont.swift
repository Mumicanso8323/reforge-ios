import SwiftUI
import Observation
import ReForgeEngine

/// 今の言語を入れる観察できる小さな箱(L-10b)。InkFont.font がここを読むので、setLanguage で書くと
/// InkFont を使っている View が作り直されずに描き直される(.id で全体を作り直さない)。
/// 書く側は主スレッドの 1 か所だけ(AppLanguage.select と AppModel.init)。読む側の InkFont.font が
/// MainActor の外(非分離の文脈)からも呼ばれるので、@MainActor にはせず @unchecked Sendable で通す。
@Observable
final class InkFontState: @unchecked Sendable {
    static let shared = InkFontState()
    var language: String = InkFont.defaultLanguage
}

/// 文字組み(docs/art/README.md §2)。書体は言語ごとに 1 つ(日本語・英語は同梱の BIZ UDGothic、
/// 中国語と韓国語は iOS の標準の書体。BIZ UDGothic にハングルと簡体字の字形が無いため)。
/// 大きさは 5 段だけ使う。Dynamic Type には relativeTo で追従する。
/// 地図の 1 マス 1 文字は言語によらず FontBook.mapFont(記号は書体に無くても固定の枠の中央に描く)。
enum InkFont {
    /// 今の言語(入口はここ 1 か所)。アプリの言語の設定が変わったら setLanguage で入れ、画面を描き直す。
    static var language: String { InkFontState.shared.language }

    /// 呼ぶのは AppModel.init と AppLanguage.select だけ。
    static func setLanguage(_ identifier: String) {
        InkFontState.shared.language = identifier
    }

    /// 既定の言語。アプリの言語が決まる前に描かれても端末の言語の書体にならない(端末の第 1 言語は見ない)。
    static let defaultLanguage = LanguageID.source.rawValue

    /// 言語の識別子(ja・en・zh-Hans・zh_TW・x-pseudo など)から書体の名前を選ぶ。
    /// 識別子の読み替えは LanguageResolver に任せる(規則を 2 か所に書かない)。知らない言語・擬似言語は BIZ UD ゴシック。
    static func family(for identifier: String) -> String {
        switch LanguageResolver.language(forPreferred: identifier) {
        case .ko?: return "AppleSDGothicNeo-Regular"
        case .zhHant?: return "PingFangTC-Regular"
        case .zhHans?: return "PingFangSC-Regular"
        default: return FontBook.mapFont
        }
    }

    /// 出す言語ごとの書体の名前(実在の確かめ用。GlyphCoverageTests)。
    static func family(for language: LanguageID) -> String { family(for: language.rawValue) }

    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        Font.custom(family(for: language), size: size, relativeTo: style)
    }

    /// 12pt 注記・購入の補助・バージョン。
    static var caption: Font { font(12, relativeTo: .caption) }
    /// 14pt 帯・一覧の補助。
    static var small: Font { font(14, relativeTo: .footnote) }
    /// 15pt 本文・ボタン・一覧の行。
    static var body: Font { font(15, relativeTo: .body) }
    /// 20pt パネルの見出し。
    static var heading: Font { font(20, relativeTo: .title3).bold() }
    /// 40pt タイトルの文字。
    static var display: Font { font(40, relativeTo: .largeTitle).bold() }

    /// 行間(本文 15pt に対して 1.5 倍 ≒ +7pt)。
    static let bodyLineSpacing: CGFloat = 7
    /// 字間(見出しとタイトルだけ少し開ける)。
    static let headingTracking: CGFloat = 1.5
    static let displayTracking: CGFloat = 4
}

/// 余白と寸法(4 の倍数)。
enum InkMetric {
    static let gutter: CGFloat = 16
    /// 右上に空けておく場所(窓の一番上に 1 つだけ置く設定のボタン。52×52pt)。
    /// 上の帯・頁の見出し・下からの札の見出しは、右端をこの幅だけ空ける。
    static let settingsReserve: CGFloat = 52
    static let gap: CGFloat = 8
    static let rowHeight: CGFloat = 44
    static let buttonHeight: CGFloat = 44
    static let corner: CGFloat = 4
    static let rule: CGFloat = 1
    /// 収まらないときの最後の手段の縮小(L-13。WidthClass.minimumScale の % を倍率に直す、アプリで 1 か所)。
    static let minimumScale: CGFloat = CGFloat(WidthClass.minimumScale) / 100
}
