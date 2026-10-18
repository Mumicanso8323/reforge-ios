# 説明書 L-05: 言語ごとの禁止語と公開の検査(話し手の範囲 `scope` を含む)

作業の単位: 多言語 L-05(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §4.4・§9.1〜§9.3・BRK-16/17/32/36・RISK-L1/L5・TEST-L5/L6/L17)。話し手の範囲 `scope` はリーダーの追加(docs/briefs/README.md の列の注)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-02(入っている)と **L-03 の段 A**(`Perceiver(language:)`。言語ごとの監査が使う)。土台: integration-d の先頭。
**出す言語は日本語だけのまま**。他の言語の語・訳は作らない。この単位は検査の仕組みで、今の日本語の配列の規則・今の公開の検査の結果は**1 つも変わらない**。
公開の部分だけを書く。語そのものは非公開の層にしか無い(7 の前の「非公開の層の側(統合担当)」)。
大きいので **2 段**: 段 A = Swift(禁止語・監査・scope・代名詞)、段 B = `tools/check-public-spoilers.py`。1 段 = 1 回の Codex 実行 = 1 コミット。段 B は段 A と独立(先でも並行でもよい)。

## 1. 目的
- 禁止語の表を言語ごとにする(日本語の配列は「日本語の語」と読む)。照らし方は言語で変える: 日本語・中国語(両方)・韓国語は部分一致、英語は小文字にそろえて単語の境目で(「ore」の規則が「more」に当たらない)。
- 英字の内部 ID の漏れの検査を言語ごとにする(英語の文では「英字を見たら疑う」が成り立たない)。
- 規則に **話し手の範囲 `scope`** を持てるようにする(例: ある人物の行と地の文だけを照らし、ほかの人の行は照らさない)。今は生成の側でその範囲に限って照らしている。エンジンの側で同じことを宣言できるようにする。
- 代名詞の規則 `pronounRules`(真実の規則とは別。開かない)と、その検査を作る。
- 公開の検査(`check-public-spoilers.py`)を言語ごとの語の表に開く。英語は大文字で始まる固有名だけを照らす(小文字の一般語は公開のコードの識別子・コメントに普通に出る)。

## 2. 作るもの

### 段 A: Swift

#### 2.1 言語ごとの語(`RFContent/Schema/Perception.swift`)
```swift
public struct LanguageWords: Codable, Equatable, Sendable {
    public var byLanguage: [LanguageID: [String]]
    public init(_ words: [String])                                    // 日本語として
    public init(byLanguage: [LanguageID: [String]])
    public subscript(_ lang: LanguageID) -> [String] { get }          // 無ければ []
    public var ja: [String] { get set }
}
```
- JSON は 2 通りを受ける。**配列 = 日本語**。**オブジェクト = 言語の識別子 → 配列**(`ja`・`en`・`zh-Hans`・`zh-Hant`・`ko`)。`x-pseudo` や知らない鍵は読み込みの誤り(語は誤りの文に入れない)。書き出しは、日本語だけなら配列、それ以外はオブジェクト。
- `ForbiddenRule`: `words` を `LanguageWords` で持つ。`var words: [String]`(= 日本語の語。get/set)と `init(id:words:until:strict:)` は**残す**(今の呼び出しと試験がそのまま動く)。`init(id:words: LanguageWords, …)` を足す。`id`・`until`・`strict` は言語で共通。
- `ContentDB.latinAllowed`(許す英字の語)も `LanguageWords` で持つ(`latinAllowed: [String]` は日本語の語の get/set として残す)。読み込みは配列(日本語)かオブジェクト。層の重なりは今と同じ(同じ語を重ねない・`remove` の `latinAllowed` は全部の言語から消す)。
- 規則の `remove`(`forbidden` を名札で消す)は今のまま。

#### 2.2 規則に話し手の範囲(`ForbiddenRule.scope`)
```swift
public struct ForbiddenScope: Codable, Equatable, Sendable {
    public var speakers: [PersonID]     // この人が言う行(場面の行の話し手・一言の話し手)。既定 []
    public var narration: Bool          // 話し手のいない場面の行(地の文)。既定 false
    public var other: Bool              // 上のどれでもない文言(名前・説明・画面の文・ノート・資料…)。既定 false
}
// ForbiddenRule.scope: ForbiddenScope?   無ければ今までどおり「全部の文言」
```
- `scope` があるときは、**列挙した範囲の文言にだけ**その規則を当てる。範囲の決め方(`RFPerception` に新しい型 `TextVoice` と `TextVoices.of(_ content:) -> [TextID: Set<TextVoice>]`):
  - 場面(`SceneDef.lines`)の行: `speaker` があれば `.person(話し手)`、無ければ `.narration`。一言(`LineDef`)は `.person(speaker)`。
  - 上以外が指す文言(認識の表・出来事・ヒント・目標・資料・所見・失敗の理由…。`ContentValidator.nonPerceptionTextRefs` の場面・一言以外の分と認識の表)と、どこからも指されていない文言は `.other`。同じ ID が場面の行と別の所の両方から指されていれば、両方の範囲に入る。
- 言語に依らない(ID の範囲)。どの言語の文も、同じ ID は同じ範囲で照らす。
- 走行中の監査(`PerceptionAuditor.inspect`)に `textID: TextID? = nil` を足す。`Perceiver.text(_:)`・`render(_:)` は一番外側の ID を渡す。ID が無い(名前・地図の字などの)文は `.other`。静的な監査も同じ範囲で照らす。
- 検証(`ContentValidator`): `forbidden.scope`(warning)— `speakers` に知らない人がいる。`forbidden.scope.empty`(error)— `speakers` が空で `narration`・`other` も false(何にも当たらない規則)。

#### 2.3 言語ごとの照らし方(`RFPerception`)
```swift
public enum WordMatcher {
    /// ja・zh-Hans・zh-Hant・ko・pseudo(日本語の文を変形した物): NFC にそろえた部分一致。
    /// en: 小文字にそろえ、空白の連なりを 1 つにし、前後が文字・数字でない所だけ(語の境目)で一致。
    public static func contains(_ text: String, word: String, language: LanguageID) -> Bool
}
```
- 英語の語は形を全部並べる前提(単数・複数・動詞の形)。語に空白があれば句として照らす。`ore's` の `'` は境目。
- 擬似言語の文は、日本語の語と部分一致で照らす(`⟦…⟧` の囲みと「・」の足しは語に当たらない)。

#### 2.4 英字の内部 ID の漏れ(`ForbiddenAudit.looksLikeInternalID`)
- `looksLikeInternalID(_ text: String, allowed: [String], language: LanguageID = .ja)`。日本語・中国語・韓国語は**今のまま**(許した語を除いて `[a-z]{3,}|_` があれば疑う。許す語は `latinAllowed[language]`)。
- 英語(と擬似言語を英語として使うときは使わない): `{…}` を除いた後、**ID の形**だけを疑う: 下線を含む小文字の連なり、または点でつながった小文字の連なり(`ui.title`・`a_b`)。点の区切りの各部分が 1 字だけのもの(`e.g`)は疑わない。大文字を含む語・普通の単語は疑わない。
- `check`・`audit` が文の言語の `latinAllowed` を渡す。

#### 2.5 言語ごとの監査(`ForbiddenAudit`)
- `check(…, language: LanguageID = .ja)`: その言語の語(`rule.words[language]`。擬似言語は日本語の語)で照らす。`Violation` に `language`(既定 `.ja`)を足す。`description` は日本語のとき今と同じ形、他の言語のときは `[段/言語]` にする。語と文は伏せる決めのまま。
- `audit(_ content:, language: LanguageID = .ja)`: `visibleTexts` を `Perceiver(language:)` と、その言語の表(`textTables.tables[language]`)で作る。**その言語の表に無い ID は照らさない**(日本語に落ちた文は日本語の回で照らされている)。範囲(`scope`)は 2.2。
- `auditAll(_ content:) -> [LanguageID: [Violation]]`: 表のある全部の言語(擬似言語を除く)で回す。
- 規則ごとの語の検査(`ContentValidator`): `forbidden.languages`(error)— `LanguageID.released` の各言語に、全部の規則で語が 1 つ以上ある。出す言語に入っていない言語で、表はあるのに語が無い規則は `forbidden.languages.partial`(warning)。`ContentValidator.validate` は試験のために `released: [LanguageID] = LanguageID.released`(L-04 で作る)を引数に取れること。
- `HintAudit` の気配の検査は日本語のまま(変えない)。

#### 2.6 代名詞の規則(§4.4。TEST-L17)
```swift
public struct PronounRule: Codable, Equatable, Sendable {
    public var id: String
    public var about: PersonID
    public var error: LanguageWords      // 当たれば止める語
    public var review: LanguageWords     // 当たれば止めずに別系統の見直しの列に回す語
}
public enum PronounAudit {
    public enum Severity: Sendable { case error, review }
    public struct Finding: Hashable, Sendable { public var rule: String; public var text: TextID
                                                public var language: LanguageID; public var severity: Severity }
    public static func check(_ content: ContentDB, language: LanguageID) -> [Finding]
}
```
- 読み込み: `forbidden` と同じファイルに `"pronounRules": [...]` を置ける(`ContentDB.pronounRules`。重なりは名札で後の層が勝つ。`remove` の `pronounRules` は名札で消す)。**禁止語の監査の段にも `ForbiddenAudit` にも入れない**(どこにでも出る一般語)。
- 照らす文の印: 文言の表のファイル(日本語の表)に省略できるキー `"about": {"<文言の ID>": ["<人の ID>" または "*"]}`(`textGates` と同じく日本語の表にだけ書く。日本語以外の表に書けば読み込みの誤り)を足す。`ContentDB.textAbout`。`"*"` は「人を差し込む型(誰でもありうる)」の意味で、その文では `review` の語も `error` として扱う。
- `check`: 規則ごとに、`about` にその人(または `*`)がある文言のうち、**その言語の自分の表にある文**を `WordMatcher` で照らす。見つけた分だけ `Finding`(語も文も持たない。規則の名札・文言の ID・言語・重さだけ)。
- 検証: `pronoun.about`(warning)知らない人、`textAbout.text`(warning)表に無い ID、`textAbout.language`(error)日本語以外の表の `about`。

### 段 B: 公開の検査(`tools/check-public-spoilers.py` と `tools/test_check_public_spoilers.py`)
- `load_rules`: `rule["words"]` が**配列なら今のまま**(言語を問わず今の照らし方)。**オブジェクトなら**言語ごとに読む: `ja`・`zh-Hans`・`zh-Hant`・`ko` は今の語と同じ扱い(部分一致。ラテン文字を含む語は今の境目の規則)、`en` は**大文字の英字で始まる語だけ**を集める(小文字で始まる語は捨てる。大文字小文字は区別し、前後が英数字・`_` でないときだけ当たる=今のラテン語の規則)。知らない言語の鍵は `SystemExit("tools/… の形が違う(言語の鍵)")`(語は出さない)。
- `tools/public-words.json` の `publicOnlyWords` も、配列(今のまま)かオブジェクト(上と同じ)。`publicOnlyPatterns`・`publicOnlyIdentifiers`・`identifierExceptions` は今のまま(言語に分けない)。
- `pronounRules`・`scope`・`latinAllowed` など**ほかのキーは読まない**(代名詞の語は公開の検査に入れない)。
- 終了時の 1 行は語の数に言語ごとの内訳を足す(`語 N(ja a・en b・…)`)。当たりは今どおり「ファイル:行」と件数だけ。語・前後の文は出さない。
- `test_check_public_spoilers.py` に足す(語は `zorb` の類の合成語。物語の語を書かない):
  1. オブジェクトの `ko` の語が、助詞の付いた文(`語 + 을`)に部分一致で当たる。`zh-Hans` も部分一致。
  2. `en` の小文字の語(`ore` 相当の合成語)は、`more` 相当の文にも `ore` そのものの文にも**当たらない**。`en` の大文字の語は当たる(単語の境目で。`Zorbleft` は当たり、`Zorblefty` と `xZorbleft` は当たらない)。
  3. 配列は今のままの結果(既存のテストが全部通る)。
  4. `pronounRules` だけを持つファイルでは何も当たらない。
  5. 知らない言語の鍵で終了コードが 0 でなく、出力に語が出ない。
  6. 当たりの出力に語が出ない(オブジェクトの形でも)。

## 3. テスト(段 A。`ReForgeCore/Tests/RFPerceptionTests/ForbiddenLanguageTests.swift` と `RFContentTests/LanguageWordsTests.swift` を新規。語は合成語・一般語だけ)
1. `LanguageWords` の読み書き: 配列 = 日本語、オブジェクト、`x-pseudo`・知らない鍵は throw(誤りの文に語が無い)、往復。`rule.words` と `init(id:words:until:strict:)` が今のまま。
2. `WordMatcher`: 英語で `ore` が `more` に当たらず `Ore.`・`ore's`・`iron  ore`(空白 2 つ)で当たる。日本語の NFC 分解形。韓国語の助詞つき。中国語の部分一致。擬似言語の文で日本語の語が当たる。
3. `looksLikeInternalID` の英語: `ui.title`・`a_b` は疑う、`Iron ore.`・`e.g. this`・`It's fine` は疑わない。日本語・中国語・韓国語は今のテストが全部通る(動かしていない)。
4. 言語ごとの監査: 試験用の内容(テストの中で作る)に、日本語の表と英語の表(同じ ID)があり、規則の `words` が `{"ja": […], "en": […]}` のとき、英語の表の文だけが `en` の語で当たり、日本語の表の文は `ja` の語で当たる。`auditAll` が言語ごとに返す。**英語の表に無い ID は英語の回で照らされない**。
5. **規則ごとの全言語の語**(TEST-L5): `validate(db, released: [.ja, .en])` で、英語の語が無い規則が `forbidden.languages`(error)。`released: [.ja]` なら出ない。公開の層は error 0。
6. `scope`: 規則を「人 A と地の文」に絞ると、(a) A の行・地の文の行は当たる、(b) 人 B の行は当たらない、(c) 認識の表の名前に使われた文は当たらない、(d) `other: true` なら (c) も当たる、(e) 場面の行と別の所の両方から指された ID は (c) の側にも入る。走行中の監査(`PerceptionAuditor` を付けた `Perceiver.text`)と静的な監査が同じ結果。範囲の検証 2 つ。`scope` の無い規則は今のまま全部に当たる。
7. 代名詞(TEST-L17。合成の人 `person.test.a`): 英語で「they are」は通り、`error` の語の文は error、`"*"` の文で `review` の語を含むと error、`about` が A の文で `review` の語は review の列、別の人の文は照らさない。日本語の表の `review` に当たる文が review に出る。`pronounRules` の語が `ForbiddenAudit` と静的な監査に混ざらない。`about` を日本語以外の表に書くと読み込みの誤り。
8. 既存のテストは全部、直さずに通る(日本語の配列の規則・`latinAllowed` の配列・`ForbiddenRule(words:)`)。

## 4. 確かめのコマンド(hub のみ)
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFPerceptionTests|RFContentTests|RFPresentTests'
python3 tools/test_check_public_spoilers.py
python3 tools/check-public-spoilers.py
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
```
- 全体のテストは回さない。**note には ssh しない・`rf-note-test` は使わない**。docker は `rf-swift-slot` 経由・`--cpus=3`・`-j 3`。
- 段 B の確かめは Linux の python だけ(macOS の CI は要らない)。段 A の `PerceptionAuditor` の引数の追加がアプリを壊さないこと(`inspect` の既存の呼び出しが変わらないこと)は、既定値で守る。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFContent/`(`Schema/Perception.swift`・`ContentDB.swift`・`ContentLoader.swift`・`ContentValidator.swift`)、`ReForgeCore/Sources/RFPerception/`(`ForbiddenAudit.swift`・`Perceiver.swift` の監査の呼び出しだけ・新規 `WordMatcher.swift`・`TextVoices.swift`・`PronounAudit.swift`)、`ReForgeCore/Tests/RFPerceptionTests/`・`RFContentTests/`、`tools/check-public-spoilers.py`・`tools/test_check_public_spoilers.py`、`docs/architecture/E-content.md` §5.2(語の表の形を書き足す)。
- 触らない: `content/`(公開・非公開の層。語を足さない)・アプリ(`ReForge/`)・`HintAudit` の中身・封(L-04)・保存の形・`tools/public-words.json`(非公開の層)。

## 6. 約束(F §4)
- 公開リポジトリに物語の語・人の名前を書かない。テストの語は合成語(`zorb`・`ore`・`iron ore` の類)と一般の代名詞・単語だけ。
- 違反・当たりの出力に、語と前後の文を出さない(規則の名札・ID・ファイル:行・件数だけ)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない。
- 浮動小数を使わない。名前の重なり(`WordMatcher`・`TextVoice`・`LanguageWords` など)をアプリ・SwiftUI・Foundation の型と重ねない(`check-app-names.py`)。
- 他の言語の語・訳を作らない(訳の手配は本人の決め)。

## 非公開の層の側(統合担当)
Codex は触れない。非公開の層(`reforge-content`)に次を足すのは統合担当(と U14。L-09 の仕事)。ここにも語・人の名前は書かない。
1. `perception/forbidden.json` の `words`: 今の配列は**そのまま日本語として有効**。他の言語の語を足すのは、言語を出すと決まってから(`LanguageID.released` を増やす前に、出す言語の全部の規則に語がそろっていること。`forbidden.languages` が error で止める)。語は用語の表の「真実」の項から書き出す(L-09)。
2. 今、生成の側で「ある人物の行と地の文」に限って照らしている規則は、該当の規則に `"scope": {"speakers": ["<人の ID>"], "narration": true}` を付けて、エンジンの側の宣言に移す。**移す前と後で、非公開の層の静的な監査と走行中の監査の違反の集合が同じ**になることを確かめる(違反の件数と規則の名札だけを比べる。語・文は見ない)。同じになったら生成側の特別扱いを消す(U14)。`other` は、名前・説明・画面の文にもその語を許さないなら `true`。
3. `tools/public-words.json`: `publicOnlyWords` を配列のまま、または言語のオブジェクトに。英語の語は大文字で始まる固有名だけが公開の検査に効く。`latinAllowed` を言語ごとにするのは他の言語を出すとき。
4. 代名詞: `perception/forbidden.json` に `pronounRules`、日本語の文言の表に `about`(U14 の生成器が `l10n/_source` と同じ情報から書く。人を差し込む文の型は `"*"`)。`pronounRules` の語を `public-words.json` に入れない。
5. 手元で `REFORGE_PRIVATE_CONTENT=<層> python3 tools/check-public-spoilers.py` を回し、段 B の変更の前後で当たりの件数が同じ(日本語の配列のままなら 0 件のまま)なことを確かめる。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(この作業場には非公開の層が無い。統合担当が「非公開の層の側」を回す。F §4)。
- 段ごとに: 枝の名前・コミットのハッシュ・4 の結果(件数・失敗・飛ばし)。
- 設計書と違う判断(とくに `about` を文言の表に置いたこと — 設計書は `l10n/_source` から読む形だが、`l10n/` は読み込まない決めのため — と、`scope` の `.other` の決め方、英語の ID の形の定義)。

## 8. 非公開の層の側の結果(10/18・統合担当)
- 生成の側で「ある人物の行と地の文」に限って照らしていた検査は、代名詞の検査 1 つだけだった。これは禁止語の規則(`scope`)ではなく、§6-4 の代名詞の規則(`pronounRules` と文言の表の `about`)に移した。禁止語の監査は「事実を知るまで出さない」語のためで、代名詞は開かないため。
- エンジンに `PronounRule.allow`(照らす前に文から除く語)を足した。日本語の部分一致では、代名詞の字を含むが代名詞ではない語(複数形・熟語)が当たってしまうため。`review` は省略できるようにした。`PronounAudit.checkAll` で、表のある全部の言語を照らす。
- 照らす範囲(`about`)は、その人の台詞・一言、地の文、資料の本文。生成の側の範囲に、その人の一言(`lines`)を足した(今は 0 件)。ほかの人を指すと確かめた行には `about` を付けない。追加の章へ移す文言は `about` も一緒に移す。
- 移す前と後の比べ: 前は生成の検査の当たりが 0 件、後はエンジンの `error` が 0 件(範囲は同じ 405 件。追加の章へ移した 3 件は除く)。禁止語の静的な監査の結果は変わらない(規則に触れていない)。層の写しの 1 文に代名詞を足すと試験が落ち、除く語を足しても通ることを確かめた。
- 生成の側の特別扱い(文を照らして止める検査)は消した。生成器は宣言を書くだけ。

