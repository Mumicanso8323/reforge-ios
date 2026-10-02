# 説明書 L-01: 文言の型と書式(RFKernel の型 + 新しいモジュール RFText)

作業の単位: 多言語 L-01(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2(ddd6f30)の §4.2・§4.3・§5.1・§13 TEST-L14)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: なし(最初の単位)。土台: integration-c の先頭。

## 1. 目的
多言語の土台になる「文言の参照」と「書式」を、純 Swift(Linux で全部確かめられる)で作る。この単位では、**どこからも使わない**(既存のコードの振る舞いを 1 つも変えない)。使い始めるのは L-02・L-03。

## 2. 作るもの

### 2.1 RFKernel(既存のモジュールに新しいファイル `ReForgeCore/Sources/RFKernel/Text.swift`)
```swift
public enum LanguageID: String, Codable, CaseIterable, Sendable {
    case ja, en, zhHans = "zh-Hans", zhHant = "zh-Hant", ko
    case pseudo = "x-pseudo"            // 開発の版とテストだけ(§13 の擬似言語)
    public static let shipped: [LanguageID] = [.ja, .en, .zhHans, .zhHant, .ko]
    public static let source: LanguageID = .ja
}

public indirect enum TextArg: Codable, Equatable, Hashable, Sendable {
    case int(Int64)
    case fixed(Int64, places: Int)      // 整数を 10^places で割った小数(浮動小数を使わない)
    case text(TextID)                   // 別の文言(ボタンの名前など)
    case subject(SubjectID)             // 認識の層の主題(L-03 で今の段の名前に組む)
    case person(PersonID)
    case ref(TextRef)                   // 入れ子の文
}

public struct TextRef: Codable, Equatable, Hashable, Sendable {
    public var id: TextID
    public var args: [String: TextArg]
    public init(_ id: TextID, _ args: [String: TextArg] = [:])
}
```
- `TextID`・`SubjectID`・`PersonID` は既存(`RFKernel/IDs.swift`)。新しい ID の型は作らない。
- Codable の形は Swift の合成のまま。`[String: TextArg]` は JSON のオブジェクトになる。保存にはまだ使わない(L-03 で使うときに統合担当が形を確かめる)。**Double・Float・Date・Data を持たない**(保存の約束。F §4)。

### 2.2 新しいモジュール RFText(`ReForgeCore/Sources/RFText/`。RFKernel だけに依る)
```swift
public enum RenderedArg: Equatable, Sendable {   // 組み立ての直前の値(主題や人は名前に組んである)
    case string(String)
    case number(Int64, places: Int)
}
public enum PluralCategory: String, Sendable { case zero, one, two, few, many, other }

public enum MessageFormat {
    /// ICU MessageFormat の一部(§4.2)を組み立てる。解析の結果は (言語, パターン) ごとに記憶してよい(スレッド安全に)。
    public static func render(_ pattern: String, args: [String: RenderedArg], language: LanguageID) throws -> String
}
public enum PluralRule { public static func category(_ n: Int64, places: Int, _ lang: LanguageID) -> PluralCategory }
public enum Josa { public static func pick(after word: String, pair: (String, String)) -> String }
public enum NumberText { public static func format(_ n: Int64, places: Int, language: LanguageID) -> String }
```

書式(§4.2。これ以外は受けない):
- `{name}`: 引数をそのまま差し込む(`.number` は `NumberText.format`)。
- `{n, plural, one {# day} other {# days}}`: 複数の選び分け。`#` は数(`NumberText`)。`=0`・`=1` などの完全一致を先に見る。
  - 英語: 整数の 1 だけ `one`、ほかは `other`(**小数点つきは 1.0 でも `other`**)。日本語・中国語(両方)・韓国語: いつも `other`。擬似言語: 英語と同じ。
  - 該当する分岐が無ければ `other`。`other` が無いパターンは解析の誤り。
- `{kind, select, a {…} b {…} other {…}}`: 文字列の引数で選ぶ。無ければ `other`。
- `{actor, josa, 이/가}`: 差し込んだ語に続く韓国語の助詞(この製品だけの書式)。出力は「語 + 助詞」。
- `{subject, cap}`: 差し込んだ語の頭の 1 書記素を大文字にする(この製品だけ。英語で文の頭に来た名前)。ラテン文字でなければそのまま。
- 分岐の中の入れ子(`{n, plural, other {{who} has # items}}`)を受ける。
- `'` による ICU の引用は受けなくてよい。`{` `}` を文字として出したいときは `'{'` `'}'` だけ受ける。
- 引数が足りない・型が合わない(plural に文字列など)ときは、**落ちずに** `⟦?name⟧` を差し込む。パターンの解析の誤りは `throw`。

`NumberText`(§4.3): 5 言語とも半角 0〜9、小数点は「.」、桁の区切りなし、負は「-」。`places` の桁を必ず出す(`fixed(150, places: 2)` → `1.50`)。言語ごとに変えられる口(switch)だけ残す。

`Josa`(§4.3): 語の最後の書記素を見る。
- ハングルの音節(U+AC00〜U+D7A3): パッチムがあれば `pair.0`、無ければ `pair.1`。ただし対が「으로/로」のときは、パッチムが ㄹ でも `로`。
- 最後が数字: 韓国語の読みで決める(0 영・1 일・2 이・3 삼・4 사・5 오・6 육・7 칠・8 팔・9 구。パッチムあり = 0,1,3,6,7,8)。
- それ以外(英字など): `"\(pair.0)(\(pair.1))"` の両方の形。

擬似言語(`x-pseudo`)の組み立ての仕上げは L-02 の仕事。この単位では `render` は擬似言語でも英語と同じ複数の規則を使うだけでよい。

### 2.3 Package.swift
- `.target(name: "RFText", dependencies: ["RFKernel"])` を L0 の後に足す(依存の向き: RFText は RFKernel だけ)。冒頭のコメントの層の図に 1 行足す。
- `ReForgeEngine` の依存と `Sources/ReForgeEngine/Exports.swift` に `@_exported import RFText` を足す。
- `testedModules` に `"RFText"` を足す(テストターゲット `RFTextTests` ができる)。

## 3. テスト(`ReForgeCore/Tests/RFTextTests/`。TEST-L14)
1. 英語の複数: 0 → other、1 → one、`fixed(10, places: 1)`(1.0)→ other、2 → other。`=0` が `one`/`other` より先に効く。
2. 日本語・簡体字・繁体字・韓国語: 0・1・2 のどれも other。
3. select: 合う分岐、無ければ other。
4. 韓国語の助詞: パッチムあり(책 → 이)、なし(나무 → 가)、ㄹ と 으로/로(돌 → 로)、ㄹ と 이/가(돌 → 이)、数字(3 → 이、2 → 가)、英字(A → `이(가)`)。
5. `cap`: `iron ore` → `Iron ore`、ハングル・漢字はそのまま、空文字は空。
6. 入れ子の分岐、`#` の差し込み、`'{'` の引用。
7. 引数が足りない・型違いで落ちずに `⟦?name⟧`。`other` の無い plural は throw。
8. `NumberText`: 負・places 0〜3・5 言語で同じ文字列。
9. `TextRef` と `TextArg` の Codable の往復(入れ子の `.ref` を含む)と、JSON にした形の見本 1 つ(文字列で比べる)。

## 4. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFKernel/Text.swift`(新規)、`ReForgeCore/Sources/RFText/`(新規)、`ReForgeCore/Tests/RFTextTests/`(新規)、`ReForgeCore/Package.swift`、`ReForgeCore/Sources/ReForgeEngine/Exports.swift`、`docs/architecture/A-modules.md`(層の図に RFText を 1 行)。
- 触らない: ほかの全部。とくに `ContentDB.texts`・`Perceiver`・`FrameBuilder`・アプリ(`ReForge/`)・`content/`。

## 5. 約束(F §4)
- 公開リポジトリに物語の語を書かない(テストの文は「iron ore」「day」「책」などの一般の語だけ)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない(この単位は書式の仕組みだけ。テストの中の日本語は可)。
- 名前の重なり: `MessageFormat`・`PluralRule`・`Josa`・`NumberText`・`RenderedArg`・`PluralCategory`・`LanguageID`・`TextArg`・`TextRef` が、アプリや SwiftUI/Foundation の型と重ならないこと(`check-app-names.py`)。
- 浮動小数を使わない(決定性。組み立ても整数で)。
- Foundation の `NumberFormatter`・`Locale` に頼らない(Linux と iOS で結果が違いうる)。

## 6. 確かめのコマンド
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift build -j 3 --build-tests --package-path ReForgeCore
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter RFTextTests
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
```
- hub の負荷の決まり: docker は必ず `rf-swift-slot` を通し、`--cpus=3`・`-j 3`。`--parallel`・`-d` は使わない。枠が空くまで待つ。全体のテストは回さない(統合担当がマージのときに回す)。
- 増分のビルドが signal 11 で落ちたら `swift package clean --package-path ReForgeCore` してから回し直す(コードの問題ではない)。

## 7. 終わりの報告(architect へ)
- コミットのハッシュ、触ったファイルの一覧
- 書式で受けない形(ICU の何を切ったか)の一覧
- テストの件数と全体の結果(件数・失敗・飛ばし)
- 設計書と違う判断をした所と理由
