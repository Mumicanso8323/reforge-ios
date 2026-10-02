import SwiftUI

/// 文字組み(docs/art/README.md §2)。書体は言語ごとに 1 つ(日本語・英語は同梱の BIZ UDGothic、
/// 中国語と韓国語は iOS の標準の書体。BIZ UDGothic にハングルと簡体字の字形が無いため)。
/// 大きさは 5 段だけ使う。Dynamic Type には relativeTo で追従する。
/// 地図の 1 マス 1 文字は言語によらず FontBook.mapFont(記号は書体に無くても固定の枠の中央に描く)。
enum InkFont {
    /// 今の言語(入口はここ 1 か所)。アプリの言語の設定が変わったら setLanguage で入れ、画面を描き直す。
    private(set) static var language: String = Locale.preferredLanguages.first ?? "ja"

    static func setLanguage(_ identifier: String) {
        language = identifier
    }

    /// 言語の識別子(ja・en・zh-Hans・zh-Hant・ko など)から書体の名前を選ぶ。
    static func family(for identifier: String) -> String {
        let id = identifier.lowercased()
        if id.hasPrefix("ko") { return "AppleSDGothicNeo-Regular" }
        if id.hasPrefix("zh") {
            // 繁体字(zh-Hant・台湾・香港・マカオ)と簡体字を分ける
            if id.contains("hant") || id.contains("-tw") || id.contains("-hk") || id.contains("-mo") { return "PingFangTC-Regular" }
            return "PingFangSC-Regular"
        }
        return FontBook.mapFont
    }

    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        Font.custom(family(for: language), size: size, relativeTo: style)
    }

    /// 12pt 注記・広告の注意・バージョン。
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
    static let gap: CGFloat = 8
    static let rowHeight: CGFloat = 44
    static let buttonHeight: CGFloat = 44
    static let corner: CGFloat = 4
    static let rule: CGFloat = 1
}
