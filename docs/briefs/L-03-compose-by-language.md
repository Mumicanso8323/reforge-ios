# 説明書 L-03: 組み立てを言語で(Perceiver・Frame・GameHost)

作業の単位: 多言語 L-03(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §4.3・§5・§7・§8.1〜§8.3・BRK-03/04/05/11/12/13/26/29・INV-L1〜L5・TEST-L2/L3/L4)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: L-01・L-02(integration-d に入っている)。土台: integration-d の先頭。
**出す言語は日本語だけのまま**(別の決定があるまで。`LanguageID.released` は L-04 で作る)。この単位は仕組みで、**日本語で画面に出る文は 1 字も変えない**。ほかの言語の訳は作らない(訳の手配は本人の決め)。
大きいので **3 段(A・B・C)に分け、1 段 = 1 回の Codex 実行 = 1 コミット**で渡す。前の段のテストが通ってから次へ。

## 1. 目的
本体が画面に出す文を、「文言の ID と型つきの引数」(`TextRef`)と言語から組む。言語を読むのは組み立てる瞬間(`Perceiver`)だけにし、世界・乱数・見込みは言語を知らない(INV-L1)。切り替え(`GameHost.setLanguage`)は世界を 1 歩も進めずに同じ世界から `Frame` を作り直す。
いちばん大事な約束: **言語を指定しない今の呼び方(`Perceiver(content:world:)` など)は、今までと同じ日本語を返す**。今のテストが全部、直さずに通ること。

## 2. 作るもの

### 段 A: Perceiver が言語で組む
#### 2.A1 `Perceiver`(`RFPerception/Perceiver.swift`)
```swift
public struct Perceiver: Sendable {
    public let language: LanguageID                      // 既定 .ja
    public let markFallback: Bool                        // 既定 false。true なら日本語に落ちた行の頭に "[ja]"(開発の版だけ。OPEN-L5)
    public init(content: ContentDB, known: Set<FactID>, language: LanguageID = .ja,
                markFallback: Bool = false, auditor: PerceptionAuditor? = nil)
    public init(content: ContentDB, world: WorldState, language: LanguageID = .ja,
                markFallback: Bool = false, auditor: PerceptionAuditor? = nil)
    /// 画面に出す文はすべてここを通る。引数は型で渡す(数は .number。plural に文字列の数は使えない)。
    public func render(_ ref: TextRef) -> String
}
```
- `TextArg` → `RenderedArg`: `.int(n)` → `.number(n, 0)`、`.fixed(v, p)` → `.number(v, p)`、`.text(id)` → その文言を組んだ文字列、`.subject(s)` → `name(s)` を監査なしで(今の段の名前)、`.person(p)` → 人の名前(`Subject.person(p)` を同じく)、`.ref(r)` → 入れ子を組んだ文字列。
- 型の引き方: `content.textTables.pattern(id, language, marker: markFallback)` → `MessageFormat.render(…, language:)`。表に無ければ `text.unknown` の型、それも無ければ開発用の印「？」(今と同じ。本体に残してよい日本語の 1 字)。`render` が throw しても落とさず同じ落とし先にする。
- 組んだ結果に `⟦?`(引数が足りない印)が残ったら、今の `{…}` が残った文と同じ扱い(`text.unknown` にする)。擬似言語の囲み `⟦…⟧` とは区別する(`⟦?` だけを見る)。
- 監査(`auditor`)は一番外側の結果に 1 回だけ(入れ子の中では呼ばない)。禁止語の照らし方を言語ごとにするのは L-05。ここでは今のまま。
- 今ある `text(_:_:)`・`rawText(_:_:)`(`[String: String]` の引数)は残し、中身を同じ組み立て(`.string` の引数)に通す。`Rejection.detail` と来歴の引数は段 B で `TextRef` にする。
- 擬似言語(`language == .pseudo`)も同じ口を通る。表が無い文言は `TextTables.lookup` が日本語から作る。

#### 2.A2 単位を差し込みの文に(BRK-04)
- `Perceiver.stat` の `.number(divisor, unit, decimals)` は、今「数の文字列 + 単位の文言」をつないでいる。単位の文言の型に `{value}` があれば、`value` に数(`.number(v, places)`)を渡して 1 つの文として組む。
- **互換**: 日本語の単位の文言に `{value}` が無ければ、今までの「数 + 文言」の連結のまま(今の公開・非公開のデータはこの形)。**日本語以外の言語では連結しない**(`{value}` が無い単位の文言を使った時は `text.unknown` にする)。
- `ContentValidator` に `text.unit`(error): 日本語に `{value}` がある単位は、日本語以外の表の同じ ID にも `{value}` がある。日本語に無い単位は、日本語以外の表に **`{value}` を持つ文を置いてはいけない**(日本語の連結の形と食い違うため)。

#### 2.A3 名前の並べ方(BRK-05。§8.3)
- `rawName(of: MatterName)` を、`content.textTables.meta[language]?.nameJoin`(L-02 で読み込み済み)で組む。部品の種類の鍵は `NamePart` の CodingKeys と同じ(`extreme`・`grade`・`temper`・`proper`・`substance`・`shape`)。`order` に無い種類は、元の相対順のまま最後に付ける。空の部品は飛ばし、区切りは空でない部品の間だけ。
- `meta` が無い言語は日本語の `meta` を使い、それも無ければ区切りなし・今の並び(今と同じ)。公開の層の `text/ja/_meta.json`(区切りなし)で今の出力と同じになること。

#### 2.A4 地図の字の文言(§8.2)
- `Perceiver.glyph(_:)`: `Variant.glyphText`(L-02 で足した)があれば、その言語の表から 1 字を引く。表に無い・組めない・1 書記素でないときは、`Variant.glyph`(言語に依らない字)、それも無ければ今の落とし先。**擬似言語では囲まず**、日本語の字をそのまま返す(1 マス 1 字の決めを壊さない)。
- `MapProjection` の結晶の既定の字(漢字 1 字のリテラル)を、地図の記号(`MapGlyphFont` の書体にある字。`◆` など)に替える。「？」は開発用の印として残してよい。

#### 2.A5 本体の画面向けの日本語を表へ(INV-L3)
- `RFPresent/DayWrap.swift` の `label(id, 日本語の既定, args)` と、`FrameBuilder.swift` の名簿・技能の 7 つの `label(id, 日本語の既定)` から、**日本語のリテラルを消す**(既定の文を持たない形にする)。引数の数は `RenderedArg.number` で渡す。
- 文を `content/public/text/ja/core_ui.json`(`{"language": "ja", "texts": {…}}`)に、**今のリテラルと同じ文**で置く(ID は今のまま: `ui.daywrap.*`・`ui.roster.*`・`ui.grant.*`)。今すでに公開の層にある ID は足さない(重複は読み込みの誤り)。非公開の層が同じ ID を持てば、後の層が勝つ(今と同じ)。
- 夜の締めの「。」でつなぐ(`parts.joined("。")`)は、約物をコードで足している(INV-L5)。区切りを `ui.daywrap.sep` の文言にし、`ja` は「。」。
- 矢印・記号(`↑→↓←`・`○`・`∴` など、かな・漢字・ハングルを含まない字)は残してよい。

#### 2.A6 `FrameBuilder`・`Frame`
- `FrameBuilder` に `public var language: LanguageID = .ja` と `public var markFallback = false`。`build` は `Perceiver(content:world:language:markFallback:)` を作って使う(中の関数が作る `Perceiver` も同じ言語。`GameHost.describe`・`resumeLine`・`darkStart` の中の `Perceiver(content:world:)` も)。
- `Frame` に `public var language: LanguageID`(init は既定 `.ja`)。

### 段 B: 引数を文に入れる・表示の文で並べない
#### 2.B1 断った理由(BRK-03)
- `Rejection.detail: [String: Value]` を `TextRef` の引数にする変換を `RFPerception` に 1 か所置く: `.int`・`.uint` → `.int`、`.string` で名前が `item` → `.subject(Subject.item(…))`、`module` → `.subject(Subject.module(…))`、ほかの文字列は今と同じく無視。`item`・`module` があれば `0` の名前でも同じ値を渡す(今の `{0}` の仕組みと同じ出力)。
- `Perceiver.rejectionText(_:detail:)` と `stoppedText` は、この変換と `render` を通す(出力は今と同じ)。
- `GameHost.describe(_:)` は `render(TextRef(r.reason, args))`。**画面には出さない**(今も出していない。足元カードに理由の文を出さない決めは変えない)。診断と試験と端末内の記録用。
- `GameHost` に `public func rejectionRef(_ r: Rejection) -> TextRef`(組む前の参照)を足す。

#### 2.B2 ノートの引数(BRK-13)
- `NoteEntry.args: [FindingArg]` と `Workbench` の `findingText`・`argStrings` を、`TextRef` の引数にする変換(`item` → `.subject`、`module` → `.subject`、数・純度の見当 → `.int`/`.fixed`、形・剛柔 → `.text`)に通し、`Perceiver.render` で組む。今の `{0}` `{1}` の位置は、引数の名前 `"0"`・`"1"`(`MessageFormat` が数字の名前を受けることを、テストで確かめる。受けなければ報告に書く)。日本語の出力は今と同じ。
- 保存の形(`NoteEntry`)は変えない。

#### 2.B3 表示の文で並べない・比べない(INV-L4・BRK-29)
- `DayWrap.made` は表示の名前を鍵にして数え(`tally[name]`)、同数のときは名前の文字順で並べている。名前は言語で変わるので、**来歴の対象(`SubjectRef` の鍵)で数え、同数は鍵で並べ**、名前は最後に引く。日本語の出力の並びが変わる場合は、変わった例を報告に書く(同数のときの順だけ)。
- ほかに「表示の文を鍵・並べ替え・比較にしている所」を `RFPresent`・`RFPerception` で棚卸しする(`sorted`・`Dictionary(grouping:)`・`==` で `String` を比べている所)。見つけた物は同じ直し方で直し、見つけた場所と件数を報告に書く。ID・コンテンツの順で並べる。

### 段 C: 言語を切り替える・知らせを参照で持つ
#### 2.C1 `GameHost`(`RFPresent/GameHost.swift`)
```swift
public actor GameHost {
    public init(simulation: Simulation, world: WorldState, language: LanguageID = .ja, markFallback: Bool = false)
    public private(set) var language: LanguageID
    /// 世界を進めずに、同じ世界から新しい言語で Frame を作り直す。revision は進める(画面が受け取り直す)。
    @discardableResult public func setLanguage(_ lang: LanguageID) -> Frame
    /// 最後に断った理由(組む前の参照)。言語を切り替えても残り、Frame を作るたびに今の言語で組める。
    public private(set) var lastRejection: TextRef?
}
```
- `builder` は `var` にして言語を差し替える(`public private(set) var builder`)。`setLanguage` は、前の `Frame` を `previous` に渡し、**全部の区画の版を上げる**(地図の字が言語で変わるため。`report.changes.areas` に `.perception` を載せた時と同じ扱い)。
- `setLanguage` は `heldCarry`・時計の保留・世界のどれも変えない。`replayLog` には書かない(コマンドではない)。
- `perform(_:)`・`send(_:)` が断りを受けたら `lastRejection` を更新する(断りが無い命令で消す)。`perform` の戻りの文字列 `rejection: String?` は残す(試験・診断用)。
- `public func peek(at: GridPoint) -> TileInspection?` を足す(`builder.inspect` だけ。`inspect(at:)` と違い、世界に何も書かず、コマンドも送らない。切り替えの引き直し用)。
- `replace(world:)`・`dawnSaveData` は今のまま(言語を引き継ぐ)。

#### 2.C2 アプリの `GameStore`(`ReForge/Sources/Game/GameStore.swift`。アプリの変更は最小)
- `notice: String?` と `show(notice:)` を、`noticeRef: TextRef?` に替える(**組んだ文を持ち越さない**。INV-L2)。端末内の記録 `logPlay(kind: "refused", fields: ["reason": …])` には、文ではなく ID(`ref.id.rawValue`)を書く。同じ断りの繰り返しの判定は `TextRef` の `==`。
- `func setLanguage(_ lang: LanguageID) async`: `host.setLanguage` の `Frame` を `refresh` に渡し、**組んだ文を持っている所を全部引き直す**: `footCard`・`inspection`(同じマスを `host.peek(at:)` で引き直す。`inspect(at:)` は世界に覚えを書くので使わない)・`panel`・`decision` の取消の札(`decisionUndo.label`)・`resumeBanner`・`dayWrap`・`objective`・`sceneLines`・`prologue`・設計とノートの頁(`benchRevision` を進める)。持ち越している文の棚卸しは `rg "String"` で `GameStore` と `GameStore+*.swift` を見て、見つけた物を報告に書く。
- アプリのビルドと単体テストは **macOS の CI(統合担当が ci/integration で手動起動)** で回す。Codex は回さない。壊さないように、変えた所は型で守る(Swift の型検査の範囲で)。

## 3. テスト(Linux で回る分。`ReForgeCore/Tests/`)
段 A(`RFPerceptionTests/RenderTests.swift` を新規):
1. `render(TextRef)`: 日本語で今の出力と同じ。引数が足りない文は `text.unknown`。入れ子の `.ref`・`.text`・`.subject`・`.person`。
2. 擬似言語: 全部の文が `⟦…⟧` で囲まれ、「・」が 4 割(切り上げ)。入れ子の文は**外側だけ**が囲まれる(内側を囲ってから外を囲むと二重になる)。監査は一番外側の 1 回。
3. 英語の試験用の表(テストの中でメモリ上に作る。`content/public` に足さない)で、`{n, plural, one {# hour} other {# hours}}` の単位が組める。日本語の連結の単位は日本語だけ連結し、英語では `text.unknown`。`text.unit` の検証が 3 つの場合(日本語に `{value}` あり・英語に無い → error / 日本語に無い・英語に有る → error / 両方あり → 通る)で出る。
4. 名前の並べ方: `meta` が `order`・`separator " "` のとき `"a b c"`、空の部品を飛ばす、`meta` 無しは今と同じ。
5. 地図の字: `glyphText` のある見え方が、日本語で表の字・擬似言語で囲まずに日本語の字・表に無い言語で `glyph`。
6. 本体の画面向けの文: `ui.daywrap.*`・`ui.roster.*` の組み立てが今と同じ出力(公開の層の既存のテストが通る)。`ReForgeCore/Sources` の `RFPresent`・`RFPerception` に、かな・漢字・ハングルを含む文字列リテラルが、開発者向けの 2 つのファイル(`HintAudit.swift`・`ForbiddenAudit.swift`)と「？」の外に無いこと(試験の中で `#filePath` から読む簡単な走査。本格の静的検査は L-06)。
段 B(`RFPerceptionTests/RejectionTextTests.swift` に足す・`RFPresentTests/DayWrapTests.swift`):
7. 断りの変換: `detail` の `item`・`module`・数が `TextRef` の引数になり、`render` が今の `rejectionText` と同じ文を返す(今のテストが全部通る)。
8. ノートの引数: `{0}` `{1}` の位置が今と同じ出力。
9. `DayWrap.made`: 同数の 2 つの品の並びが、名前を変えても(表の文を差し替えても)変わらない。
段 C(`RFPresentTests/LanguageSwitchTests.swift` を新規。TEST-L2〜L4):
10. **世界は言語を知らない**: 同じ seed・同じコマンドの列を `.ja`・`.pseudo` で 200 歩ずつ回し、各歩の保存のバイト列(`GameHost.saveData(slot: .resume, stamps: [])`)が等しい。寝る見込み・足元カードの行為の ID も等しい。
11. **実行中の切り替え**: 地図の途中・序の途中・決断の途中・断りがある時に `setLanguage(.pseudo)` を呼ぶと、次の `Frame` の文(`FrameText.allStrings`)のうち、文言から組んだものが全部 `⟦` で始まり、保存のバイト列は変わらず、序の行・場面の行の番号が変わらず、`revision` が進む。`setLanguage(.ja)` で元の `Frame`(`revision` 以外)に戻る。
12. 断りは `lastRejection` に参照で残り、切り替えの後の `describe` が新しい言語の文になる。
13. **保存に文が無い**: 長く遊んだ世界の保存の JSON の文字列の値のどれも、`textTables` の全部の言語の値と一致しない。
14. 地図の `Frame` の区画の版: `setLanguage` で全区画の版が上がる。同じ言語を続けて呼ぶと、上がらなくてよい(上げてもよいが、二度目で世界が変わらないこと)。

## 4. 確かめのコマンド(hub のみ。段ごとに関わるテストだけ)
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift build -j 3 --build-tests --package-path ReForgeCore
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'RFPerceptionTests|RFPresentTests|RFContentTests|RFTextTests'
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
```
- hub の負荷の決まり: docker は必ず `rf-swift-slot` を通し、`--cpus=3`・`-j 3`。`--parallel`・`-d` は使わない。全体のテストは回さない(統合担当がマージのときに回す)。**note には ssh しない・`rf-note-test` は使わない**。
- アプリ側(`GameStore`)の確かめは macOS の CI(ci/integration の手動起動)で統合担当が回す。報告に「アプリは CI 待ち」と書く。
- 増分のビルドが signal 11 で落ちたら `swift package clean --package-path ReForgeCore` してから回し直す。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFPerception/Perceiver.swift`、`ReForgeCore/Sources/RFPresent/`(`FrameBuilder.swift`・`Frame.swift`・`GameHost.swift`・`DayWrap.swift`・`MapProjection.swift`・`Workbench.swift`・`Panels.swift` の文の組み立てと並べ替えの所)、`ReForgeCore/Sources/RFContent/ContentValidator.swift`(`text.unit` だけ)、`ReForgeCore/Sources/RFKernel/Text.swift`(足りない小さな口があれば)、`ReForgeCore/Tests/`(上の新規と、直す必要のあるテスト)、`content/public/text/ja/core_ui.json`(新規)、`ReForge/Sources/Game/GameStore.swift` と `GameStore+*.swift`(2.C2 だけ)と、それが壊す `ReForgeTests/` の最小の直し。
- 触らない: `ForbiddenAudit` の照らし方(L-05)・封と `rf-seal`・`stage.sh`・`ci.yml`(L-04)・`content/private`・保存の形(`SaveCodec`・`SaveEnvelope`・`NoteEntry` の型)・画面の見た目(アプリのビューのファイル。L-10b 以降)・ほかの言語の訳文(`content/public/text/en` などに文を足さない)。

## 6. 約束(F §4)
- 公開リポジトリに物語の語・人の名前を書かない(テストの文は「iron ore」「hour」など一般の語と、`test` の ID だけ)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない(2.A5 の後に残るのは開発者向けの文と「？」だけ)。
- 浮動小数を使わない。保存の型に `Double`・`Date`・`Data` を足さない。
- 画面に、確認のダイアログ・説明・理由の文を足さない(断りの文は引き続き画面に出さない)。
- 名前の重なり: 新しい型・関数が、アプリや SwiftUI/Foundation の型と重ならないこと(`check-app-names.py`)。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(この作業場には非公開の層が無い。統合担当がマージの前に、古い形の非公開の層で回す。F §4。とくに非公開の層の単位の文言に `{value}` が無い(連結の形)ことと、`ui.daywrap.*` の重なり)。
- 段ごとに: 枝の名前・コミットのハッシュ・4 の結果(件数・失敗・飛ばし)。
- 2.B3 の棚卸し(見つけた場所と件数・並びが変わった例)、2.C2 の持ち越している文の棚卸し(直した物・直せずに残した物)、`{0}` が `MessageFormat` に通るか、設計書と違う判断。
