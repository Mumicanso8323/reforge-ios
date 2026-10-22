# 説明書 W-09: 絵の受け口を場面と決断につなぐ(絵そのものは入れない)

作業の単位: W-09(絵の引き方)の残り。土台は main 1860eae。実装: relay:codex-impl。受け取り: 統合担当(architect)。
すでに main にある物: `ArtProvider`・`ArtView`(`ReForge/Sources/Theme/ArtProvider.swift`。封をした絵を引き、開けなければ絵なし)・`ArtSeal`(`ReForgeCore/Sources/RFContent/ArtSeal.swift`)・`rf-seal`・`Variant.art`(認識の見え方の立ち絵。仲間のタブが使用中)・`PrologueView.art`(W-16 が欄だけ作った。いつも nil)。
足りない物: 場面と決断が ArtID をデータから受けて `Frame` に載せる配線と、画面が絵の無いときに今と同じ見た目を保つ置き方。この単位はそれだけを作る。

## 0. 守る要件(AGENTS.md の最上位の要件に照らした扱い)
- **Z1 初手で止めない**: 絵は上乗せ。絵が無い・封が開かない・まだ調達していないときは、**今と同じ見た目**。絵の枠・仮の絵・頭文字の丸・シルエットは出さない。押せない物も、説明・理由の文も出さない(「絵が読めません」のような文を画面に足さない。封が開かない 1 行は今ある帯の `sealedContentFailed` のまま)。
- **人物の絵はチームで作らない**(調達は使い魔とオーナー)。この単位は**受け口と配線だけ**。リポジトリに絵のバイナリを入れない。試験の絵は、試験の中で作る単色の PNG を封にして(または `ArtProvider` に直接渡して)使う。
- 公開リポジトリに物語の語(人の名前・答えの語)を書かない。試験の ID は中立(`art.test.…` ではなく `t01` のように英小文字・数字・`.`・`_` だけ。`ContentValidator.artIDsAreNeutral` の形)。`content/private` は読まない。

## 1. 決めたこと(実装者は理由を問わずこのとおり作る)

### 1.1 どの場面が、どのデータから、いつ受けるか
| 場面 | データ(欄) | `Frame` の欄 | `FrameBuilder` が埋める時 |
|---|---|---|---|
| 序(`SceneStyle.prologue`)・物語の途中の全画面の場面(`.stage`)。夜明けに起きる出来事・結末の後の場面も、`scene` が `.stage` ならここ | `SceneDef.art`(新)。無ければ、今の行の話し手(`Line.speaker`)の立ち絵 = 認識の見え方 `Variant.art`(`Perceiver.art(Subject.person(id))`) | `PrologueView.art`(既存の欄) | `prologue(_:_:)` が `PrologueView` を作るフレームごとに(毎回、世界と内容から導く。状態は持たない) |
| 決断の帯(`PendingDecision`) | `EventDef.art`(新) | `DecisionView.art`(新) | `decision(_:_:)` が `DecisionView` を作るフレームごとに |
| 地図の上のふきだし(`bubble`・`sceneLines`) | 受けない(`SceneDef.art` が付いていても無視。地図の上に絵を直接置かない: docs/art/README.md §5) | — | — |
| 夜の締め(`DayWrapView`)・暗い場面(`darkStart`)・足元カード・上の帯・日付の帯 | 受けない | — | — |
| 仲間のタブ | 既存の `Variant.art`(変えない) | `CrewMemberView.art`(既存) | 既存 |

- 夜明けは特別な経路を持たない。夜明けに起きる出来事(`trigger.on == nil`)が持つ `scene` / `choices` が、上の表の行に当たるだけ。
- 絵は**場面 1 つ(ページ 1 枚)に 1 枚**。行ごとの絵の切り替え(`Line.art`)は作らない。ページを替えたいなら `then` で場面を分ける(序はもともとそうしている)。
- 立ち絵(話し手の絵)は `scene.art` が無い場面でだけ出る。`scene.art` があればそれが優先。話し手の見え方が絵を持たない(開示の前)なら、絵なし。見え方は事実で切り替わるので、**開示の前に人物の絵が出ない**ことは今の認識の層の規則のまま守られる(`SceneDef.art` / `EventDef.art` は無条件に出るので、データ側(U14)が、出してよい場面にだけ付ける)。
- 全身か胸から上かは `Frame` に持たない。`ArtView` が素材の縦横比で決める(§3.1)。

### 1.2 決めかねた物を既定の案で決めた(リーダーが覆してよい)
1. 絵の欄は `SceneDef.art` と `EventDef.art` の 2 つだけ。`Line.art`・`ChoiceDef.art`・`ChapterDef.art` は作らない。
2. 話し手の立ち絵は、認識の層の見え方から引く(新しいデータの欄を足さない)。
3. 全身/胸から上は画面の側が縦横比で決める(`Frame` に `ArtFraming` を足さない)。
4. 「存在しない ArtID」の検査は、`ContentValidator.validate(_:released:art:)` の新しい引数 `art: Set<ArtID>? = nil`。`nil` は「絵の一覧が分からない」ので検査しない(絵をまだ調達していない非公開の層がそのまま通る)。一覧を渡す側は、層に `art/` があるときだけ渡す(§2.4)。`rf-seal` への組み込みはこの単位でしない。
5. 絵の先読み・縮小デコードはこの単位でしない(§3.4)。
6. 決断の帯の絵は 56pt 角の切り出し 1 つ。大きな絵は出さない。

## 2. 本体(ReForgeCore。Linux で確かめる)

### 2.1 RFContent(`Schema/Defs.swift`)
`SceneDef` と `EventDef` は明示の init を持たない(JSON で読む・メモリベースの memberwise)。Optional の `var` を足せば既存の呼び出しは壊れない。
```swift
// SceneDef の末尾に足す
/// この場面(ページ)の絵(中立の番号。art.sealed の中)。全画面の場面(prologue・stage)だけが使う。bubble では無視する。
public var art: ArtID?

// EventDef の末尾に足す
/// 決断の帯に添える絵(中立の番号)。choices のある出来事だけが使う。
public var art: ArtID?
```
- どちらも省略可。**既定 nil。今の内容は 1 バイトも変わらない**: 同じ内容を読み、`JSONEncoder`(`.sortedKeys`)で書き戻した出力に `"art"` が現れない(Optional の合成 `encode` は nil を書かない)。Codable を手書きにしない。
- `Defs.swift` は W-24・ゼロ開始(`StartDef.opening`)も触る。**自分が触る行は `SceneDef`(`style`/`then` の直後)と `EventDef`(`tags` の直後)の中だけ**。ほかの型・並びは変えない(§5)。

### 2.2 RFPresent
```swift
// Frame.swift
public struct DecisionView {
    // ... 既存 ...
    /// 決断の帯に添える絵(無ければ nil)。
    public var art: ArtID? = nil
    // == に art を足す(自前の == を使っているので、足さないと絵だけが替わっても「同じ」になる)
}
```
- `PrologueView.art`(既存)の doc を「`SceneDef.art`、無ければ今の行の話し手の立ち絵」に直す。`PrologueView.init` は変えない。
- `Frame.init` に引数を足さない。`Frame` に新しい欄を足さない。
- `FrameBuilder.prologue(_:_:)`: `lines`(`shownLines`。今の行までの、条件を満たした行)を作った後、
  ```
  art = def.art ?? lines.last?.speaker.flatMap { p.art(Subject.person($0)) }
  ```
  を `PrologueView(... art:)` に渡す。`def.style` が `.bubble` / nil のときは今どおり `nil` を返す(絵も作らない)。
- `FrameBuilder.decision(_:_:)`: `DecisionView(... art: content.events[d.event]?.art)`。
- 序・stage の間の「地図は黒・帯は空」などの Frame の組み直し(`build` の `if let prologue` の分岐)は変えない。`frame.decision = nil` のまま(序の間は決断の帯の絵も出ない)。
- 絵の ID が実在するかは `FrameBuilder` で調べない(本体は絵の中身を知らない。無ければ画面が「絵なし」にする)。
- `FrameBuilder` は `Frame.swift`・`FrameBuilder.swift` を PT-B3(`Frame.pulses`・`decisionShown`)・ゼロ開始(`darkStart`・`unlocks`)も触る。**触るのは `prologue(_:_:)` と `decision(_:_:)` の 2 つの関数の中だけ**。

### 2.3 保存・時計・乱数
- 保存の形は変えない(`SaveEnvelope`・`schemaVersion`・場面の状態 `narrative.scene` はそのまま)。絵は状態に入れない。凍った保存の見本は作り直さない。
- 世界を変える処理(`Simulation`・`EffectApplier`・`NarrativeSystem`)に触らない。

### 2.4 検証(`ContentValidator.swift`)
```swift
public static func validate(_ db: ContentDB, released: [LanguageID] = LanguageID.released,
                            art: Set<ArtID>? = nil) -> [Issue]
```
- 既存の呼び出し(引数なし)はそのまま動く。新しい `static func artReferencesWellFormed(_ db: ContentDB, art: Set<ArtID>?, _ out: inout [Issue])` を、`validate` の呼び出しの並びの**末尾**(`extractPurityBonusInRange` の次)に 1 行足す。ほかの単位も末尾に足すので、衝突したら両方残す。
- 規則(名前):
  1. `art.form`(error): `SceneDef.art`・`EventDef.art`・`Variant.art` の ID が中立の番号の形(英小文字・数字・`.`・`_` だけ。空でない)。今の `artIDsAreNeutral`(`perception.art`)は変えず、場面と出来事の分を新しい規則で足す。
  2. `art.exists`(error): `art` が非 nil のとき、`SceneDef.art`・`EventDef.art`・`Variant.art` の ID が、その集合に無ければ error。メッセージに ID だけを入れる(どの場面かは場面の ID のみ。物語の語は入らない)。
  3. `art.bubble`(warning): `style` が `bubble` / nil の場面に `art` がある(無視されることを知らせる)。
  4. `art.event.nochoices`(warning): `choices` が無い出来事に `art` がある。
  5. `art.scene.prologue_then` は作らない(ページごとの絵は自由)。
- **`art == nil` のとき 2 は検査しない**(1・3・4 は検査する)。公開の層・今の非公開の層(絵の欄を使っていない/絵を調達していない)で、これらが 1 つも出ないこと。
- 一覧を渡す側: `ArtSeal.collect(layer:)` の `keys`。層に `art/` ディレクトリがあるときだけ渡し、無ければ `nil`(= 調達していない)。呼び出しは非公開の層の試験(U14 の側)に任せる。公開の層はいつも `nil`。

### 2.5 本体の試験(`Tests/AcceptanceTests/ArtWiringTests.swift` を新規。データは `TestContent.publicOnly()` に `ContentLoader.apply(json:to:)` で足す。`StageSceneTests` と同じ流儀。文は「試験の一行目」のような中身の無い文)
1. 全画面の場面: `scene.art` が `PrologueView.art` に出る。`then` の次のページは自分の `art`(無ければ nil)。ページが替わったフレームで前の絵が残らない。
2. 話し手の立ち絵: `scene.art` が無く、話し手の見え方が `Variant.art` を持つとき、今の行の話し手の絵が出る。話し手が替わる行で絵が替わる。`scene.art` があれば `scene.art` が勝つ。話し手の見え方が事実で切り替わる試験の人物(開示の前は `art` なし・後は `art` あり)で、**開示の前は nil、`learns` で知った行から出る**。
3. `bubble` の場面に `art` が付いていても、`Frame.prologue == nil`・`sceneLines` は今どおり・どの欄にも絵が出ない。
4. 決断: `EventDef.art` が `DecisionView.art` に出る。無ければ nil。`DecisionView` の `==` が絵だけの違いで偽になる。
5. **絵は遊びを変えない(INV-ART1)**: 同じ種・同じ入力の列(場面を最後まで送る・決断を選ぶ・`tick` 数百回)を、(a)`art` の付いた内容 と (b)同じ内容から `SceneDef.art`・`EventDef.art`・`Variant.art` を全部消した内容 に流し、毎ステップの世界の保存の出力(`SaveCodec.encode`)が**同じバイト列**、`Frame` は `prologue?.art`・`decision?.art`・`crew` の `art` だけ違う(それらを nil に直して比べると等しい)。
6. **今のコンテンツは同じ出力(INV-ART2)**: 公開の層を読み、`scenes`・`events` を `.sortedKeys` で JSON に書いた文字列に `"art"` が無い。既存の試験(`StageSceneTests`・`PrologueTests`・凍った保存の見本の往復)は 1 つも書き換えずに通る。
7. 検証: `art.form`(大文字を含む ID)・`art.exists`(集合に無い ID)・`art.bubble`・`art.event.nochoices` がそれぞれ当たる。`art: nil` のとき `art.exists` は出ない。公開の層は `validate(db)` でも `validate(db, art: [])` でも `art.*` が 0 件(絵の欄を使っていないので)。
8. 封: 試験の中で `ArtSeal.collect(layer:)` 用の一時の層に `art/t01.png`(1×1 の単色)を書き、`collect` → `seal` → `open` が同じ中身(既存の `ContentTests` の形に 1 件足す)。その `keys` を `validate(art:)` に渡し、`t01` を指す場面は通り、`t02` を指す場面は `art.exists`。

## 3. 画面(ReForge。macOS の CI でしかコンパイルされない。型と API の名前は目で確かめ、報告に書く)

### 3.1 `ArtView` と `ArtProvider`(`Theme/ArtProvider.swift`。持ち主: この単位)
```swift
enum ArtStyle { case full, scene }
struct ArtView: View {
    let id: ArtID
    var style: ArtStyle = .full     // 既定 .full = 今の見た目(仲間のタブ)。変えない
}
```
- `.scene`: 素材の縦横比(高さ/幅)が **2.0 以上**(縦長の全身。11:25 ≒ 2.27)なら、上から 45% を切り出して(幅いっぱい・上そろえで `clipped`)出す。2.0 未満(山場の絵など)なら全体を `scaledToFit`。どちらも `accessibilityHidden(true)`。絵が無ければ何も描かず、場所も取らない(既存どおり)。
- `ArtProvider` に、画面の側の差し替え口を足す(DEBUG だけ): `init(files: [ArtID: Data], failed: Bool = false)` と `#if DEBUG static func install(_ p: ArtProvider)`(`shared` を差し替える。`shared` を `private(set) static var` にする)。本番の経路(`init(bundle:)`・`ContentKey`)は変えない。
- 呼ぶ側(§3.2・§3.3)は、`ArtProvider.shared.image(id) != nil` を先に確かめ、非 nil のときだけ絵の区画・余白・`HStack` を作る。`art` が非 nil でも封が開かなければ「絵なし」と同じレイアウトにする(`ArtView` が何も描かなくても、包む側の余白や区画が残ると空の枠になるため)。

### 3.2 全画面の場面(`Game/PrologueScene.swift`・`ReForgeApp.swift` の 1 か所)
- `PrologueScene` に `var art: ArtID? = nil` を足し、`RootView` が `prologue.art` を渡す(2 か所の呼び出し。終わりの移りの `exitingScene` も同じ)。
- `art` が非 nil で `ArtProvider.shared.image(art)` が非 nil のときだけ、**絵の区画**を作る。そうでなければ**今のレイアウトのまま(1 ピクセルも動かない)**。
  - 絵の区画: 画面の上寄り(安全域の内側。上の余白 `height × 0.06`、高さ `height × 0.34` まで、幅は画面の幅から左右 32pt ずつ引いた分まで)に中央そろえで `ArtView(id:, style: .scene)`。タップは通す(`allowsHitTesting(false)`。画面のどこを押しても送りになるのは今のまま)。
  - 区画ができる間だけ、文の塊(`textBlock`)の上の余白を `height × 0.2` から `height × 0.46`、高さを `height × 0.5` から `height × 0.42` に替える。行の位置・折り返し・古い行が薄れて流れる規則・`▼` は今のまま。**絵が有るページから無いページへ替わったとき、文の塊は元の位置に戻る**(絵のあるページの間は動かない)。
  - 浮かび方: 絵はそのページの最初の行と一緒に 0.4 秒で浮かぶ(`accessibilityReduceMotion` が true なら浮かべず出す)。同じページの次の行では絵を動かさない。
- 読み上げ: 場面の読み上げのラベル(行をつないだもの)は変えない。絵は読み上げに出さない(`accessibilityHidden`)。絵が替わっても `AccessibilityNotification.Announcement` は増やさない。
- 識別子: 絵の区画に `accessibilityIdentifier("sceneArt")`(UI テスト用。要素は読み上げの 1 要素の外に重ねる。`prologueLine-N` と同じ DEBUG の作り方でよい)。
- 動きを減らす・終わりの移り(`runExit`)は今のまま。絵は場面の `sceneOpacity` に従って一緒に消える。

### 3.3 決断の帯(`Game/MapActionBand.swift`。この単位は決断の分岐の中だけ触ってよい)
- `decision.art` が非 nil で `ArtProvider.shared.image(...)` が非 nil のときだけ、問いの文(`decisionPrompt`)の左に 56pt 角の切り出し(`ArtView(style: .square)` を `frame(width: 56, height: 56)`。`.scene` は縦横比を保って収めるので正方形を埋めない(10/22 CI で 54.7×56 になった))を置く。問いの文が nil のときは、選ぶボタンの上の行に、左そろえで 56pt 角だけを置く。
- 絵が無い・開かないときは `VStack` の中身も余白も今と同じ(`HStack` で包むのは絵のあるときだけ)。選ぶボタンの並び・高さ・`decisionBand` の識別子・`decide` は変えない。帯が地図の枠を動かさない(今のまま)。
- 絵は押せない(ボタンにしない・タップを受けない)。識別子 `decisionArt`。

### 3.4 先読みはしない(報告に測りを書く)
- 絵の先読み・縮小デコードはこの単位でしない。`ArtProvider.image(_:)` は今のまま、最初の 1 回だけ `UIImage(data:)`(描画時にデコード)。
- 代わりに、`ScreenshotMode` の絵の起動(§4)で、場面に絵が出るフレームの最初の描画に何 ms かかったかを、DEBUG のログに 1 行出す(`PerfProbe` が既にあればそれ。無ければ `Date()` の差で十分)。16ms を超えるなら、報告の「決めかねたこと」に書く(PERF-01 の枠で扱う。この単位で直さない)。

### 3.5 画面の約束
- アプリに日本語のリテラルを足さない(この単位の画面の文は無い)。`python3 tools/gen-xcstrings.py --check`・`tools/check-app-strings.py` が通る。
- `GameStore` は `Frame.prologue`・`Frame.decision` をそのまま持つ(`decision != f.decision` の比較は `==` が絵を含むので変更不要)。`GameStore.swift` を触らない。
- `check-app-switches.py`: 新しい enum の case は足さない(`ArtStyle` はアプリの側の enum)。

## 4. 画面の試験(macOS の CI。`ReForgeTests`・`ReForgeUITests`)
- 試験用の絵: 試験の中で `UIGraphicsImageRenderer` で作った単色の PNG(`Data`)を `ArtProvider(files:)` に渡して `ArtProvider.install` する。縦長(110×250)と横長(200×120)の 2 枚。ファイルは何もコミットしない。
- `ReForgeTests/ArtProviderTests.swift`(新規):
  1. `image(_:)` は入れた ID で非 nil、無い ID で nil、壊れた `Data` で nil(落ちない)。`failed` の旗が `init(files:failed:)` のとおり。
  2. `ArtView(style: .scene)` の切り出し: 縦長は上から 45%(出力の高さ ÷ 幅 ≒ 0.45 × 2.27 ≒ 1.02)、横長は全体(高さ ÷ 幅 ≒ 0.6)。`ArtView(style: .full)` は今と同じ(縦横比のまま)。
- `ScreenshotMode`(DEBUG)に起動引数 `-ReForgeScreenshotArt present|missing` を足す(`stage` と `decisionBand` の画面にだけ効く。引数が無ければ今の 80 枚は 1 枚も変わらない)。
  - `present`: 上の 2 枚を `install` し、`stage` は `PrologueSample` の見本の `PrologueView` に `art`(縦長)を付けて出す。`decisionBand` は `content.events["event.test.decision"]` に `art`(縦長)を付ける(`ScreenshotMode` の中で DEBUG だけ。`startScreenshotGame` が `structure.fence` を書き換えるのと同じ流儀。公開の層のファイルは変えない)。
  - `missing`: `art` の ID を付けるが、`install` する提供元は空(= 封が開かない/調達していない)。
- `ReForgeUITests/ArtWiringUITests.swift`(新規。`ScreenSnapshotTests` の 80 枚には入れない):
  1. `stage` + `present`: `sceneArt` が存在し、その frame が画面の中・文の最初の行(`prologueLine-0`)の frame と重ならない。タップで次の行へ送っても `sceneArt` の frame は動かない。画面のどこを押しても送れる(絵の上でも)。
  2. `stage` + `missing` と `stage`(引数なし)で、`prologueLine-0…2` の frame が **等しい(誤差 0.5pt 以内)**。`sceneArt` は存在しない。
  3. `decisionBand` + `present`: `decisionArt` が存在し、frame が 56pt 角・画面の中。`decisionPrompt`・選ぶボタンが画面の中。`decisionBand` + `missing` と引数なしで、`decisionBand` の frame の高さが等しい。
  4. 動きを減らす設定(`-UIAccessibilityReduceMotion`)でも 1〜3 が通る。
  5. 5 言語(`ja`・`en`・`zh-Hans`・`zh-Hant`・`ko`)のうち 2 言語以上で 1 と 3 を回す(文が長い言語で絵と重ならないことの確かめ)。

## 5. 他の単位と同じファイルを触る所(衝突のしかた)
並行して進む単位: PT-B3(反応・音)・PT-B4(行動の記録)・W-24(工業の最初の記録)・ゼロ開始(`StartDef.opening`)。**この単位は次の範囲だけ**を触る。それ以外の行は書き換えず、整形もしない。

| ファイル | この単位が触る範囲 | 同じファイルを触る単位 | 衝突したら |
|---|---|---|---|
| `RFContent/Schema/Defs.swift` | `SceneDef` の末尾 1 欄・`EventDef` の末尾 1 欄 | W-24(別の型を足す)・ゼロ開始(`StartDef`)・PT-B4(別の定義かも) | 型ごとに離れている。両方残す |
| `RFContent/ContentValidator.swift` | `validate` の引数と末尾の 1 行・新しい関数 `artReferencesWellFormed` | ゼロ開始(V 規則を足す)・PT-B4(節目の規則を足す) | 呼び出しの並びの末尾はどの単位も足す。順序は問わず全部残す |
| `RFPresent/Frame.swift` | `DecisionView` の欄と `==`・`PrologueView.art` の doc | PT-B3(`Frame.pulses`)・ゼロ開始 | `Frame` 本体の欄・init は触らないので離れている |
| `RFPresent/FrameBuilder.swift` | `prologue(_:_:)`・`decision(_:_:)` の 2 関数の中 | PT-B3(`build`・`decisionShown`)・ゼロ開始(`darkStart`・`unlocks`・`build`) | 関数の外は触らない。`decisionShown` は `DecisionView` の比較で出す想定だが、その比較は `==` を通るのでこの単位の変更で壊れない |
| `ReForge/Sources/ReForgeApp.swift` | `RootView` の `PrologueScene(...)` 呼び出し 2 か所に `art:` を足すだけ。`DEBUG` の `startScreenshotGame` は触らない(`ScreenshotMode` 側で内容を直す) | PT-B3(音の差し込み)・ゼロ開始 | 引数の足しだけなので両方残す |
| `Game/MapActionBand.swift` | 決断の分岐の中だけ | PT-B3(決断の帯が出た合図)の可能性 | 分岐の外は触らない |
| `Game/PrologueScene.swift` | `art` の引数・絵の区画・文の塊の位置の分岐 | なし(PT-B6 は入っている) | — |
| `Debug/ScreenshotMode.swift`・`PrologueSample.swift` | `-ReForgeScreenshotArt` の読み取りと見本の絵 | ゼロ開始(`zeroB0`・`zeroB1` を足す) | 画面の列挙には足さず、引数で効かせるので離れている |
| 触らない | `Simulation`・`EffectApplier`・`NarrativeSystem`・`SaveEnvelope`・`GameStore.swift`・`GameScreen.swift`・`MapCanvasView`・`FootCardView`・`StatusBandView`・`DayWrap.swift`(W-24)・`content/private`・`content/public`(公開の層のファイルは変えない) | | |

その他に触ってよい: `ReForgeCore/Tests/…`(新しい試験と、`DecisionView` の `==` が変わって直す所)・`docs/art/README.md` §6 の表に 1 行(場面と決断の絵の引き方は `SceneDef.art` / `EventDef.art` / 話し手の見え方・`ArtView(style:)` は画面の側)・`project.yml`(UI テストのファイルを足すなら)。

## 6. 受け入れのコマンド
```
~/.local/bin/rf-note-test . --filter 'AcceptanceTests.ArtWiringTests|AcceptanceTests.StageSceneTests|AcceptanceTests.PrologueTests|RFContentTests|RFPresentTests|RFPerceptionTests'
~/.local/bin/rf-note-test .                     # 全体(公開の層)。終了コード 0
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-app-strings.py
python3 tools/check-public-spoilers.py
python3 tools/gen-xcstrings.py --check
```
- note に ssh できなければ予備(hub): `~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter <テスト>`。hub では全体を回さない。
- 画面の試験(§4)は macOS の CI でしか回らない。枝を push して CI の結果を見る。ローカルで回せなければ「未実行」と書く(回ったことにしない)。
- 受け入れの合否: 本体の試験が全部通る・既存の試験を 1 つも書き換えていない(`git diff` で `Tests/` の既存ファイルの変更が `DecisionView` の `==` 関連だけ)・`check-public-spoilers.py` が 0・`ReForgeUITests` の既存の 80 枚が変わらない(引数なしの起動で)。

## 7. 約束(F §4)
- 公開リポジトリに物語の語を書かない。試験の文は中身の無い文(数字とラテン文字を序の場面の文に使わない: `scene.prologue.text` に当たる)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない。
- 新しい状態の項目を保存に足さない。浮動小数を本体に入れない(縦横比の 2.0 や 45% は画面の側だけ)。
- 絵のバイナリをコミットしない。

## 8. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(この作業場には非公開の層が無い。統合担当がマージの前に、絵の欄の無い今のデータと、U14 が絵の欄を使うデータの両方で回す)。
- 枝の名前・先頭のハッシュ・6 の結果(件数)・アプリの側で目で確かめた API の名前(iOS の版)・画面の試験の実行の有無・3.4 の測り・決めかねたこと。
