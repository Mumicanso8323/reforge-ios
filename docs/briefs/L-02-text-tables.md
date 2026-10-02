# 説明書 L-02: 言語ごとの文言の表を読む

作業の単位: 多言語 L-02(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §4.2・§5.1 `TextTables`・§6.3・§6.4・§8.2・§8.3・§13 擬似言語・TEST-L1 の (2)(3)(7))。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-01(integration-c に入った。`RFText`・`TextRef`)。土台: integration-c の先頭。

## 1. 目的
文言の表に**言語の軸**を足す。読み込み・引き方・検証までを作り、**画面に出る文は 1 字も変えない**(今の組み立て `Perceiver` は日本語の表を今までどおり引く。言語で組むのは L-03)。
いちばん大事な約束: **今の非公開の層のデータ(言語の印が無い)を、そのまま読めて、今のテストが全部通ること**。非公開の層はこの作業場に無いので、統合担当がマージの前に回す。

## 2. 作るもの

### 2.1 RFContent: `TextTables`(新規 `ReForgeCore/Sources/RFContent/TextTables.swift`)
```swift
public enum TextLookup: Equatable, Sendable {
    case found(String)        // その言語の表にあった
    case fallback(String)     // その言語に無く、日本語(原文)に落とした
    case missing              // 日本語にも無い
}

public struct NameJoin: Codable, Equatable, Sendable {   // _meta.json の nameJoin(§8.3。使うのは L-03)
    public var order: [String]        // 部品の種類の並び("extreme","grade","temper","substance","shape")
    public var separator: String
}
public struct TextMeta: Codable, Equatable, Sendable {
    public var nameJoin: NameJoin?
}

public struct TextTables: Equatable, Sendable {
    public var tables: [LanguageID: [TextID: String]] = [:]
    public var meta: [LanguageID: TextMeta] = [:]
    public init() {}
    /// 表を持つ言語(擬似言語は含めない)。
    public var available: Set<LanguageID> { get }
    /// 引く。擬似言語は日本語の文を変形して .found で返す(2.4)。日本語の表に無ければ .missing。
    /// 日本語以外で無ければ .fallback(日本語)。繁体字が欠けても簡体字には落とさない。
    public func lookup(_ id: TextID, _ lang: LanguageID) -> TextLookup
    /// 画面に出す前の文の型(パターン)。fallback は marker が true なら頭に "[ja]" を付ける。missing は nil。
    public func pattern(_ id: TextID, _ lang: LanguageID, marker: Bool) -> String?
}
```
- `ContentDB` に `public var textTables = TextTables()` を足す。
- 今の `ContentDB.texts: [TextID: String]` は**消さずに**、`textTables.tables[.ja]` を読み書きする計算プロパティに替える(`get` は `tables[.ja] ?? [:]`、`set` は `tables[.ja] = newValue`)。今の本体とテストの `db.texts[...]`(読み・書き・`c.texts["…"] = "…"`)がそのまま動くこと。`Equatable` の比較は保存されたプロパティ(`textTables`)で行われる。
- `textGates` は今のまま(日本語の表にだけ書く。門は ID ごとなので全部の言語に効く)。

### 2.2 読み込み(`ContentLoader.swift`)
- 1 つの JSON に、省略できるキー `"language"`(`LanguageID` の rawValue)と `"nameJoin"` を足す。
  - `"language"` が無いファイルの `"texts"` は**日本語**として読む(今のデータの全部がこれ)。
  - `"language": "x-pseudo"` は読み込みの誤り(擬似言語は表を持たない)。
  - `"language"` が `ja` 以外のファイルに `"textGates"` があれば読み込みの誤り。
  - ファイルの層の中の相対パスが `text/<コード>/…` で、`<コード>` が `LanguageID` の rawValue なのに `"language"` と違う(または `"language"` が無く `<コード>` が `ja` でない)ときは読み込みの誤り(置き場所と印の食い違いを止める)。
  - `"nameJoin"` は `textTables.meta[言語].nameJoin` に入れる(`"language"` の無いファイルなら ja)。
- 層の中の重複の検査(`seen.insert`)は、言語ごとに分ける(`"texts.ja"`・`"texts.en"` の名前で)。同じ ID が日本語と英語の両方にあるのは重複ではない。
- 後の層はキーごとに上書き(今と同じ。言語ごと)。
- `remove` の `"texts"` は、全部の言語の表からその ID を消す。
- `isContentPath` に `l10n/` を足す(`materials/`・`tools/` と同じ扱い。§6.4)。`_meta.json` は今の規則で読まれる(ファイル名が `_` で始まっても読む)ので、そのままでよい。
- `docs/architecture/E-content.md` の、表(33 行目)と置き場所(70〜71 行目)と重ねる順(46 行目)の説明を、この形に直す(`text/<言語>/`・`language`・`_meta.json`・`l10n/` を読まない)。

### 2.3 地図の字の文言(`Schema/Perception.swift`)
- `Variant` に `public var glyphText: TextID?` を足す(省略可。init の引数の末尾に既定値つきで足す)。意味: 言語で変わる地図の 1 字。あれば `glyph` より勝つ。**この単位では引かない**(使うのは L-03 以降。`MapProjection` に触らない)。

### 2.4 擬似言語(§13)
`lookup(id, .pseudo)` は、日本語の文 `s` から次を作って `.found` で返す:
- `"⟦" + s + 足し + "⟧"`。`足し` は「・」を `(s の Character の数 × 4 + 9) / 10` 個(4 割を切り上げ。整数で)。
- `s` が ICU のパターンでも、足すのは外側だけなので、組み立ては壊れない(テストで確かめる)。

### 2.5 検証(`ContentValidator.swift` に `textTablesWellFormed` を足し、`validate` から呼ぶ)
規則の名前と水準:
1. `text.format`(error): どの言語のどの文も `MessageFormat` のパターンとして読める(L-01 の `PatternParser` を使う。2.6)。
2. `text.args`(error): 日本語以外の言語の文は、同じ ID の日本語の文と**引数の名前の集まり**が同じ(順番は自由。plural・select・josa・cap の名前も数える)。日本語に無い ID は対象外(3 を見よ)。
3. `text.orphan`(warning): 日本語に無い ID が、ほかの言語の表にある。
4. `perception.glyphText`(error): `glyphText` の日本語の文が 1 つの書記素(`Character` 1 つ)。日本語に無ければ error。ほかの言語にある文も 1 書記素。
- **欠けた ID(日本語にあって英語に無い)は、この単位では報告しない**(TEST-L1 の (1) は L-08)。
- RFContent が RFText を使うので、`Package.swift` の RFContent の依存に `"RFText"` を足す(L1 → L2 の向きなので層の決まりに合う)。

### 2.6 RFText に足す口(`MessageFormat.swift`)
```swift
extension MessageFormat {
    /// パターンが読めるか(読めなければ throw。render と同じ解析)。
    public static func validate(_ pattern: String) throws
    /// パターンが使う引数の名前の集まり(入れ子の分岐の中も含む)。
    public static func argumentNames(_ pattern: String) throws -> Set<String>
}
```

### 2.7 公開の層の文言を `content/public/text/ja/` に移す
- 今 `"texts"` を持つ公開の層のファイル(`perception/perception.json`・`perception/units.json`・`combat/perception.json`・`codex.json`・`map.json`・`production/production.json`・`research/research.json`・`narrative/documents.json`・`narrative/sheets.json`)から、`"texts"` の中身を**そのまま**(ID も文も変えずに)`content/public/text/ja/<元のファイルの名前を / を _ にしたもの>.json` に移す(例: `perception/perception.json` → `text/ja/perception_perception.json`)。移した先のファイルは `{"language": "ja", "texts": {…}}`。元のファイルからは `"texts"` を消す。`textGates` は動かさない。
- `content/public/text/ja/_meta.json` を作る: `{"language": "ja", "nameJoin": {"order": ["extreme","grade","temper","substance","shape"], "separator": ""}}`。
- 試験用に `content/public/text/en/test.json` を作る: 公開の層の日本語の表から、引数を持つ文 1 つと持たない文 2 つを選び、英語の文(物語に触れない一般の語)を書く(`"language": "en"`)。`_meta.json` も en 用(`separator` は `" "`)。
- 公開の層の内容の数(ID と文)が移す前と同じであることを、テストで確かめる(2.8 の 6)。

### 2.8 テスト(`Tests/RFContentTests/TextTablesTests.swift` を新規。RFText の 2.6 は `Tests/RFTextTests` に足す)
1. 言語の印の無い `"texts"` は日本語に入る。`db.texts` で読める・書ける(計算プロパティ)。
2. `language: "en"` の表は英語に入り、`lookup(id, .en)` が `.found`。英語に無い ID は `.fallback(日本語)`。日本語にも無ければ `.missing`。`zh-Hant` が無くても `zh-Hans` に落ちない。`pattern(…, marker: true)` は fallback に `[ja]` が付き、found には付かない。
3. 擬似言語: `⟦…⟧` で囲み、「・」の数が 4 割の切り上げ。`{n, plural, other {# 個}}` の擬似言語のパターンを `MessageFormat.render` で組んで落ちない。
4. 読み込みの誤り: `x-pseudo` の表・`en` の表の `textGates`・`text/en/` に `"language": "ja"`・同じ層の同じ言語の同じ ID(重複)。同じ ID が ja と en にあるのは誤りでない。`remove` の `texts` が全部の言語から消す。`l10n/` の下の JSON を読まない。
5. 検証: 読めないパターン → `text.format`。英語の引数の名前が違う(`{who}` と `{actor}`)→ `text.args`。日本語に無い ID が英語にある → `text.orphan`(warning)。`glyphText` の文が 2 字 → `perception.glyphText`。
6. 公開の層を読んだ `db.texts` の件数と中身が、移す前の版(移す前に数えた件数をテストに数字で書く)と同じ。`TestContent.publicOnly()` の検証が error 0。
7. RFText: `validate` が読めないパターンで throw、`argumentNames` が入れ子の中の名前も返す。
- 今のテストは全部、変えずに通ること(`db.texts` を読み書きするテストを含む)。

## 3. 確かめのコマンド
```
~/.local/bin/rf-note-test . --filter 'RFContentTests|RFTextTests|RFPerceptionTests|RFPresentTests'
~/.local/bin/rf-note-test .                        # 全体(公開の層)。終了コード 0
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
```
- note に ssh できなければ予備(hub): `~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter <テスト>`。hub では全体を回さない。
- 増分のビルドが signal 11 で落ちたら `swift package clean --package-path ReForgeCore` してから回し直す。

## 4. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFContent/`(`TextTables.swift` 新規・`ContentDB.swift`・`ContentLoader.swift`・`ContentValidator.swift`・`Schema/Perception.swift`)、`ReForgeCore/Sources/RFText/MessageFormat.swift`(2.6 だけ)、`ReForgeCore/Package.swift`(RFContent の依存に RFText)、`ReForgeCore/Tests/RFContentTests/`・`ReForgeCore/Tests/RFTextTests/`、`content/public/`(2.7 だけ)、`docs/architecture/E-content.md`(2.2 の 3 か所)。
- 触らない: `RFPerception`(`Perceiver`・監査)・`RFPresent`・アプリ(`ReForge/`)・`content/private`・保存の形(`RFSave`。`ContentDB` は保存に入らない)・`rf-seal`・`stage.sh`・`ci.yml`。

## 5. 約束(F §4)
- 公開リポジトリに物語の語を書かない(英語の試験の文は一般の語だけ)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない(開発者向けのエラーの文は日本語でよい)。
- 浮動小数を使わない。
- 名前の重なり: `TextTables`・`TextLookup`・`TextMeta`・`NameJoin` がアプリや SwiftUI/Foundation の型と重ならないこと(`check-app-names.py`)。

## 6. 決めかねたとき
- 今の公開の層の文で、`MessageFormat` として読めないもの(`{` `}` を文字として使っているなど)が見つかったら、文を直さずに報告に書く(文の持ち主は統合担当)。
- 計算プロパティ `texts` で動かないテストがあれば、テストを直さずに報告に書く。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(この作業場には非公開の層が無い。統合担当がマージの前に、古い形の非公開の層で回す。F §4)。
- 枝の名前・先頭のハッシュ・3 の結果(件数)・公開の層の文言の件数(移す前と後)・6 に当たったこと。
