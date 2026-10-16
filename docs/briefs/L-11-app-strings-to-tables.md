# 説明書 L-11: アプリの文言を表へ

作業の単位: 多言語 L-11(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の DEC-L1・OPEN-L4・§1・§12.3〜§12.5・BRK-06/19/23/24/27/29・INV-L5・TEST-L10)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-02(入っている)。L-10b の `AppLanguage`・`app_language.json` があればそれも表に載せる(無くても進められる)。土台: integration-d の先頭。
**出す言語は日本語だけのまま**。表に載せる文は**今の日本語の文と 1 字も違わない**(画面の見た目は変えない)。ほかの言語の訳は作らない。`CFBundleLocalizations`・OS の「このアプリの言語」に出る言語は、**出す言語(`LanguageID.released` = 日本語)だけ**にする(使えない言語を OS の設定に出さない)。
アプリは Codex の作業場ではビルドできない。**3 回に分け、1 回ごとに macOS の CI(ci/integration の手動起動)で統合担当が確かめてから次を渡す**。

## 1. 目的
アプリの固定文言を `Localizable.xcstrings`(日本語の文がキー)から、本体と同じ「文言の表」(`ui.*` の ID → 文。差し込みは ICU の一部)へ移す。言語の切り替えが SwiftUI の `Text("…")` の引き直しに頼らず、断片の連結(「残り」+ 数 +「回」、「手ざわり: 」+ 漢数字 +「割くらい」)と漢数字の表をやめて 1 つの差し込みの文にする。読み込みの失敗の画面は、表が読めなくても出せるようにする。

## 2. 作るもの

### 2.1 文言の口(`ReForge/Sources/Theme/UIText.swift` 新規)
```swift
enum UIArg { case int(Int), string(String), fixed(Int64, places: Int) }   // → RenderedArg

@MainActor @Observable final class UIText {
    static let shared = UIText()
    private(set) var language: LanguageID
    func configure(tables: TextTables, language: LanguageID, markFallback: Bool)   // 起動時と切り替えで
    func string(_ id: TextID, _ args: [String: UIArg] = [:]) -> String
}
@MainActor func ui(_ id: TextID, _ args: [String: UIArg] = [:]) -> Text      // Text(verbatim: UIText.shared.string(…))
```
- `string` は `UIText.shared` の観察可能な値を読む(言語が替わると、これを使っている View が**作り直されずに**描き直される。`.id(...)` で全体を作り直さない)。
- 引き方: `tables.pattern(id, language, marker: markFallback)` → `MessageFormat.render`。表に無い ID は、`BootText`(2.4)→ それも無ければ「？」(開発の版は `assertionFailure`)。組めなければ落とさず同じ落とし先。
- `AppModel` が起動時に `configure`。言語の切り替え(L-10b の `AppLanguage.select`)で `configure` を呼び直す。L-10b がまだ入っていなければ、言語は `.ja` 固定で呼ぶ(切り替えの口だけ残す)。

### 2.2 ID の決まりと表
- 置き場: `content/public/text/ja/app.json`(`{"language": "ja", "texts": {…}}`。大きければ画面ごとに `app_<画面>.json` に分けてよい)。`app_language.json`(L-10b)があれば同じ決まりに合わせる。
- 名前: `ui.<幅の区分>.<名前>`。幅の区分は設計書 §11 と同じ: `button`(ボタン)・`band`(帯の項目)・`tab`(タブの名前)・`card`(足元カードの行)・`bubble`(地図のふきだし・調べた結果)・`prologue`(序の行)・`label`(**地図の上の札だけ**)・`body`(資料・ノート・設定の見出しと説明・一覧の行)、読み上げだけのラベルは `ui.a11y.<名前>`。迷ったら `body`。L-13 がこの頭で幅を測る。
- 数・名前の入る文は、名前つきの引数: 「残り {n} 回」「建造中 {p}%」「前回: {last}。次: {next}」。数の複数形や漢数字は**表の言葉として**持つ(例: 割合は `{tenths, select, 1 {一割くらい} 2 {二割くらい} … other {{n}割くらい}}`)。日本語の出力は今と同じ字になること。
- **コードで約物・区切り・単位を足さない**(INV-L5): 「・」「:」「、」「。」の連結、`" "` で名前と数をつなぐ、`Text(a) + Text(b)` の連結、`ForEach` の間に「・」を挟む、を探して表の 1 つの文にする(区切りが要る一覧は、区切りを表の文言にする)。全角の約物(U+3000〜303F・U+FF00〜FFEF)もこの対象。
- 動的に ID を組み立てない(`ui("ui.tab." + x)` は禁止。列挙型から ID への写しをコードに置く)。静的な確かめが ID を文字列として探せるように。

### 2.3 移し方(3 回に分ける)
1. **道具を作る(第 1 回の最初)**: `tools/gen-xcstrings.py` に `--extract` を足す(今の `Text("…")` と補間のキーを JSON で出す: ファイル:行・リテラル・補間の型 `%lld`/`%@`)。これで抜き出した物を、名前つきの引数の `ui.*` に置き換える。
2. **第 1 回 = 基盤 + `Screens/`・`Theme/`・`ReForgeApp.swift`**: `UIText`・`ui()`・`BootText`・`tools/check-app-strings.py`(2.5)・表(`app.json`)・読み込みの失敗の画面。タイトル・設定・購入(広告)・角のボタンの読み上げのラベル(`ui.a11y.settings_open`/`settings_close`)・`InkCard`/`InkButton`/`HoldRing` の文言。
3. **第 2 回 = `Game/` の地図まわり**: `GameScreen`・`MapCanvasView`(断片の連結と漢数字)・`StatusBandView`・`FootCardView`・`FireOutlookLine`・`DayWrapLinesView`・`BattleBandView`・`UndoBand`・`MapActionBand`・`TabBarView`・`GameOverView`・`PrologueScene`・`DarkStartScene`・`StickControl`。
4. **第 3 回 = タブと設計 + 仕上げ**: `Game/Tabs/*`(`CrewTab`・`BaseTab`・`DesignTab`・`NotesTab`)・`Game/Design/*`(`ProcessSheetView`・`WorkbenchModel` の `"\(k)割くらい"`)。続けて 2.6(Info.plist)と 2.7(旧カタログの廃止・文書・CI)。
- 各回の終わりに、`check-app-strings.py` が**ratchet**(2.5 の基準 `tools/app-strings-baseline.json`: ファイル → まだ移していないリテラルの数)で通ること。第 3 回の終わりで基準は空。
- 移した文の**日本語が旧カタログの文字と同じ**であること(第 3 回に `python3 tools/check-app-strings.py --parity-with-catalog` で、旧 `Localizable.xcstrings` の全キーが、`%lld`→`{名前}` の読み替えで表の値のどれかと一致することを確かめ、出力を報告に貼る。広告・購入の画面が M-01 で消えている場合、その文言は移さず、旧カタログの対応する鍵を一覧で報告する)。
- `String(localized:)`(`HoldRing`)・`LocalizedStringKey`(`Picker("…")`・`Toggle("…")`・`restoreMessage` など)・`accessibilityLabel(Text("…"))` も表へ。`#if DEBUG` の開発の設定の節(`SettingsView` の「開発」)・`Debug/` の日本語は開発者向けなので表に移さない(許可の対象。2.5)。

### 2.4 読み込みの失敗の画面(`BootText`。BRK-27)
- `ReForge/Sources/Screens/BootText.swift`: 表が読めない時に出す**数個の文**を、アプリの中に直接持つ: `ui.body.load_failed`(「データを読み込めませんでした」)・`ui.a11y.settings_open`・`ui.a11y.settings_close`・`ui.body.settings`(設定の札の題)。形は `[LanguageID: [TextID: String]]`。**今は日本語の項だけを置く**(ほかの言語の文は作らない。訳の手配は本人の決め)。引くとき、その言語の項が無ければ日本語。
- テスト(`ReForgeTests/BootTextTests.swift`): (i) `BootText` の日本語の値が、公開の層の日本語の表の同じ ID の値と**同じ**(ずれない)。(ii) `LanguageID.released` の全部の言語に `BootText` の項がある(出す言語を増やすとき、読み込みの失敗の画面の文も要る、を強制する。メッセージにそう書く)。
- `ContentErrorView`(`ReForgeApp.swift`): 開発者向けのエラーの文(`String(describing: error)`)を**そのまま見せない**。`BootText` の 1 文を出し、エラーの文は `#if DEBUG` か dev の条件(`REFORGE_DEV`)のときだけ、下に小さく出す。設定の角のボタンはこの画面でも見える(今のまま)。表が無いので設定の札の中身は `BootText` で出せる行だけ(バージョンなど表を要らない物)。
- 封を開けなかったとき(`sealedContentFailed`)の帯の 1 行の文言も表(または `BootText`)から。

### 2.5 静的な確かめ(`tools/check-app-strings.py` 新規。TEST-L10。python3 標準だけ)
`ReForge/Sources/**/*.swift` を調べ、どれか外れたら終了コード 1(ファイル:行だけ出す):
1. **直書きが無い**: コメントを除く文字列リテラルに、かな・漢字・ハングル・全角の約物(U+3000〜303F・U+FF00〜FFEF)が含まれる行は、許可の一覧 `tools/app-strings-allow.json` の物と、`#if DEBUG … #endif` の中と `ReForge/Sources/Debug/` だけ。許可: 言語の名前の表(`AppLanguage` の `// endonym`)・`BootText.swift`。それ以外はファイルごとの基準(`app-strings-baseline.json`)を超えたら失敗(ratchet。基準は減らす方向にだけ更新)。
2. 使っている `ui("…")`・`UIText.shared.string("…")` の ID が、`content/public/text/ja/` の表にある。引数の名前(`[“n”: …]`)が日本語の文の引数の名前の集まりと同じ(行内で読める範囲)。
3. 表の `ui.*` で、アプリのコードのどこからも使われていない ID が無い(`ui.daywrap.*`・`ui.roster.*`・`ui.grant.*` など本体が使う ID は対象外=アプリのコードが ID を持たない物)。
4. ID が `ui.<区分>.<名前>`(区分は 2.2 の 9 つ)の形。
5. `ui(` の引数が文字列リテラルでない(動的な組み立て)。
6. 約物・区切りの連結: `Text(…) + Text(…)`、`Text(verbatim: "\(…)・\(…)")` の類を見つけたら失敗(`verbatim:` で本体が組んだ文・名前を出すのは可。**かな・漢字・約物を含まない**補間だけの物は可)。
- `tools/test_check_app_strings.py`(新規。一時ディレクトリの見本で各規則の内外を確かめる)。`ci.yml` の `app-switches` ジョブで `gen-xcstrings.py --check` の step を `check-app-strings.py` の step に**置き換える**(同じ位置・`if: always()`)。
- `tools/check-no-reason-text.py` を、`Text("…")` のリテラルでなく、`ui("…")` の ID を表の日本語に引いた文で禁止の語を照らす形に直す(対象のファイルと禁止の語は今のまま。INV-F1)。

### 2.6 Info.plist(BRK-23。**出す言語だけ**)
- `project.yml`: `developmentLanguage: ja` はそのまま。プロジェクトに知らせる言語(`knownRegions`)は **`tools/released-languages.py` の出力(今は `ja`)+ `Base`**。XcodeGen の書き方(`options` の `knownRegions` など)は XcodeGen の文書で確かめ、`INFOPLIST_KEY_CFBundleLocalizations` のように**生成の対象でない鍵を書かない**(無効な鍵は黙って捨てられる)。
- `ReForge/Resources/InfoPlist.xcstrings` を新規: `CFBundleDisplayName` を「Re:Forge」(どの言語も同じ。OPEN-L3)、出す言語の項だけ(`ja`)。今は求める許可の文は無いので足さない。
- 新規 `tools/check-languages.py`: `project.yml` の `knownRegions`・`InfoPlist.xcstrings` の言語の項が、`released-languages.py` の出力 + `Base` と**一致**すること(多くても少なくても失敗)。`ci.yml` の `app-switches` ジョブに 1 step。`ios` ジョブの Build の後(Package ipa の前)に、`PlistBuddy -c "Print :CFBundleLocalizations" "$APP/Info.plist"` が出す言語の集合 + `Base` と一致することを確かめる 1 step(一致しなければ失敗)。
- これで、OS の「設定 > このアプリ」の言語の一覧に出るのは日本語だけ。出す言語を増やすときは `released` を直すと、この確かめが project.yml の直しを要求する。

### 2.7 旧カタログの廃止・文書(第 3 回の最後)
- `ReForge/Resources/Localizable.xcstrings` と `tools/gen-xcstrings.py` を削除(`--extract` はこの単位の中で使い終わった後)。`project.yml` の Resources の説明のコメントを直す。
- `docs/architecture/F-work-units.md` §4 の「アプリ: 画面の固定文言は `Text("…")`…」の項を、新しい規則に書き換える(アプリの固定文言は `ui("ui.<区分>.<名前>")` で表から引く。`Text("…")` のリテラルを書かない。コードで約物・区切り・単位を足さない。確かめは `check-app-strings.py`)。`README.md` の 2 行(画面の固定文言の書き方・`tools/` の一覧)を直す。`docs/briefs/screen-snapshots.md` の「訳はまだ無い…カタログの既定」の一文は、表の落とし先(日本語)の言い方に直す。

## 3. テスト
(アプリの単体テストは macOS の CI で回る。Linux で回る分は本体の側。)
1. `ReForgeTests/UITextTests.swift`(新規): (i) `ui` の引数つきの文が日本語で旧カタログと同じ字を返す(代表の 6 つ: 数・名前・割合・複数の引数・約物を表で持つ文・読み上げのラベル)。(ii) 擬似言語で `configure` すると、`string` が `⟦…⟧` で囲まれた文を返す。(iii) 表に無い ID が落ちずに「？」。(iv) 言語を替えると、同じ `UIText` を読む View が作り直されずに更新される(`Observation` の追跡の確認。`withObservationTracking` で変更が通知されること)。
2. `ReForgeTests/BootTextTests.swift`(2.4)。
3. 本体の側(Linux): `ReForgeCore/Tests/RFContentTests` に、公開の層の `ui.*` の表が (i) 読み込めて `ContentValidator` の error が 0、(ii) どの `ui.*` の ID も `ui.<区分>.<名前>`(本体の `ui.daywrap.*` などを除く)、(iii) 日本語の文の引数が書式として読める、を確かめる(`app.json` が `ContentDB` にそのまま載る確かめ)。
4. 静的な確かめ: `tools/test_check_app_strings.py`、`tools/check-app-strings.py`、`tools/check-languages.py`、`tools/test_check_languages.py`(一時ディレクトリの見本で一致・不一致・`Base` の扱い)。
5. 画面: `screens` のジョブ(画面の写真)の `LayoutFitTests`・`ScreenSnapshotTests` が、直す前と同じ(日本語の見た目が変わらない。切れ検出が増えない)で通る。既存の UI テストは日本語のラベルで要素を探している所があるので、文が同じなら壊れない(L-06 が識別子に替える)。

## 4. 確かめのコマンド
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFContentTests|RFPresentTests'
python3 tools/check-app-strings.py
python3 tools/test_check_app_strings.py
python3 tools/check-languages.py
python3 tools/test_check_languages.py
python3 tools/check-no-reason-text.py
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
python3 -c "import yaml; yaml.safe_load(open('project.yml')); yaml.safe_load(open('.github/workflows/ci.yml'))"
```
- 全体のテストは回さない。**note には ssh しない・`rf-note-test` は使わない**。docker は `rf-swift-slot` 経由・`--cpus=3`・`-j 3`。
- アプリのビルド・`ReForgeTests`・`ReForgeUITests`・ipa の `CFBundleLocalizations` の確かめは macOS の CI(ci/integration の手動起動。`run_app_tests`・`screens=true`)で統合担当が回す。報告に「アプリは CI 待ち」と書き、Codex は次の回に進まない。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForge/Sources/**`(文言の置き換え・`UIText.swift`・`BootText.swift` 新規。**見た目・配置・色・識別子は変えない**)、`ReForge/Resources/`(`InfoPlist.xcstrings` 新規、`Localizable.xcstrings` の削除)、`content/public/text/ja/app*.json`(新規)、`project.yml`(2.6 だけ)、`tools/`(2.3・2.5・2.6 の新規と `check-no-reason-text.py`・`gen-xcstrings.py` の削除)、`.github/workflows/ci.yml`(`app-switches` と `ios` の確かめの step だけ)、`ReForgeTests/`・`ReForgeCore/Tests/RFContentTests/`、`docs/architecture/F-work-units.md` §4・`README.md`・`docs/briefs/screen-snapshots.md` の 1 文。
- 触らない: 本体の `ReForgeCore/Sources`(必要なら報告に書く)・`content/private`・`LanguageID.released`(出す言語を増やさない)・字体の選び方(L-12)・配置と幅(L-13)・release の名前・タグ・ipa の名前・保存の形・M-01 が消す画面を、M-01 より先に消さない。

## 6. 約束(F §4)
- 公開リポジトリに物語の語・人の名前を書かない(文言は今の画面の固定文言だけ。新しい文を作らない)。
- **見せた物は使える**: OS の言語の一覧・設定の選択肢に、表が最後までそろっていない言語を出さない(2.6)。
- 画面に、確認のダイアログ・説明・理由の文・チュートリアルを足さない。足元カード・暗い始まり・拠点のタブにできない理由の文を足さない(`check-no-reason-text.py`)。
- 他の言語の訳を作らない。`BootText` にも日本語しか置かない。
- 名前の重なり(`UIText`・`UIArg`・`BootText`・`ui`)を SwiftUI/Foundation の型と重ねない(`check-app-names.py`)。
- 浮動小数を使わない(数の見せ方は本体の `NumberText` と同じ決まり)。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(非公開の層の文言と ID が重ならないこと — `ui.*` が非公開の層に無いこと — を統合担当が確かめる。F §4)。
- 回ごとに: 枝の名前・コミットのハッシュ・4 の結果。**「アプリは CI 待ち」**。
- 移した文の数(旧カタログの鍵の数 → 表の ID の数)、約物・断片の連結を直した場所の一覧、`--parity-with-catalog` の出力、M-01 との重なり(移さなかった広告・購入の文言)、`knownRegions` の書き方をどう確かめたか、設計書と違う判断。
