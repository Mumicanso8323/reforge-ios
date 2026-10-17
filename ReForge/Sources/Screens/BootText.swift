import ReForgeEngine

/// 読み込みの失敗の画面が出す文(L-11 / BRK-27)。文言の表が読めない時でも出せるよう、アプリの中に直接持つ。
/// 今は日本語の項だけ(出す言語は日本語だけ。ほかの言語の文は作らない。出す言語を増やす時は、ここにも項が要る
/// — BootTextTests が `LanguageID.released` の全部の言語に項があることを確かめる)。
/// 公開の層の表(`content/public/text/ja/app.json`)の同じ ID の値と同じ文(BootTextTests が確かめる)。
enum BootText {
    static let table: [LanguageID: [TextID: String]] = [
        .ja: [
            "ui.body.load_failed": "データを読み込めませんでした",
            "ui.a11y.settings_open": "設定を開く",
            "ui.a11y.settings_close": "設定を閉じる",
            "ui.body.settings": "設定",
        ],
    ]

    /// その言語の項。無ければ日本語。ID が無ければ nil。
    static func string(_ id: TextID, _ language: LanguageID) -> String? {
        table[language]?[id] ?? table[.ja]?[id]
    }
}
