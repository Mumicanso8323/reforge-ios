# 説明書 L-12: 言語ごとの字体

作業の単位: 多言語 L-12(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §10・OPEN-L2・RISK-L2・BRK-12/15/18/24・§12.5・TEST-L7)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-10b(`AppLanguage`・`InkFont` の観察可能な言語・`-ReForgeLanguage` の起動引数)。書体の土台は art-director の `InkFont.setLanguage`・`family(for:)`(入っている。新しく作らない)。土台: integration-d の先頭。
**出す言語は日本語だけのまま**。この単位は字体と言語の印の配線で、**日本語の見た目は変えない**。中国語・韓国語の字体は同梱しない(iOS の標準の字体を使う。OPEN-L2 の決定)。ほかの言語の訳は作らない。
アプリの変更なので Codex の作業場ではビルドできない。**macOS の CI(ci/integration の手動起動)で統合担当が確かめる**。

## 1. 目的
1. **今の不具合を直す**: `InkFont.language` の初期値が端末の第 1 言語(`Locale.preferredLanguages.first`)で、`setLanguage` を呼ぶ所が無い。日本語しか出さない今のビルドでも、端末の言語が中国語・韓国語だと日本語の文が PingFang や Apple SD Gothic Neo で描かれてしまう(日本語の字形でなくなる)。画面の文の書体は、端末ではなく**アプリが使っている言語**で決める。
2. 言語を切り替えたとき、画面の文の書体・言語の印(`locale`・読み上げの言語)・地図の描画の記憶が、新しい言語になる。
3. 字が字体で描けること(豆腐が出ないこと)を、言語ごとに確かめる道具を作る。

## 2. 作るもの

### 2.1 書体の入口を一本にする(`Theme/InkFont.swift`)
- `InkFont.language` の初期値を、端末の言語ではなく **`LanguageID.source.rawValue`(`ja`)**にする(`InkFont.defaultLanguage`)。アプリの言語が決まる前に描かれても、端末の言語の書体にならない。
- 呼ぶ所は 2 つだけ: (1) `AppModel.init`(L-10b で `AppLanguage.effective` から)、(2) `AppLanguage.select`(L-10b)。ほかから `setLanguage` を呼ばない。L-10b が入っていれば、この 2 つが呼べていることを確かめる。無ければ、この単位で呼び元を足す。
- `family(for:)` の対応は art-director のとおり(日本語・英語・擬似言語 → BIZ UD ゴシック、簡体字 → PingFang SC、繁体字 → PingFang TC、韓国語 → Apple SD Gothic Neo)。**擬似言語 `x-pseudo` を BIZ UD ゴシックに落とす**ことを明示し(今も落ちるが、テストで固定する)、識別子の読み(`zh-Hans-CN`・`zh_TW`・大文字)を、本体の `LanguageResolver.language(forPreferred:)`(L-10b)を使って言語に直してから選ぶ(2 か所に読み替えの規則を書かない)。
- 地図の 1 マスの字(`FontBook.mapFont`)は、言語によらず BIZ UD ゴシック(今のまま)。マスの枠の中央に 1 字を置く作りなので、字体に無い記号は iOS の代わりの字体で描かれても崩れない。

### 2.2 言語の印(`ReForgeApp.swift` の `RootView`)
- 画面の根に `.environment(\.locale, Locale(identifier: <今の言語の識別子>))`。簡体字 `zh-Hans`・繁体字 `zh-Hant`・韓国語 `ko`・英語 `en`・日本語 `ja`(擬似言語は `ja`)。iOS が代わりの字体を選ぶときも、その言語の字形を選ばせるため。値は `AppLanguage.effective` から。切り替えで更新される(作り直されない)。
- **読み上げの言語**: 画面の根に、今の言語を読み上げの言語として付ける。SwiftUI の `locale` の環境で足りるか、`UIAccessibility` の `accessibilityLanguage` を持つ UIKit の包みが要るかは、iOS 17 で使える API の範囲で確かめて選び、どちらにしたかを報告に書く。
- 開発の版で日本語に落ちた行(`[ja]` の目印の付いた行。`markFallback`)は、その行だけ日本語の読み上げにする。判定は純関数 `SpeechLanguage.identifier(for effective: LanguageID, text: String) -> String`(`[ja]` で始まる文は `ja`、それ以外は `effective`)で、テストできる形にする。目印が付くのは日本語以外の言語で表が欠けているときだけなので、日本語だけの今は何も変わらない。

### 2.3 地図の描画の記憶(BRK-12)
- 切り替え(L-03 の `GameStore.setLanguage`)の後、`MapTerrainCache` の画が**新しい言語の字で作り直される**ことを確かめる。`TerrainImageKey` は区画の版(`revision`)を含み、L-03 が切り替えで全区画の版を上げるので、通常は自動で捨てられる。**そうなっていなければ**(区画の版が上がらない・鍵に入らない)、言語を鍵に足すか切り替えで `discardOutside([])` 相当を呼ぶ。字の描画の記憶(`GlyphKey` = 字 + 色)は区画の絵を組む間だけの物で、持ち越さないことも確かめる。

### 2.4 字が描けることの確かめ(TEST-L7。macOS の CI)
- `ReForgeTests/GlyphCoverageTests.swift`: 言語ごとに、(a) その言語の画面の文の字体の連なり(`InkFont.family(for:)` の字体 → iOS の代わりの字体)で、その言語の表(`content` の `textTables.tables[言語]` の全部の値)の全部の字が描ける、(b) 地図の字(`Variant.glyph`・`glyphText`・`content.glyphs`・`TilePalette` の記号)が `FontBook.mapFont` か iOS の代わりの字体で描ける。描ける = `CTFontCreateForString` が返した字体が `LastResort` でなく、`CTFontGetGlyphsForCharacters` で字の字形が得られる。**描けない字は、字と言語と置き場所(文言の ID)を一覧にして失敗**。
- 対象の言語は **`AppLanguage` が出せる言語(= 日本語)**。テストの中で、`LanguageID.shipped` の全 5 言語の**字体の名前そのもの**(`PingFangSC-Regular`・`PingFangTC-Regular`・`AppleSDGothicNeo-Regular`・`BIZUDGothic-Regular`)が iOS の実機・シミュレータで実在する字体として引ける(`UIFont(name:size:)` が nil でない)ことも確かめる(名前の打ち間違いで黙って別の字体になるのを防ぐ)。
- 表が無い言語の字の確かめは、その言語の表が入ってから(L-08 以降)。この単位は道具と、日本語の分だけ。

### 2.5 画面の写真の起動引数(`ReForgeUITests/ScreenSnapshotTests.swift`・`LayoutFitTests.swift`)
- 画面の写真は今 `-AppleLanguages (xx)` と `-AppleLocale` で 5 言語を撮り、アプリの書体は端末の言語に従っていた。2.1 の後は、**アプリの言語に従う**ので、これを足さないと全部が日本語の書体になり、字体の確かめが黙って弱くなる。各言語の起動に `-ReForgeLanguage <言語の識別子>`(L-10b の開発の版の入口)を足す。表が無い言語は日本語の文が日本語に落ちて(開発の版は `[ja]` が付く)出るが、字体・配置の確かめには足りる。
- 写真の名前・枚数(5 言語 × 13 画面)・検査(切れ検出・角のボタン)は今のまま。`-ReForgeLanguage` を付けない起動(日本語)は、直す前と同じ字体であること。

## 3. テスト(アプリの単体テストは macOS の CI)
1. `ReForgeTests/InkFontTests.swift`(新規): `family(for:)` の表 — `ja`・`en`・`x-pseudo`・`fr`(知らない言語)→ BIZ UD ゴシック。`zh-Hans`・`zh-CN`・`zh-SG`・`zh`・`zh-Hans-CN`・`zh_CN` → PingFang SC。`zh-Hant`・`zh-TW`・`zh-HK`・`zh-MO`・`zh-Hant-TW`・`zh_TW` → PingFang TC。`ko`・`ko-KR` → Apple SD Gothic Neo。`InkFont.defaultLanguage == "ja"`。`setLanguage("ko")` の後 `InkFont.body` が韓国語の字体になる(`UIFont` に直して `familyName` を比べる)。テストの後始末で `ja` に戻す。
2. `SpeechLanguageTests`(本体でなくアプリ側の純関数でよい。Linux に置けるなら `ReForgeCore/Tests/RFPresentTests` へ): `[ja] …` → `ja`、それ以外 → 今の言語の識別子、擬似言語 → `ja`。
3. `GlyphCoverageTests`(2.4)。
4. 切り替えの後の描画の記憶: `GameStore` を擬似言語に替える(L-10b の入口)と、全区画の `revision` が上がり、`MapTerrainCache.image(for:…)` が新しい鍵で作り直す(`renderCount` が増える)。同じ言語で呼び直しても作り直しは起きなくてよい。
5. 画面: 5 言語の画面の写真のジョブが、直す前と同じ枚数で通り、切れ検出・角のボタンの検査が新しく落ちない(落ちたら、どの言語のどの画面かを `screens/report.json` から報告に書く。直せるのは配置だけ=L-13)。

## 4. 確かめのコマンド
```
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-app-strings.py          # L-11 が入っていれば
python3 tools/gen-xcstrings.py --check      # L-11 が入るまで
python3 tools/check-public-spoilers.py
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFPresentTests'      # SpeechLanguage を本体に置いたときだけ
```
- 全体のテストは回さない。**note には ssh しない・`rf-note-test` は使わない**。docker は `rf-swift-slot` 経由・`--cpus=3`・`-j 3`。
- アプリのビルド・`ReForgeTests`・`ReForgeUITests`・画面の写真は macOS の CI(ci/integration の手動起動。`run_app_tests`・`screens=true`)で統合担当が回す。報告に「アプリは CI 待ち」と書く。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForge/Sources/Theme/InkFont.swift`、`ReForge/Sources/ReForgeApp.swift`(`RootView` の環境と `AppModel.init` の呼び出し)、`ReForge/Sources/Game/MapScene.swift`・`MapCanvasView.swift`(2.3 が要るときの鍵だけ)、`ReForge/Sources/Screens/AppLanguage.swift`(`setLanguage` を呼ぶ所の確認)、`ReForgeTests/`・`ReForgeUITests/`(上の新規と起動引数の追加)、`ReForgeCore/Sources/RFPresent/`(`SpeechLanguage` を本体に置くとき)と `ReForgeCore/Tests/RFPresentTests/`。
- 触らない: 字体のファイル(`Resources/Fonts`。中国語・韓国語の字体を**同梱しない**)・`FontBook.mapFont` の対応・出す言語(`LanguageID.released`)・文言の表・画面の配置と幅(L-13)・本体の組み立て・`content/`。

## 6. 約束(F §4)
- 公開リポジトリに物語の語・人の名前を書かない。
- **日本語の見た目を変えない**: 日本語の起動(端末の言語が何でも)で、字体・字間・行間が直す前の日本語の端末と同じ。
- 見せた物は使える・画面に説明や確認を足さない。
- 字体を同梱しない・訳を作らない。
- 名前の重なり(`SpeechLanguage` など)を SwiftUI/Foundation/UIKit の型と重ねない(`check-app-names.py`)。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(非公開の層の文の字が日本語の字体で描けること — 豆腐が出ないこと — を統合担当が `GlyphCoverageTests` を非公開の層を重ねて回して確かめる。F §4)。
- 枝の名前・コミットのハッシュ・4 の結果。**「アプリは CI 待ち」**。
- 初期値の不具合が、直す前に実際に再現した条件(端末の言語を中国語にした画面の写真など。CI の写真で比べられれば貼る)、2.2 の読み上げの言語をどの API にしたか、2.3 の記憶が自動で捨てられていたか、設計書と違う判断。
