import SwiftUI
import ReForgeEngine

/// 設定の言語の節(L-10b)。選べる言語が 1 つ(いまは日本語だけ)のときは何も置かない(見出しも空白も)。
/// 行は「端末に合わせる」と、出してよい言語(表が最後までそろっている物)。押したらその場で切り替わる
/// (確認のダイアログ・説明の文・再起動の案内は出さない。札も閉じない)。
struct LanguageSection: View {
    @Bindable var app: AppModel

    var body: some View {
        if app.language.showsSection {
            InkSection(title: ui("ui.body.language")) {
                row(id: "system", title: ui("ui.button.language_system", ["language": .string(AppLanguage.name(app.language.effective))]), selected: app.language.choice == .system) {
                    app.selectLanguage(.system)
                }
                ForEach(app.language.offered, id: \.self) { language in
                    row(id: language.rawValue,
                        title: Text(verbatim: AppLanguage.name(language))
                            .font(Font.custom(InkFont.family(for: language.rawValue), size: 15, relativeTo: .body)),
                        selected: app.language.choice == .language(language)) {
                        app.selectLanguage(.language(language))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("languageSection")
        }
    }

    private func row(id: String, title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            InkRow(title: title, value: selected ? Text(Image(systemName: "checkmark")) : nil)
        }
        .buttonStyle(.inkRow)
        .accessibilityIdentifier("languageRow.\(id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
