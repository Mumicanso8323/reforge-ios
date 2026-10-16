# 説明書 L-06: テストを日本語から外す

作業の単位: 多言語 L-06(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §13・BRK-25/32・TEST-L9/L11/L12)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-03(段 A〜C が入っていること。`Perceiver(language:)`・`GameHost.setLanguage`・`lastRejection`・`GameStore.noticeRef`)。L-05 の `PerceptionAuditor` の言語対応があれば 2.4 の監査が言語ごとになる(無くても進められる)。土台: integration-d の先頭。
**出す言語は日本語だけのまま**。この単位はテストと検査の道具だけで、ゲームの挙動も画面も変えない。他の言語の訳は作らない(擬似言語はテスト用の機械的な変形で、訳ではない)。
2 回の Codex 実行に分ける: **第 1 回 = 2.1〜2.3(本体のテストの書き換えと静的な検査)、第 2 回 = 2.4〜2.5(擬似言語の通し・アプリ側のテスト)**。

## 1. 目的
決まりを確かめるテストが、日本語の文の字面に頼っている(日本語の文を直すと壊れ、他の言語では意味が無い)。決まりの確かめは **`TextRef` か ID** で比べ、日本語の文で比べてよいのは「日本語の表を引いて組む」こと自体を確かめるテストだけにする(そのテストは言語を `.ja` と明示して、印を付ける)。あわせて、擬似言語で通しを回して「表を通らずに出た文」を機械で見つけられるようにする。

## 2. 作るもの

### 2.1 棚卸し(最初にやる。結果を報告に貼る)
- `ReForgeCore/Tests/**`・`ReForgeTests/**`・`ReForgeUITests/**` で、**日本語(かな・漢字)の文字列リテラルを期待値にして比べている行**を数える(`XCTAssert*` の呼び出しで、最後の引数の「失敗のときの文」は数えない)。ファイルごとの件数の表を作り、各行を 3 つに分ける:
  - (a) **仕組みの確かめ**(理由・名前・段の言葉が正しく出るか。`TextRef`/ID で比べるべき物)。
  - (b) **日本語の表を引くこと自体の確かめ**(例: `{n}` の差し込み・名前の並べ方・単位。`.ja` と明示して残す物)。
  - (c) **内容の期待値としての日本語**(試験用の内容の中の物で、ID と対で書いてある物など。残してよい理由を 1 行)。
- 手がかり(今の数の目安。設計書の見積もりより多い): 日本語リテラルのある `XCTAssert*` の行が全体で約 630 行・86 ファイル(失敗の文を含む粗い数)。多いのは `RFPresentTests/MapPresentTests.swift`・`RFPerceptionTests/PerceptionTests.swift`・`RFProductionTests/ProductionSystemTests.swift`・`RFPresentTests/OpeningDisclosureTests.swift`・`RFCrewTests/CrewSystemTests.swift`。

### 2.2 比べ方の道具(`RFTestSupport/TestSupport.swift`)
```swift
public enum TestText {
    /// 文言の参照を、その言語で組んだ文にする(期待値を表から作る。リテラルを書かない)。
    public static func render(_ id: TextID, _ args: [String: TextArg] = [:],
                              content: ContentDB, language: LanguageID = .ja) -> String
    /// 仕組みのテストを回す言語: 日本語・擬似言語・(出す言語で、表がそろっている物)。今は [.ja, .pseudo]。
    public static func languages(for content: ContentDB) -> [LanguageID]
}
public enum PseudoCheck {
    /// 擬似言語で組んだ Frame の文字列のうち、「表を通らずに出た」物を返す(2.4)。
    public static func unwrapped(_ strings: [String]) -> [String]
}
```
- `languages(for:)` は、`[.ja, .pseudo]` に、`LanguageID.released`(L-04)と `content.textTables.available` の両方に入る日本語以外の言語を足す。`released` が日本語だけの今は `[.ja, .pseudo]`。

### 2.3 テストの書き換えと、戻らない仕掛け
- (a) の行を、`TextRef` の比較(`host.lastRejection == TextRef("reason.…")`・`frame` の持つ ID の比較)か、`TestText.render(…)` で作った期待値との比較にする。**同じテストを `TestText.languages` の全部の言語で回せる形**にできる物は、言語のループで回す(`GameHost(language:)`・`FrameBuilder.language` を言語に合わせる)。
- (b) の行は、そのテストの先頭で言語を `.ja` と明示し(`Perceiver(language: .ja)` など)、期待値の行(か直前の行)に `// ja-table` の印を付ける。
- (c) は残してよい。理由が 1 行で書けない物は (a) にする。
- **ratchet の検査**(新規 `tools/check-test-text-literals.py`。python3 標準だけ): 上の数え方でファイルごとに「印の無い日本語の期待値の行」を数え、`tools/test-text-literals.baseline.json`(ファイル → 件数。**この単位の最後の数を書く**)と比べる。件数が増えたファイル・基準に無い新しいファイルで 1 件でもあれば終了コード 1(ファイルと件数だけ出す)。件数が減ったら「基準を下げよ」と出す(失敗にはしない)。`RFPresentTests`・`RFPerceptionTests`・`AcceptanceTests`・`ReForgeTests` の基準は **0 を目標**にする(0 にできない行は (c) として理由を `// ja-ok: <理由>` の印で示す。印のある行は数えない)。
- `ReForgeCore` の画面向けの文の静的な確かめ(TEST-L11。新規 `tools/check-core-strings.py` と `tools/core-strings-allow.json`): `ReForgeCore/Sources/RFPresent`・`RFPerception` の `*.swift` で、コメントを除いた**文字列リテラルにかな・漢字・ハングルが含まれる行**を探す。許す物は `core-strings-allow.json`(ファイル → リテラルの配列)に書いた物だけ: 開発者向けの 2 ファイル(`RFPerception/HintAudit.swift`・`RFPerception/ForbiddenAudit.swift`。ファイルごと)と、開発用の印「？」。矢印・記号(かな・漢字・ハングルを含まない字)は対象外。許可の一覧に無い物があれば終了コード 1(ファイル:行だけ出す)。L-03 の後なので今は一覧だけで通る。
- `ci.yml` の `app-switches` ジョブに 2 つの検査を 1 step ずつ足す(`check-store-metadata.py` の次。ほかの step は変えない)。

### 2.4 擬似言語で通しを回す(TEST-L9。第 2 回)
- **構造**: `PseudoCheck.unwrapped(strings)`: かな・漢字・ハングルを含み、書記素が 2 つ以上の文字列で、`⟦` で始まり `⟧` で終わらない物を返す(1 書記素の文字列は地図の字なので除く。ID・色の名前などの ASCII や記号の文字列は対象外)。
- **走らせ方**: 公開の層で毎回回る既存の通しのテスト(`AcceptanceTests` の中から 1 つ選ぶ。無ければ、`GameHost` で 30 分(ゲーム内)の間 `tick` と代表的なコマンドを送る短い通しを新規に書く)を、`GameHost(language: .pseudo)` で回し、**1 歩ごとの `Frame` の全文字列**(`FrameText.allStrings`)に `PseudoCheck.unwrapped` が空であること。非公開の層を重ねたとき(`REFORGE_TENMIN_BOT=1` の既存の通し。env の決まりは今のまま)も、擬似言語の回を 1 つ足す(非公開の層が無ければ飛ばす)。
- **走行中の監査**(BRK-32): 同じ通しに `PerceptionAuditor` を付け、`TestText.languages` の全部の言語で違反 0。静的な監査は L-05 の `auditAll`(全言語)で、ここでは呼ぶだけ。
- 「見つかる」ことの確かめ(あえて壊す): テストの中で、表を通さない文字列(日本語のリテラル)を 1 つ `Frame` の文字列に混ぜた見本を作り、`unwrapped` がそれを返すこと。
- 切り替えの途中: 通しの途中(序・決断・断りがある時)で `setLanguage(.pseudo)` → `setLanguage(.ja)` を呼んでも、世界の保存のバイト列が変わらないこと(L-03 の試験の拡張。通しの途中の状態で)。

### 2.5 アプリ側のテスト(第 2 回。macOS の CI で回る)
- `ReForgeTests/AppTests.swift` の `store.notice == "まだ昼だ"` は、`store.noticeRef == TextRef("reason.time.still_day")`(L-03 で `noticeRef` になっている)。ほかの日本語の期待値も 2.1 の分け方で直す。
- `ReForgeUITests/*.swift` の日本語のラベルで要素を探している所(`ScreenSnapshotTests`・`LayoutFitTests`・`PrologueSceneTests` など)は、`accessibilityIdentifier` で探す形に直す。識別子が無い要素は、画面のファイルに `.accessibilityIdentifier("…")` を足してよい(**見た目・配置・読み上げのラベルは変えない**)。ラベルの文字そのものを確かめるのが目的のテストだけ、`// ja-table` で残す。
- 直せない物は報告に一覧で書く(ファイル・行・理由)。アプリ側は Codex の作業場では回せない。型検査と静的な検査(`check-app-switches.py`・`check-app-names.py`)で守り、**CI 待ち**と書く。

## 3. テスト(この単位が足すテスト)
1. `RFTestSupportTests` 相当(`RFPresentTests` に置いてよい): `TestText.render` が引数つきの文を組む、`languages(for:)` が `[.ja, .pseudo]`(`released` が日本語だけのとき)、`PseudoCheck.unwrapped` が (i) 囲まれた文 → 空、(ii) 囲まれていない日本語 → 返す、(iii) ASCII の ID・1 書記素の字・記号 → 返さない。
2. 2.4 の通し(擬似言語・全言語の走行中の監査・あえて壊した見本・切り替えの途中)。
3. 検査の道具の試験: `tools/test_check_test_text_literals.py`(一時ディレクトリに作った見本のテストファイルで、印あり/なし・失敗の文・件数の増減・基準に無いファイルを確かめる)と `tools/test_check_core_strings.py`(許可の一覧の内外・コメント・記号)。`ci.yml` の `app-switches` に 1 step ずつ。
4. 既存のテストは、書き換えた分を除いて全部通る。書き換えたテストが**日本語の表を差し替えても通る**(例: `TestText.render` の元の表の文を変えても、仕組みのテストは壊れない)ことを、代表の 1 本で確かめる(テストの中で表をメモリ上で差し替える)。

## 4. 確かめのコマンド(hub のみ。関わるテストだけ)
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift build -j 3 --build-tests --package-path ReForgeCore
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFPresentTests|RFPerceptionTests|AcceptanceTests|RFCrewTests|RFProductionTests'
python3 tools/check-test-text-literals.py
python3 tools/check-core-strings.py
python3 tools/test_check_test_text_literals.py
python3 tools/test_check_core_strings.py
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```
- 書き換えたテストのあるモジュールを `--filter` に足す(棚卸しの表のモジュール)。全体のテストは回さない(統合担当がマージのときに回す)。**note には ssh しない・`rf-note-test` は使わない**。docker は `rf-swift-slot` 経由・`--cpus=3`・`-j 3`。
- アプリ側(2.5)は macOS の CI(ci/integration の手動起動)で統合担当が回す。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Tests/**`(書き換え)、`ReForgeCore/Sources/RFTestSupport/`、`ReForgeTests/**`・`ReForgeUITests/**`(2.5)、`ReForge/Sources/**` の `accessibilityIdentifier` の追加だけ(2.5)、`tools/check-test-text-literals.py`・`tools/check-core-strings.py`・それぞれの試験と基準・許可の一覧(新規)、`.github/workflows/ci.yml`(`app-switches` の step の追加だけ)、`docs/architecture/F-work-units.md` §4 に 2 行(テストの比べ方の規則: 決まりの確かめは `TextRef`/ID。日本語の文で比べるテストは `// ja-table`)。
- 触らない: ゲームの挙動を変える本体のコード(テストが壊れたからと本体を直さない。壊れたら報告に書く)・画面の見た目・`content/`・封(L-04)・禁止語の照らし方(L-05)。

## 6. 約束(F §4)
- 公開リポジトリに物語の語・人の名前を書かない(期待値は表から作る。リテラルを書くのは一般の語と ID だけ)。
- 画面に、確認のダイアログ・説明・理由の文を足さない(識別子の追加だけ)。
- テストを通すために期待値を甘くしない(増やした分は ratchet の基準に出る)。
- 浮動小数を使わない。名前の重なり(`TestText`・`PseudoCheck`)をアプリや Foundation の型と重ねない。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(非公開の層を重ねたとき、書き換えたテストと擬似言語の通しが通ることを統合担当が確かめる。F §4)。
- 回ごとに: 枝の名前・コミットのハッシュ・4 の結果(件数・失敗・飛ばし)。
- 棚卸しの表(ファイルごとの (a)(b)(c) の件数)、基準の最後の数、`// ja-ok` を付けた行の一覧、擬似言語の通しで見つかった「表を通らずに出た文」(あれば。直すのは L-03/L-11 の持ち主なので、場所だけ書く)、2.5 で直せなかった物。
