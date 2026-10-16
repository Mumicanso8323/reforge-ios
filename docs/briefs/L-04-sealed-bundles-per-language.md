# 説明書 L-04: 言語ごとの封

作業の単位: 多言語 L-04(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §6.1〜§6.3・DEC-L5・BRK-07・TEST-L13)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-02(integration-d に入っている。`text/<言語>/` を読む `ContentLoader`・`TextTables`)。土台: integration-d の先頭。
**出す言語は日本語だけのまま**。この単位は封と読み込みの仕組みで、今の非公開の層(`text/ja/` だけ)は、封を分けても**読み込んだ `ContentDB` が 1 つも変わらない**。ほかの言語の訳は作らない。
公開の部分だけを書く。非公開の層の側は 7 の前の「非公開の層の側(統合担当)」。

## 1. 目的
非公開の層の物語の文を、言語ごとに別の封をした束(`text-<言語>.sealed`)にする。言語に依らない部分(`text/` を除く全部)は今の `private.sealed`。起動時に開ける束を言語ごとに数え、**欠けた・壊れた言語はその言語だけが日本語に落ちる**(ほかの言語・世界は動く)。出す言語が決まった後で、ストアの版が「出す言語の束がそろっていなければ作らない」ようにする。

## 2. 作るもの

### 2.1 出す言語の一覧(`RFKernel/Text.swift`)
```swift
extension LanguageID {
    /// 出す言語。別の決定があるまで日本語だけ。ここを増やすのは本人の決め(訳の手配・検収を含む)。
    public static let released: [LanguageID] = [.ja]
}
```
- `shipped`(設計上の 5 言語。対応する言語の候補)は今のまま。`released` は `shipped` の部分集合で `.ja` を含み、`.pseudo` を含まない。
- 新規 `tools/released-languages.py`(python3 標準だけ): `ReForgeCore/Sources/RFKernel/Text.swift` の `released` の行を読み、言語の識別子(`ja`・`zh-Hans` など。`case zhHans = "zh-Hans"` の対応も同じファイルから読む)を 1 行ずつ出す。`--csv` でカンマ区切り。読めなければ終了コード 1。**出す言語の正本はこの Swift の 1 行**で、シェル・CI・project.yml の確かめ(L-11)はこの道具から読む。

### 2.2 封の分け方(`RFContent/ContentSeal.swift`)
```swift
extension ContentSeal {
    public static func textFileName(_ lang: LanguageID) -> String          // "text-ja.sealed"
    /// 層の相対パスが言語の表なら、その言語(text/<コード>/ の下。コードが LanguageID でない・.pseudo のときは nil)。
    public static func textLanguage(ofPath rel: String) -> LanguageID?
    /// 読み込みと同じファイルを、言語に依らない分と言語ごとの分に分ける。
    public static func collectSplit(layer: URL) throws -> (base: [String: Data], text: [LanguageID: [String: Data]])
}
```
- `collect(layer:)` は今のまま残す(全部入りの 1 つ。互換と比べる用)。
- `private.sealed` には `text/<言語>/` の下を入れない。`text-<言語>.sealed` には、その言語の `text/<言語>/…` の全部(`_meta.json` を含む)を、層の相対パスのまま入れる。コードが知らない言語のフォルダは `base` に残す(封の中なので漏れない。rf-seal は件数だけ標準出力に出す)。
- 形は今の `RFS1`(合図 + nonce + AES-256-GCM)のまま。鍵は 1 つ、**束ごとに nonce は変える**(`seal` が毎回乱数を引くので、そのままでよい)。
- **取り違え防止**: `text-<コード>.sealed` を開いたとき、中の全部のパスが `text/<コード>/` で始まらなければ、その束は使わない(`LoadError.sealed`)。`text-en.sealed` を `text-ja.sealed` の名前で置いても受けない。

### 2.3 `rf-seal`(`Sources/rf-seal/main.swift`)
- 引数は今のまま(`rf-seal <層> <private.sealed> <ContentKey.swift> [<art.sealed>]`)。末尾に省略可の `--require-languages <コードのカンマ区切り>` を足す。
- `private.sealed` と同じ場所に `text-<言語>.sealed` を、層に `text/<言語>/` がある言語ぶん作る。**同じ場所の古い `text-*.sealed` は消す**(今 `private.sealed` を消すのと同じ作法)。層が無い・空なら、`text-*.sealed` も全部消す。
- 封をした後、全部の束を開き直して中身が一致すること、**全部の束**に見張りの文字列(`bundle.json` の canary)が平文で無いことを確かめる(今の確かめを束の数だけ)。
- `--require-languages` に挙げた言語の `text/<コード>/` が層に無ければ、終了コード 1(「出す言語の物語の文が非公開の層に無い」。文の中身・ファイル名は出さない)。非公開の層が無い(鍵 nil の公開だけの)ビルドでは要求しない。
- 出力は件数と大きさだけ(言語ごとに 1 行: `rf-seal: 束 ja <件数> ファイル <バイト>`)。鍵・本文は出さない。

### 2.4 読み込み(`RFContent/ContentLoader.swift`)
```swift
public struct BundleReport: Equatable, Sendable {
    public var opened: Set<LanguageID>          // 開けた言語の束
    public var failed: [LanguageID]             // ファイルはあるが開けない・形が違う・取り違え
    public var missing: [LanguageID]            // 求めた言語で、ファイルが無い
}
extension ContentLoader {
    /// loadBundled と同じ中身 + 束の報告。expecting は出す言語(missing の判定にだけ使う)。
    public static func loadBundledReport(root: URL, key: Data?, expecting: [LanguageID] = []) throws
        -> (db: ContentDB, report: BundleReport)
}
```
- `loadBundled(root:key:)` は今の署名のまま残し、`loadBundledReport` の `db` を返す。
- 非公開の層が平文のディレクトリ(`content/private`。開発の手元)のときは今のまま(`text/<言語>/` もそのまま読まれる)。報告は `opened` = 表のある言語、`failed`・`missing` は空。
- 封のとき: `private.sealed` と、**開けた `text-*.sealed` を全部、1 つのメモリ上の層**(`.memory(name: "private", files:)`)にまとめて読む(今と同じ「同じ層の重なりの検査」・同じ「後の層が勝つ」)。
- 言語の束が開けない・形が違う・取り違え → その言語だけ `failed`(読み込みは続ける)。ファイルが無い → `expecting` に入っていれば `missing`。
- **日本語は原文**。封の層があるのに `text-ja.sealed` が `failed` または無いとき(`private.sealed` は開けても物語の文が無い)は、非公開の層ごと使えないものとして `loadBundled` は throw する(今の「封が開けない」と同じ扱い。呼び手が公開の層だけに落とす)。
- 古い形(全部入りの `private.sealed` で `text-*.sealed` が無い)も読めること(`text/` が `private.sealed` の中にあれば今までどおり)。

### 2.5 `GameBootstrap`(`RFPresent/GameBootstrap.swift`)
```swift
public struct ContentLoad: Sendable { public var content: ContentDB; public var sealedFailed: Bool
                                      public var report: BundleReport }
public static func loadContentReport(contentDirectory: URL, key: Data?) throws -> ContentLoad
```
- 既存の `loadContent`・`loadContentFallingBack` は署名を変えず、`loadContentReport` に通す(`expecting` は `LanguageID.released`)。`sealedFailed` の意味は今のまま(封を開けず公開の層だけで起動)。
- 画面の帯に「この言語の物語の文がまだ無い」を出すのは **この単位の外**(L-10b 以降の画面の担当。日本語だけの今は出ない)。ここは数を返すだけ。

### 2.6 `stage.sh` と `ci.yml`
- `tools/content/stage.sh`: rf-seal を呼ぶとき、`--require-languages` に **ストアの版(環境変数 `REFORGE_STORE_BUILD=1`)なら `tools/released-languages.py --csv`、それ以外は `ja`** を渡す。束は `AppContent/content/` に `private.sealed`・`text-*.sealed`・`art.sealed` として並ぶ。
- `stage.sh` は、公開の層の写し(`AppContent/content/public/`)から、**出す言語に入っていない言語の `text/<コード>/` を消す**(`content/public/text/en/` などの試験用の途中の表が ipa に入らないように)。`content/public` そのものは触らない。
- 「平文の `private` が束に紛れていない」の確かめに、「`AppContent/content/text/` が無い」を足す。
- `ci.yml`:
  - `testflight` ジョブの `tools/content/stage.sh` の step に `env: REFORGE_STORE_BUILD: "1"`(ほかのジョブには付けない)。
  - `ios` と `testflight` の「Package ipa」「ipa の確かめ」で、非公開の層があるとき(`content/private/bundle.json` があるとき。今の canary の確かめと同じ条件)、**出す言語ごとに `$APP/content/text-<コード>.sealed` がある**ことを確かめる。`$APP/content/text/`(平文)が無いことも。
  - `app-switches` ジョブに `python3 tools/test_released_languages.py`(2.7)を 1 step。
  - release の名前・タグ・ipa の名前・dev の URL は変えない。ほかの step は変えない。

### 2.7 `tools/test_released_languages.py`(新規。`test_check_public_spoilers.py` と同じ unittest)
- 一時ディレクトリに作った小さな `Text.swift` の見本で、`released` の読み取り(1 言語・複数・`zh-Hans` の対応)と、読めないときの失敗。本物の `Text.swift` を読ませ、出力が `ja` だけであること(出す言語を増やすときに意図して直すテスト。メッセージに「出す言語を変えるのは本人の決め」と書く)。

## 3. テスト(`ReForgeCore/Tests/RFContentTests/SealedBundlesTests.swift` を新規)
1. `collectSplit`: `world.json`(言語に依らない)・`text/ja/a.json`・`text/ja/_meta.json`・`text/en/a.json`・`text/xx/a.json`(知らない言語)の見本の層で、`base` に `world.json` と `text/xx/a.json`、`text[.ja]` に 2 つ、`text[.en]` に 1 つ。`.pseudo` のフォルダは `base`。
2. **同じ中身**: 見本の層を、(a) 平文の層として `load(layers:)`、(b) `private.sealed` + `text-ja.sealed` + `text-en.sealed` にして `loadBundled(root:key:)` で読む、の 2 つが `ContentDB` として等しい。古い形(全部入りの `private.sealed`)でも等しい。公開の層との重ね(同じ ID の上書き)も同じ結果。
3. 欠け: `text-en.sealed` を消すと、`expecting: [.ja, .en]` で `report.missing == [.en]`、英語の行は `lookup` が `.fallback(日本語)`、日本語と世界は変わらない。`expecting` に無ければ `missing` は空。
4. 壊れ: `text-en.sealed` の 1 バイトを変える → `report.failed == [.en]`、読み込みは成功。鍵違いも同じ。**`text-ja.sealed` を壊す・消す → `loadBundled` が throw**、`GameBootstrap.loadContentFallingBack` は公開の層だけで `sealedFailed == true`。
5. 取り違え: `text-en.sealed` の中身を `text-ja.sealed` の名前で置く → `ja` が `failed`(→ 4 と同じ扱い)。
6. 平文が無い: 全部の束のバイト列に、見本の文(`text/ja/a.json` の文の一部)が平文で現れない。束ごとに先頭の nonce(合図の次の 12 バイト)が違う。
7. 作法: `rf-seal` と同じ手順(関数で。CLI は 4 で手で確かめる)で、古い `text-fr.sealed` が残っている出力先に書くと消える。層が空なら全部消える。
8. `LanguageID.released == [.ja]`(出す言語を変えるときは本人の決めで、このテストを直す)。`released` ⊂ `shipped`・`.ja` を含む・`.pseudo` を含まない。
9. `TestContent.full()` が非公開の層を持つ環境(統合担当の環境)では、**実際の層を `collectSplit` → 封 → `loadBundled` した `ContentDB` が、`load(layers:)` と等しい**(非公開の層が無ければ `XCTSkip`)。Codex の作業場では飛ばされる。

## 4. 確かめのコマンド(hub のみ)
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFContentTests|RFPresentTests'
python3 tools/test_released_languages.py
python3 tools/released-languages.py --csv                 # ja
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
bash -n tools/content/stage.sh
```
- rf-seal の手元の確かめ(一時ディレクトリで。コミットしない): 見本の層(`text/ja/`・`text/en/` を持つ)を作り、`swift run --package-path ReForgeCore rf-seal <層> <out>/private.sealed <out>/ContentKey.swift --require-languages ja` が `private.sealed` と `text-ja.sealed`・`text-en.sealed` を作り、`--require-languages ko` で終了コード 1 になること。出力の 1 行ずつを報告に貼る。
- 全体のテストは回さない。**note には ssh しない・`rf-note-test` は使わない**。docker は `rf-swift-slot` 経由・`--cpus=3`・`-j 3`。
- ipa の確かめ(ci.yml の追加の step)と stage.sh の実走は macOS の CI(ci/integration の手動起動)で統合担当が回す。報告に「CI 待ち」と書く。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFKernel/Text.swift`(`released` の 1 行)、`ReForgeCore/Sources/RFContent/`(`ContentSeal.swift`・`ContentLoader.swift`)、`ReForgeCore/Sources/rf-seal/main.swift`、`ReForgeCore/Sources/RFPresent/GameBootstrap.swift`、`ReForgeCore/Tests/RFContentTests/`、`tools/released-languages.py`・`tools/test_released_languages.py`(新規)、`tools/content/stage.sh`、`.github/workflows/ci.yml`(2.6 の step だけ)、`docs/architecture/E-content.md` §4.5(封の説明を新しい形に)。
- 触らない: アプリ(`ReForge/`)・`content/`(公開の層の文言も)・`content/private`・`project.yml`(L-11)・保存の形・`ArtSeal`(絵の封)・release の名前とタグ。

## 6. 約束(F §4)
- 公開リポジトリに物語の語を書かない(テストの文は一般の語と ID だけ)。
- 鍵・本文・見張りの文字列を標準出力・ログに出さない(件数と大きさだけ)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない(開発者向けのエラーは日本語でよい)。
- 出す言語を日本語から増やさない。`content/public/text/` に他の言語の文を足さない。

## 非公開の層の側(統合担当)
Codex は触れない。マージの前に統合担当が、非公開の層(`reforge-content`)を重ねて行う。物語の語はここにも書かない。
1. **同じ読み込みの確認**: 手元で非公開の層を重ね、3 の 9 を走らせる(実際の層で、平文の読み込みと「封を分けた読み込み」の `ContentDB` が等しいこと)。等しくなければ、`text/` の下に言語の印の無い・食い違うファイルがある。直すのは非公開の層の側(`"language"` の印か置き場所)。
2. **生成器(U14)**: 出力先は今の `text/ja/`(`b.T(…, path="text/ja/…")`)のままでよく、変更は要らない。`text/<言語>/` の追加は L-07・L-08 の仕事(この単位では作らない)。`l10n/` は封にも読み込みにも入らない(L-02 の約束のまま)。
3. **CI の非公開の層のジョブ**(`core` の `private`)と `ios`・`testflight` のジョブで、`text-ja.sealed` ができ、ipa に入ること。dev の ipa の大きさが物語の文の分だけ(`private.sealed` から移った分)で、増えていないこと。
4. **見張りの文字列**: 非公開の層の `bundle.json` の canary が、どの束にも平文で出ないこと(rf-seal が確かめる)。
5. **途中の公開の表**: `content/public/text/` の途中の他言語の表(試験用)は、`released` に入るまで ipa に入らない(stage.sh が消す)。ストアの版で消えていることを `ls` で確かめる。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(上の「非公開の層の側」を統合担当が回す)。
- 枝の名前・先頭のハッシュ・4 の結果(件数・失敗・飛ばし)と、rf-seal の手元の確かめの出力。
- ipa の確かめ・`stage.sh` の実走は CI 待ち。設計書と違う判断(とくに、日本語の束が壊れた時の扱い・取り違えの判定)。
