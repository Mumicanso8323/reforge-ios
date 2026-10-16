# 説明書 L-10b: 言語の設定(設定の言語の節・端末の言語の読み替え)

作業の単位: 多言語 L-10 の残り(L-10a = 角のボタンは入っている)。設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §3.1・§3.2・DEC-L2・OPEN-L1・BRK-01・TEST-L16。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-03(`GameHost.setLanguage`・`GameStore.setLanguage`)と L-04(`LanguageID.released`)。L-10a(`SettingsCorner`・設定の言語の節の空き場所)。土台: integration-d の先頭。
**出す言語は日本語だけのまま**。この単位は「選べる仕組み」で、**画面に出る選択肢は、出す言語に入っていて、表が最後までそろっている言語だけ**(見せた物は使える。使えない選択肢は作らない)。今のデータでは選べる言語が日本語だけなので、**言語の節そのものが画面に出ない**(1 つしか選べない節は置かない)。ほかの言語の訳は作らない。
2 回に分ける: **第 1 回 = 2.1(本体。Linux で全部確かめられる)、第 2 回 = 2.2〜2.5(アプリ。macOS の CI で確かめる)**。

## 1. 目的
言語の選び方を決まりにする: アプリ内の設定が端末より優先。既定は「端末に合わせる」(端末の言語の並びから、**出せる言語**のうち最初に合うもの。どれにも合わなければ英語。英語が出せなければ日本語)。選んだらその場で切り替わる(確認も再起動も無い)。切り替えは世界を進めず、画面だけ組み直す。

## 2. 作るもの

### 2.1 本体: 出せる言語・選び方・読み替え(`ReForgeCore/Sources/RFPresent/LanguageChoice.swift` 新規)
```swift
public enum LanguageChoice: Equatable, Sendable {
    case system
    case language(LanguageID)
    public static let defaultsKey = "reforge.language"
    public init(stored: String?)            // nil・"system"・知らない値 → .system。LanguageID の rawValue → .language
    public var stored: String               // "system" か言語の識別子
}

public enum LanguageOffer {
    public struct Problem: Equatable, Sendable { public enum Kind: Sendable { case missing, arguments, format, nameJoin }
                                                 public var kind: Kind; public var count: Int }
    /// その言語の表が最後までそろっているか。日本語は原文なので常に空。
    public static func problems(_ lang: LanguageID, in tables: TextTables) -> [Problem]
    /// 設定に出してよい言語(出す言語の順)。日本語は常に含める。
    /// 日本語以外は、released に入っていて problems が空のものだけ。includePseudo は開発の版だけ true。
    public static func offered(released: [LanguageID] = LanguageID.released, tables: TextTables,
                               includePseudo: Bool = false) -> [LanguageID]
}

public enum LanguageResolver {
    /// 端末の言語の識別子("zh-Hant-TW"・"zh_TW"・"en-GB"・"ja" など)→ 5 言語のどれか(合わなければ nil)。
    public static func language(forPreferred identifier: String) -> LanguageID?
    /// 実際に使う言語。choice が .language(x) で x が offered にあればそれ。そうでなければ system として決める。
    public static func resolve(_ choice: LanguageChoice, preferred: [String], offered: [LanguageID]) -> LanguageID
}
```
- `problems` の見方(**使える**の定義): 日本語の全 ID がその言語の表にある(`missing`)、日本語の文と引数の名前の集まりが同じ(`arguments`)、書式として読める(`format`)、日本語に `nameJoin` があればその言語にもある(`nameJoin`)。これらの検査は `ContentValidator.textTablesWellFormed` と同じ物を使い、同じ規則を二重に書かない(呼べる形に切り出してよい)。
- 読み替え(§3.1): 大文字小文字を区別せず、`_` と `-` を同じに扱う。`zh-Hans`・`zh-CN`・`zh-SG`・`zh-Hans-*`・地域だけの `zh` → 簡体字。`zh-Hant`・`zh-TW`・`zh-HK`・`zh-MO`・`zh-Hant-*` → 繁体字。`en-*` → 英語、`ja-*` → 日本語、`ko-*` → 韓国語。それ以外(`fr`・`pt-BR` など)→ nil。擬似言語は端末の言語からは決まらない。
- `resolve`: system のとき、`preferred` を順に読み替え、**`offered` に入っている最初**を返す(端末の第 1 言語が出せなければ第 2 言語を見る)。どれにも合わなければ、`offered` に英語があれば英語、無ければ日本語。`.language(x)` の x が `offered` に無い(保存した後でビルドが変わった・擬似言語を出さないビルド)ときは system として決める。**`offered` に無い言語を返さない**。
- 端末の言語の並びを作るのはアプリ(2.2)。本体は文字列の配列を受けるだけ。

### 2.2 アプリ: 言語の状態(`ReForge/Sources/Screens/AppLanguage.swift` 新規)
- `@MainActor @Observable final class AppLanguage`:
  - `init(defaults: UserDefaults = .standard, tables: TextTables, preferred: [String] = AppLanguage.devicePreferred(), includePseudo: Bool = AppLanguage.includesPseudo)`
  - `private(set) var choice: LanguageChoice`(`UserDefaults` の `reforge.language` から。**セーブには入れない**。「記録を消す」でも消えない)、`let offered: [LanguageID]`、`var effective: LanguageID`(`LanguageResolver.resolve`)、`var showsSection: Bool { offered.count >= 2 }`。
  - `func select(_ choice: LanguageChoice)`: 保存し、`effective` を更新し、`InkFont.setLanguage(effective.rawValue)`(2.3)を呼ぶ。ゲーム中なら `AppModel` が `await game.setLanguage(effective)`(L-03)を続けて呼ぶ。
  - `static func devicePreferred() -> [String]`: `Bundle.main.preferredLocalizations` の後ろに `Locale.preferredLanguages` を重複なしで足した並び。
  - 言語の名前: その言語自身の書き方の表(`ja` 日本語・`en` English・`zh-Hans` 简体中文・`zh-Hant` 繁體中文・`ko` 한국어・擬似言語 `Pseudo`)。これは訳す文ではなく名前の表なので、コードに置いてよい(`// endonym` と書く。L-11 の許可の一覧に入れる物)。
- `AppModel`(`ReForgeApp.swift`)が `let language: AppLanguage` を持ち、起動時に `InkFont.setLanguage(language.effective.rawValue)` を呼ぶ。ゲームを作る所(`startNewGame`・`continueGame`・デバッグの流し込み)は、`GameStore` に `language.effective` を渡す(`GameStore.init` に `language: LanguageID = .ja` の引数。`GameBootstrap.host` へ)。開発の版だけ `markFallback: true`。
- `AppModel.deleteSave()` は言語の設定を消さない。

### 2.3 アプリ: 字体の再描画(`Theme/InkFont.swift` の最小の変更)
- `InkFont.language` の保持を `@Observable` の小さな箱(`InkFontState.shared`。`@MainActor`)にして、`InkFont.font(_:relativeTo:)` がそれを読む。`setLanguage` で箱を書くと、`InkFont` を使っている View が**作り直されずに**描き直される(`.id(...)` で全体を作り直さない。地図のカメラ・開いているタブ・パネル・設定の札が保たれる)。
- 字体の選び方(`family(for:)`)・初期値・端末の言語に従う初期値の直しは **L-12**。ここでは触らない。

### 2.4 アプリ: 設定の言語の節(`ReForge/Sources/Screens/LanguageSection.swift` 新規。`SettingsView.swift` の「言語の節の場所」に置く)
- `app.language.showsSection` が false のときは**何も置かない**(見出しも空白も。今のデータではこちら)。
- 節の見出しは文言の表の `ui.body.language`。行は「端末に合わせる」+ `offered` の各言語。
  - 「端末に合わせる」の行は `ui.button.language_system`(文は `端末に合わせる({language})` の形。`{language}` に今の `effective` の名前)。今の言語で書く。
  - 各言語の行は、その言語自身の書き方の名前を、**その言語の字体**で出す(`InkFont.family(for: code)` の `Font.custom`)。
  - 選ばれている行に `checkmark`。1 行 = 44pt 以上の押せる範囲、`.buttonStyle(.inkRow)`。押したらその場で `select`。確認のダイアログ・説明の文・「再起動が必要」の類は出さない。
  - `accessibilityIdentifier`: 節 `languageSection`、行 `languageRow.system` と `languageRow.<言語の識別子>`。選択中の行は `.isSelected` の特性。
- 文言は `content/public/text/ja/app_language.json`(新規。`{"language": "ja", "texts": {…}}`)に、`ui.body.language`=「言語」、`ui.button.language_system`=「端末に合わせる({language})」。L-11 がまだ入っていなければ、この 2 つだけを表から引く小さな口(`AppLanguage` の中)を使い、L-11 が `ui(…)` に置き換える。
- 設定は今のとおり地図の下半分の札。ゲームの時計は設定が開いている間止まる(L-10a)。切り替えで札は閉じない。

### 2.5 アプリ: 開発の版だけの入口(`Debug/ScreenshotMode.swift` の `#if DEBUG`)
- 起動引数 `-ReForgeOfferPseudo YES`: `includesPseudo` を true にする(擬似言語を節に出す。表を持たない言語の画面確認と、節の UI テスト用)。引数が無い起動・製品のビルド(Release)では常に false。
- 起動引数 `-ReForgeLanguage <言語の識別子>`: その実行だけ `choice` を `.language(…)` に固定する(保存しない。`offered` に無い言語でも固定する=字体・配置の確かめ用。L-12・L-13 が使う)。引数が無い起動では何も変わらない。

## 3. テスト

### 3.1 本体(Linux。`ReForgeCore/Tests/RFPresentTests/LanguageChoiceTests.swift` 新規)
1. 読み替えの表: `zh-TW`・`zh-HK`・`zh-MO`・`zh-Hant`・`zh-Hant-TW`・`zh_TW` → 繁体字。`zh-CN`・`zh-SG`・`zh-Hans`・`zh-Hans-CN`・`zh` → 簡体字。`en-US`・`en-GB`・`EN` → 英語。`ja-JP`・`ko-KR`。`fr`・`pt-BR`・空 → nil。
2. `resolve`: 保存した言語が優先。保存が offered に無ければ system。system は offered の最初に合う物(端末が [繁体字, 英語]・offered が [日本語, 英語] なら英語)。合わなければ英語(offered にあれば)、無ければ日本語。**offered が [日本語] のとき、どの端末の言語でも日本語**。擬似言語は offered にあるときだけ選べる。
3. `offered`/`problems`(テストの中でメモリ上の表を作る): 英語の表が日本語の全 ID を持ち引数もそろっていて `released: [.ja, .en]` なら [日本語, 英語]。1 つでも欠ける・引数の名前が違う・書式が読めない・`nameJoin` が無い → 英語は出ない(`problems` の種類と件数が正しい)。**表がそろっていても `released` に無い言語は出ない**。`includePseudo: true` で擬似言語が最後に付く。
4. **今のデータ**: `TestContent.publicOnly()` と(あれば)`TestContent.full()` で、既定の `released`(= 日本語だけ)なら `offered == [.ja]`。`released` に 5 言語を全部明示しても、公開の層の途中の表(試験用の英語・韓国語・中国語)は欠けがあるので `[.ja]` のまま(**途中の表が選択肢に出ない**ことの固定)。
5. `LanguageChoice` の保存の往復と、知らない値が system になること。

### 3.2 アプリ(macOS の CI で統合担当が回す。`ReForgeTests/LanguageSettingTests.swift` 新規)
6. `AppLanguage`: 既定は system。offered が [日本語] なら `effective == .ja`・`showsSection == false`。擬似言語を出す設定なら `showsSection == true`。
7. 擬似言語を選ぶ: `UserDefaults` に保存され、`InkFont` の言語が替わり、ゲーム中なら `GameStore` の文が囲み(`⟦`)に変わり、**保存のバイト列(世界)が選ぶ前と同じ**。日本語に戻すと元の文に戻る。
8. 「記録を消す」(`deleteSave`)で言語の設定が残る。保存した擬似言語が、擬似言語を出さない設定の起動では system に戻る。
9. 設定が開いている間は時計が進まない(L-10a のテストを壊さない)。切り替えの前後で、地図のカメラの位置と開いているタブが変わらない(`GameScreen` の状態を読める範囲で)。

### 3.3 画面(macOS の CI。`ReForgeUITests/ScreenSnapshotTests.swift` に場面を足す)
10. 既定の起動の設定の画面に `languageSection` が**存在しない**(出す言語が日本語だけの間、選べない選択肢を置かない)。
11. `-ReForgeOfferPseudo YES` の起動: `languageSection`・`languageRow.system`・`languageRow.ja`・`languageRow.x-pseudo` がある。擬似言語を押すと、再起動なしに画面の文が囲み付きになり、`settingsButton` が見えて押せて右上の 52×52pt の中にあり、設定の札が開いたまま。日本語の行を押すと戻る。TEST-L16 の「切り替えた後も角のボタンが見える」はこの場面で見る。

## 4. 確かめのコマンド
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFPresentTests|RFContentTests'
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
python3 tools/gen-xcstrings.py --check     # L-11 が入るまで。ReForge/Sources の日本語のリテラルを増やさない(文言は表から)
```
- 全体のテストは回さない。**note には ssh しない・`rf-note-test` は使わない**。docker は `rf-swift-slot` 経由・`--cpus=3`・`-j 3`。
- 第 2 回(アプリ)は Codex の作業場ではビルドできない。型検査と上の静的な検査で守り、`ReForgeTests`・`ReForgeUITests` は **macOS の CI(ci/integration の手動起動。`run_app_tests`・`screens=true`)で統合担当が回す**。報告に「アプリは CI 待ち」と書く。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFPresent/LanguageChoice.swift`(新規)、`ReForgeCore/Sources/RFContent/ContentValidator.swift`(検査を呼べる形に切り出すだけ)、`ReForgeCore/Tests/RFPresentTests/`、`ReForge/Sources/Screens/`(`AppLanguage.swift`・`LanguageSection.swift` 新規、`SettingsView.swift` の空き場所)、`ReForge/Sources/ReForgeApp.swift`(`AppModel` の言語まわり)、`ReForge/Sources/Game/GameStore.swift`(`init` の言語の引数だけ)、`ReForge/Sources/Theme/InkFont.swift`(2.3 だけ)、`ReForge/Sources/Debug/ScreenshotMode.swift`、`content/public/text/ja/app_language.json`(新規)、`ReForgeTests/`・`ReForgeUITests/`(上の新規と最小の直し)。
- 触らない: `LanguageID.released`(出す言語を増やさない)・`project.yml` と `CFBundleLocalizations`(L-11)・字体の選び方と初期値(L-12)・長い文の配置(L-13)・封(L-04)・保存の形・`content/private`・設定の角のボタンの窓(L-10a)。

## 6. 約束(F §4)
- 公開リポジトリに物語の語・人の名前を書かない。
- **見せた物は使える**: 表が最後までそろっていない言語・出す言語に入っていない言語を、設定にも、OS の「このアプリの言語」にも出さない(後者は L-11)。選べる言語が 1 つなら節ごと置かない。
- 画面に、確認のダイアログ・説明・理由の文・チュートリアルを足さない(切り替えは押したその場)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない。アプリの文言は表から(言語の名前の表だけが例外)。
- 浮動小数を使わない。名前の重なり(`LanguageChoice`・`LanguageOffer`・`LanguageResolver`・`AppLanguage`)を Foundation/SwiftUI の型と重ねない(`check-app-names.py`)。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(非公開の層を重ねたときも `offered == [日本語]` のままであることを統合担当が確かめる。F §4)。
- 回ごとに: 枝の名前・コミットのハッシュ・4 の結果(件数・失敗・飛ばし)。第 2 回は「アプリは CI 待ち」。
- `problems` の検査を切り出した所、`InkFont` を観察可能にして描き直しが起きること(作り直しが起きていないことの確かめ方)、設計書と違う判断(読み替えの第 2 言語を見る点・`released` に入らない言語を出さない点)。
