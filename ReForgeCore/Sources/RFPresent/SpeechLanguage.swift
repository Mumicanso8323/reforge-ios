import RFKernel

/// 読み上げの言語(L-12)。画面の根にはアプリの言語を付け、開発の版で日本語に落ちた行(`[ja]` の印)だけ日本語にする。
public enum SpeechLanguage {
    /// 開発の版の印(TextTables が表に無くて日本語に落ちた文の頭に付ける)。
    public static let fallbackMarker = "[ja]"

    /// 言語の識別子。擬似言語は日本語。`[ja]` で始まる文は日本語、それ以外は effective。
    public static func identifier(for effective: LanguageID, text: String) -> String {
        if text.hasPrefix(fallbackMarker) { return LanguageID.ja.rawValue }
        return base(effective)
    }

    /// 画面の根に付ける言語(擬似言語は ja)。
    public static func base(_ effective: LanguageID) -> String {
        effective == .pseudo ? LanguageID.ja.rawValue : effective.rawValue
    }
}
