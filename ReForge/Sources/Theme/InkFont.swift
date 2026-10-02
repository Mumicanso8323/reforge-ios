import SwiftUI

/// 文字組み(docs/art/README.md §2)。書体は同梱の BIZ UDGothic 一つ(地図と同じ。全角の幅がそろう)。
/// 大きさは 5 段だけ使う。Dynamic Type には relativeTo で追従する。
enum InkFont {
    /// 12pt 注記・広告の注意・バージョン。
    static let caption = Font.custom(FontBook.mapFont, size: 12, relativeTo: .caption)
    /// 14pt 帯・一覧の補助。
    static let small = Font.custom(FontBook.mapFont, size: 14, relativeTo: .footnote)
    /// 15pt 本文・ボタン・一覧の行。
    static let body = Font.custom(FontBook.mapFont, size: 15, relativeTo: .body)
    /// 20pt パネルの見出し。
    static let heading = Font.custom(FontBook.mapFont, size: 20, relativeTo: .title3).bold()
    /// 40pt タイトルの文字。
    static let display = Font.custom(FontBook.mapFont, size: 40, relativeTo: .largeTitle).bold()

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
