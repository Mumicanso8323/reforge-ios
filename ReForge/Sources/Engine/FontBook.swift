import CoreText
import Foundation
import os

/// 同梱の等幅フォント(BIZ UDGothic、SIL Open Font License 1.1。ライセンス文は Resources/Fonts/BIZUDGothic-OFL.txt)。
/// 地図の 1 マス = 1 文字はこのフォントで描く。文字は固定の正方形の枠の中央に置くので、
/// フォントに無い文字(⍋ ∙ ▒ など)がシステムのフォントで描かれても枠はずれない。
enum FontBook {
    /// PostScript 名。
    static let mapFont = "BIZUDGothic-Regular"
    private static let log = Logger(subsystem: "com.yusukedoi.reforge", category: "font")

    /// アプリの起動時に 1 回呼ぶ(Info.plist の UIAppFonts を使わずに登録する)。
    @discardableResult
    static func register(bundle: Bundle = .main) -> Bool {
        guard let url = bundle.url(forResource: mapFont, withExtension: "ttf") else {
            log.error("font file missing")
            return false
        }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        // 2 回目の登録(テストから)は「登録済み」の誤りになる。使えるので成功として扱う。
        if let e = error?.takeRetainedValue(), CFErrorGetCode(e) == CTFontManagerError.alreadyRegistered.rawValue {
            return true
        }
        log.error("font registration failed")
        return false
    }
}
