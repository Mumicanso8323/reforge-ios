# 説明書 L-13: 長い文の配置(幅の区分)

作業の単位: 多言語 L-13(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §11・BRK-20/21/34・TEST-L8)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-11(`ui.<区分>.<名前>` の表)・L-12(言語ごとの字体)・L-10b(`-ReForgeLanguage`・`-ReForgeOfferPseudo`)。序の層(W-16/PT-B6)の配置と組。土台: integration-d の先頭。
**出す言語は日本語だけのまま**。この単位は「文が長くなっても壊れない配置」で、**日本語の見た目は変えない**(日本語が今収まっている所は、収まったまま・同じ寸法のまま)。ほかの言語の訳は作らない(長さの試しは擬似言語 = 日本語の文を 4 割伸ばした機械的な変形)。
アプリの変更なので Codex の作業場ではビルドできない。**2 回に分け、1 回ごとに macOS の CI で統合担当が確かめてから次へ**: 第 1 回 = 2.1〜2.2(区分の表と配置の直し)、第 2 回 = 2.3〜2.4(測る道具と擬似言語の画面の写真)。

## 1. 目的
英語・韓国語は日本語より横に長くなる(日本語は 1 字 = 1em)。配置が文の長さに耐えるようにする: 固定の幅・固定の高さ・行数の上限が、文が伸びると切れる・重なる所を、**文言ごとの「幅の区分」**で決めた規則に直す。短い言い方で収める(訳す人の仕事)ことを前提にして、収まらないときの最後の手段(0.85 倍までの縮小)と、伸ばして収める所(足元カード・ふきだし・本文)を分ける。

## 2. 作るもの

### 2.1 幅の区分の表(`ReForgeCore/Sources/RFText/WidthClass.swift` 新規。純 Swift。Linux で確かめる)
```swift
public enum WidthClass: String, CaseIterable, Sendable {
    case button, band, tab, card, bubble, prologue, label, body
    public var pointSize: Int            // 字の大きさ(pt)
    public var maxWidth: Int?            // 幅の上限(pt)。無ければ nil
    public var maxLines: Int?            // 行の上限。無ければ nil
    public var shrinkable: Bool          // 0.85 倍まで縮めてよい(button・band だけ)
    public var growsWithText: Bool       // 文が伸びたら箱が伸びる(card・bubble・prologue・body)
    /// 文言の ID の頭 `ui.<区分>.` から区分を決める。合わない ID(本体の `ui.daywrap.*` など)と `ui.a11y.*` は .body(読み上げ専用は測らない)。
    public static func of(_ id: TextID) -> WidthClass
}
```
- 値は設計書 §11 の表のとおり: `button` 16pt・150pt・1 行・縮める。`band` 14pt・110pt・1 行・縮める。`tab` 12pt・64pt・1 行・縮めない(収まらなければ検査で止める)。`card` 15pt・343pt・2 行・伸ばす。`bubble` 14pt・260pt・4 行・伸ばす。`prologue` 17pt・310pt・1 文が 2 行まで・伸ばす(日本語は 1 行 18 字以内=今の決まり)。`label` 12pt・120pt・1 行・末尾を切る。`body` 15pt・343pt・行の上限なし・縦に流す。幅の基準は iPhone の最小の画面幅 375pt から左右 16pt を引いた 343pt。
- 縮小の下限 `WidthClass.minimumScale = 85`(‰ でなく % の整数。浮動小数を使わないため、アプリで `0.85` に直す定数は 1 か所)。
- 大きい文字(Dynamic Type)は今回の範囲の外。幅は標準の大きさで測る。

### 2.2 配置の直し(アプリ。`ReForge/Sources/**`。第 1 回)
**最初に棚卸し**: 文を入れる箱で、固定の幅・固定の高さ・行数の上限を持つ所を全部挙げ(`rg "frame\(width:|frame\(height:|minHeight|lineLimit|minimumScaleFactor"` を手がかりに)、各所を「伸ばす / 縮める / そのまま(記号・絵・文を含まない)」に分けた表を報告に貼る。直す方針は次のとおり。**日本語で今収まっている所は、見た目の寸法を変えない**(`min`/`max` に替えるだけで、日本語の文なら今と同じ寸法になること)。
- **ボタン**(`InkButtonStyle` ほか): 1 行のまま `.minimumScaleFactor(0.85)` を先に付ける。幅は文に合わせて伸びる(`minWidth` は今のまま、固定の幅にしない)。タイトルの幅 240pt の固定(`DarkStartScene`)は最小の幅にする。
- **帯の項目**(`StatusBandView`・`BattleBandView`・`UndoBand`・`FireOutlookLine`・`MapActionBand`): 1 行のまま `.minimumScaleFactor(0.85)`。帯の内側は右に 52pt(`InkMetric.settingsReserve`)を空けたまま。折り返す並び(項目が直の子になる流れ)は今のまま。封の失敗の注意の 1 行など説明の文は 2 行まで。
- **タブの名前**(`TabBarView`): 1 行・縮めない。収まらない文は検査(2.3)が止める。固定幅を持たせない(均等割りの幅で収まるかを測る)。
- **足元カード**(`FootCardView`): 名前の行を 2 行まで(`lineLimit(2)`)。高さは `minHeight: 84` から内容に合わせて伸びる(固定の高さにしない)。日本語では今と同じ 84pt のまま。カードが伸びても地図の操作(操作棒・長押し)の当たりを押し出さない。
- **地図のふきだし・調べた結果**(`MapCanvasView` の `inspection`・`forgePanel`): 幅 260pt を上限に、4 行まで、高さは内容に合わせる。画面の外にはみ出さない(画面の端で折り返す・寄せる今の作りのまま)。
- **序の行**(`PrologueScene`・`DarkStartScene`): 1 文が 2 行まで折り返しても重ならない(固定の高さ `height * 0.5` などの枠が、文の 2 行目を切らない)。送りのボタンの当たりと設定の角を押し出さない。
- **本文・一覧**(`InkRow`・`InkSection`・`CrewTab` の固定幅 44pt の見出しなど): 見出しに固定の幅を付けず `fixedSize` か `min` にする。行は縦に流す(`lineLimit(1)` の一覧の行は、`body` の文なら 2 行まで許す)。数の列だけ固定でよい。
- **地図の上の札**(`label`): 1 行・末尾を切る(今のまま)。
- 文の中の約物・単位をコードで足している所があれば、L-11 の約束(INV-L5)に反するので報告に書く(この単位では直さない)。

### 2.3 測る道具(アプリのテスト。第 2 回)
- `ReForgeTests/TextWidthTests.swift`(TEST-L8): 表(`UIText` が引く `ui.<区分>.*` の全部)の文を、`WidthClass.of(id)` の区分の字の大きさ・**本当の字体**(`InkFont.family(for:)` の言語ごとの字体。`UIFont` と `NSAttributedString.size`)で測る。
  - **出す言語のうち日本語以外**(今は無い)は、`button`・`band`・`tab`・`label` の幅が区分の上限(縮める区分は `0.85` を掛けた余裕込み)に収まること。収まらない文は ID・言語・測った幅・上限を一覧にして失敗。
  - **日本語は現状の測定値を一覧に出すだけ**(失敗にしない)。日本語は今の画面の文であり、区分の上限は翻訳者への目安(短い言い方を書く基準)なので。上限を超える日本語の文の一覧を報告に貼る。
  - `LanguageID.released` と `AppLanguage` が出す言語が増えたとき、日本語以外の測定が自動で効く(テストが言語を列挙する)。
- 区分ごとの上限は、表の文の長さの目安 `maxWidth` を Linux の道具(L-08 = 非公開側の仕事)が先に出す。この単位は実機の字体で測る側だけ。

### 2.4 擬似言語の画面の写真(第 2 回。`ReForgeUITests/ScreenSnapshotTests.swift`・`LayoutFitTests.swift`)
- 画面の写真の全部の画面(13 画面)を、`-ReForgeLanguage x-pseudo -ReForgeOfferPseudo YES` で 1 回ずつ追加で撮る(`pseudo_<画面>.png`。5 言語の枚数には足さない別の組)。擬似言語は日本語の文を 4 割伸ばした物。
- 切れ検出(`InkFitLog`。`InkFitCheck` の id)を**区分に対応づける表**をコードに持つ(例: `InkButton.label` = button、`InkPanel.title`・`InkRow.title` = body …)。擬似言語の撮影では、**伸ばす区分(`card`・`bubble`・`prologue`・`body`)の id が切れていたら失敗**。縮める・切る区分(`button`・`band`・`tab`・`label`)の切れは、`screens/report.json` に「報告」として載せるだけで失敗にしない(擬似言語の 4 割増しは、短い言い方を書く前提の区分の上限を超えるため)。表に無い id が出たら失敗(区分を決め忘れない)。
- 角のボタン(`settingsButton`)の検査(TEST-L16)は擬似言語の写真でも通ること。文が伸びても右上の 52×52pt を空けたまま、重ならない。
- 日本語の写真(`-ReForgeLanguage` を付けない)は、直す前と同じ寸法で通る(`LayoutFitTests` が今の値のまま)。

## 3. テスト
1. 本体(Linux。`ReForgeCore/Tests/RFTextTests/WidthClassTests.swift` 新規): 表の値が 2.1 のとおり。`of(_:)` — `ui.button.x`→button、`ui.tab.x`→tab、`ui.band.x`、`ui.card.x`、`ui.bubble.x`、`ui.prologue.x`、`ui.label.x`、`ui.body.x`、`ui.a11y.x`・`ui.daywrap.x`・知らない区分・`ui.button`(名前なし)→ body。`growsWithText` が card・bubble・prologue・body だけ、`shrinkable` が button・band だけ。
2. アプリ(CI): `TextWidthTests`(2.3)・擬似言語の画面の写真(2.4)・既存の日本語の写真と `LayoutFitTests` が直す前と同じ寸法。
3. 配置の単体テスト(`ReForgeTests/`): 足元カードが日本語で 84pt、擬似言語の長い名前で 84pt を超えて伸び、画面の下の端を越えない。ふきだしが 4 行で止まり、画面の幅(343pt)の内側に収まる(ふきだしの文を伸ばした見本で)。
4. 静的: `tools/check-app-strings.py`(L-11)・`check-app-switches.py`・`check-app-names.py`。

## 4. 確かめのコマンド
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFTextTests'
python3 tools/check-app-strings.py
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
```
- 全体のテストは回さない。**note には ssh しない・`rf-note-test` は使わない**。docker は `rf-swift-slot` 経由・`--cpus=3`・`-j 3`。
- アプリのビルド・`ReForgeTests`・`ReForgeUITests`・画面の写真は macOS の CI(ci/integration の手動起動。`run_app_tests`・`screens=true`)で統合担当が回す。Codex は「アプリは CI 待ち」と書いて止まる(画面の写真の PNG を見るのは統合担当)。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFText/WidthClass.swift`(新規)と `ReForgeCore/Tests/RFTextTests/`、`ReForge/Sources/**` の配置の修飾子(`frame`・`lineLimit`・`minimumScaleFactor`・`fixedSize`・`minHeight`・余白)。`ReForgeTests/`・`ReForgeUITests/`(新規と起動引数・切れ検出の表)。
- 触らない: 文言の表と文(`content/`・日本語の文を縮めない)・字体の選び方(L-12)・出す言語(`LanguageID.released`)・本体の組み立て・色・絵・操作の仕組み(押す・長押し・操作棒の当たりの寸法を変えない)・識別子(`accessibilityIdentifier` を変えない)・設定の角の窓(L-10a)。

## 6. 約束(F §4)
- 公開リポジトリに物語の語・人の名前を書かない。
- **日本語の見た目を変えない**(寸法・改行・余白)。日本語が収まっている所の「固定」を「最小/最大」に替えるだけ。
- 見せた物は使える・画面に説明や確認を足さない(収まらないときの最後の手段は 0.85 倍の縮小まで。省略記号で隠さない区分では、収まるまで伸ばす)。
- 設定の角の 52×52pt を空ける・重ねない(TEST-L16 を壊さない)。
- 浮動小数を本体に持ち込まない(`WidthClass` は整数)。名前の重なり(`WidthClass` など)を SwiftUI の型と重ねない。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(非公開の層の画面の文 — 序・場面・資料 — で擬似言語の写真が切れないことは、統合担当が非公開の層を重ねて確かめる。画面の写真のジョブは公開の層だけなので、非公開の層の文の長さの確かめは `TextWidthTests` を非公開の層を重ねて回して見る。F §4)。
- 回ごとに: 枝の名前・コミットのハッシュ・4 の結果。**「アプリは CI 待ち」**。
- 棚卸しの表(伸ばす/縮める/そのまま)、日本語で区分の上限を超えている文の一覧、切れ検出の id と区分の対応表、設計書と違う判断(擬似言語を縮める区分に当てない点・日本語を失敗にしない点)。
