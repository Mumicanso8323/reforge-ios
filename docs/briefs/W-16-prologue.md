# 説明書 W-16: 冒頭の文章(序)の本体と画面

作業の単位: 序盤 W-16(設計: reforge-plan `docs/plans/2026-10-02-opening-and-industry-depth.md` v0.5 の §2.8・DEC-O7・INV-O1・INV-O14・PRL-4・TEST-O21)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: W-01 の v0.5 の直し(integration-c に入った。`Simulation.releasesHold` が場面の送りで保留を解かない・`WorldFactory` が時計の止まった世界で始まりの出来事をその場で起こす)。土台: integration-c の先頭。
序の本文(`scene.r1.prologue.1〜3` と行ごとの注記)は U14 が非公開の層に書く。この単位は**型・規則・画面**だけ。公開リポジトリに序の本文を書かない。

## 1. 目的
ゲームの始まりに、序の 3 ページと目覚めを、黒い地図の上に 1 行ずつ出す。押すたびに 1 行進む。時計は止めたまま。読み終えた同じフレームで地図が灯り、足元カードに最初の行為が出る(INV-O1)。

## 2. 本体(ReForgeCore)

### 2.1 RFContent(`Schema/Defs.swift` の `SceneDef`)
```swift
public enum SceneStyle: String, Codable, Sendable { case bubble, prologue }
// SceneDef に足す(どちらも省略可。今のデータはそのまま読める):
public var style: SceneStyle?   // nil = .bubble(今の地図の上のふきだし)
public var then: SceneID?       // この場面の最後の行の次に、続けて始める場面(ページ送り)
```

### 2.2 RFNarrative(`NarrativeSystem.swift`)
- `advanceScene`: 最後の行の次で場面が終わるとき、`then` があれば、その場面を始める(`EffectApplier` の `.startScene` と同じ処理。来歴は今の場面の `origin` を引き継ぐ)。`then` が無ければ今までどおり終わる。
- `sceneTick`(時間で行を送る): `.prologue` の場面は時間で送らない(時計が動いていても)。
- 序の場面は資料・ノート・日誌に入れない(PRL-4)。今、場面の行を記録に残している所があれば、`.prologue` では残さない。

### 2.3 RFSim(`Simulation.apply`)
- いま流れている場面(`world.narrative.scene`)が `.prologue` の間は、`.narrative(.advanceScene)` と `.narrative(.fireFromEffect)` 以外のコマンドを、処理せずに `Rejection("reason.scene.prologue")` で断る(世界は 1 つも変えない)。
- `reason.scene.prologue` の日本語の文を公開の層の文言の表に足す(理由の文が並んでいる所。L-02 が入っていれば `content/public/text/ja/` の下)。文は物語に触れない一般の言い方(例:「いまは文を読んでいる」)。

### 2.4 RFContent の検証(`ContentValidator.swift` に `scenesWellFormed` を足す。規則の名前)
1. `scene.then`(error): `then` の先の場面がある。`then` の連なりが輪にならない。
2. `scene.prologue.start`(error): `.prologue` の場面は、(a) `start.events` に書かれた出来事が始める場面(出来事の `scene`、または効果の `startScene`)か、(b) ほかの `.prologue` の場面の `then` の先、からしか始まらない。ほかの出来事・効果・`then`(`.bubble` の場面からの)が `.prologue` の場面を始めていたら error(途中で地図を黒くしない)。
3. `scene.prologue.when`(error): `.prologue` の場面の行は `when` を持たない。
4. `scene.prologue.text`(error): `.prologue` の場面の行の日本語の文に、数字(0〜9 と全角の ０〜９)とラテン文字(A〜Z・a〜z と全角)が無い(TEST-O21 の (8) の一部。禁止語は今の監査が全段で見る)。
- 今の非公開の層(`.prologue` を使っていない)で、これらが 1 つも出ないこと(古いデータでそのまま通る)。

### 2.5 RFPresent
```swift
public struct PrologueView: Equatable, Sendable {
    public var lines: [String]      // このページの、いままでに出た行(0 行目から今の行まで。今の言語で組んだ文)
    public var waiting: Bool        // 次の送りを待っている(▼ を点滅させる)。序の間はいつも true
    public var art: ArtID?          // W-09 で使う。この単位ではいつも nil
}
// Frame に足す
public var prologue: PrologueView?  // 非 nil の間: 地図は黒・帯は空・足元カードとタブは出さない
```
- `FrameBuilder`: 今の場面が `.prologue` なら `prologue` を作る(行の文は今の場面の行を、今と同じ `Perceiver` で組む)。そのとき `sceneLines` は空、足元カードの行為は 0、タブは 0、帯の項目は 0、地図は全部「見ていない」(黒)にする。`.bubble` の場面は今のまま `sceneLines`。
- 序が終わった後のフレームは、今の最初の画面と同じ(足元カードに最初の行為 1 つ。TEST-O1)。

### 2.6 テスト(`Tests/AcceptanceTests/PrologueTests.swift` を新規。データは公開の層ではなく、テストの中で `TestContent.publicOnly()` を写して足す)
公開の層の `start` は変えない(今のテストの全部が序に断られないように)。テストの中で、`.prologue` の場面 2 つ(`scene.test.prologue.1` が 2 行で `then` に `.2`、`.2` が 1 行)と、それを始める出来事を作り、`start.events` と `start.clock.held = true` に入れた世界で確かめる(TEST-O21):
1. 最初の `Frame` の `prologue` が非 nil で 1 行。足元カードの行為 0・タブ 0・帯の項目 0・地図は黒。
2. 何も送らずに `tick`(実時間)を 600 秒ぶん呼んでも、行も時刻も変わらない。
3. 3 回送ると(1 ページ目の 2 行目 → 2 ページ目の 1 行目 → 終わり)、最後の送りの直後の `Frame` で `prologue` が nil、足元カードに最初の行為が 1 つ。その間 `clock.held` は true、時刻は始まりのまま。ページが替わったとき `lines` は新しいページの 1 行だけになる。
4. 序の間、歩く・行為・寝るのコマンドが `reason.scene.prologue` で断られ、世界のハッシュが変わらない。
5. 序の途中で保存して読み戻すと、同じ場面の同じ行から続く(`SaveCodec` の往復)。
6. 同じ seed で、序を最短で送った世界と、送りの間に `tick` を 1 万回挟んだ世界の、最初の行為の後のハッシュが等しい。
7. 検証: 2.4 の 1〜4 がそれぞれ当たる(輪・始まりの外から始める・`when`・数字とラテン文字)。公開の層の検証は error 0 のまま。
- TEST-O21 の (6)(言語を変えると同じ行が新しい言語で出る)は L-03 の後に足す。この単位ではしない。

## 3. 画面(ReForge。macOS の CI でしかコンパイルされない。型と API の名前は目で確かめる)
- 新しいファイル `ReForge/Sources/Game/PrologueLayer.swift`(持ち主: この単位。F §4 の画面の持ち主の表に 1 行足す):
  - 地図の領域いっぱいの黒(`InkColor` の地図の黒)の上に、中央に文の塊。行は左にそろえる。字は地図と同じ字体(`InkFont` の本文)、17pt、暗い暖色の白(`InkColor` にある近い色)。シート・ダイアログ・閉じる物は使わない。
  - 行は `Text(verbatim:)`(本体が組んだ文)。新しい行は 0.4 秒で浮かぶ(`accessibilityReduceMotion` が true なら浮かべずに出す)。最後の行の末に小さな `▼` を点滅させる(`Text(verbatim: "▼")`。ボタンではない)。
  - 層のどこを押しても `store.send(.narrative(.advanceScene))`。
  - 読み上げ: 塊を 1 つの要素にし、ラベルは今のページの行をつないだもの。`accessibilityAction(.default)` で送る。新しい行が出たら読み上げに知らせる(`AccessibilityNotification.Announcement`)。
- `GameStore`: `Frame.prologue` を持つ(`sceneLines` と同じ形で、`apply` の 2 か所に足す)。
- `GameScreen.swift`(持ち主は統合担当。この単位は次の 3 か所だけ触ってよい): `store.prologue != nil` の間は、`StatusBandView`・`BattleBandView`・`FootCardView`・`TabBarView` を出さず、地図の上に `PrologueLayer` を重ねる。`prologue` が nil に替わったら、黒を 0.8 秒で消す(地図が灯る)。設定のボタン(`settingsButton`。L-10 で足す)が画面にあれば、それは隠さない。
- アプリに日本語のリテラルを足さない(この単位の画面の文は全部、本体が組んだ文と `▼`)。`python3 tools/gen-xcstrings.py --check` が通ること。

## 4. 確かめのコマンド
```
~/.local/bin/rf-note-test . --filter 'AcceptanceTests.PrologueTests|RFContentTests|RFNarrativeTests|RFSimTests|RFPresentTests'
~/.local/bin/rf-note-test .                        # 全体(公開の層)。終了コード 0
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
python3 tools/gen-xcstrings.py --check
```
- note に ssh できなければ予備(hub): `~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter <テスト>`。hub では全体を回さない。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFContent/Schema/Defs.swift`(`SceneDef` と `SceneStyle`)・`ContentValidator.swift`、`ReForgeCore/Sources/RFNarrative/NarrativeSystem.swift`、`ReForgeCore/Sources/RFSim/Simulation.swift`、`ReForgeCore/Sources/RFPresent/`(`Frame.swift`・`FrameBuilder.swift`)、`ReForgeCore/Tests/`(新しいテストと、`Frame` の init が変わって直す所)、公開の層の文言の表(`reason.scene.prologue` の 1 行)、`ReForge/Sources/Game/PrologueLayer.swift`(新規)・`GameStore.swift`・`GameScreen.swift`(3 の範囲)、`docs/architecture/F-work-units.md`(画面の持ち主の表に 1 行)。
- 触らない: `content/private`・保存の形(`SaveEnvelope`・`schemaVersion`。場面の状態は今の `narrative.scene` のまま)・`MapCanvasView`・`MapScene`・`FootCardView`・`StatusBandView`(U13 の持ち物。隠すのは `GameScreen` の側で)・ほかの担当のタブのファイル。

## 6. 約束(F §4)
- 公開リポジトリに物語の語と序の本文を書かない。試験の場面の文は「試験の一行目」のような中身の無い文にする(数字とラテン文字も使わない。2.4 の 4 に当たるので)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない。
- 新しい状態の項目を保存に足さない。
- 浮動小数を本体に入れない(画面のアニメーションの秒は画面の側だけ)。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(この作業場には非公開の層が無い。統合担当がマージの前に、序の無い古いデータと U14 の序の入ったデータの両方で回す。F §4)。
- 枝の名前・先頭のハッシュ・4 の結果(件数)・アプリの側で目で確かめた API の名前(iOS の版)・決めかねたこと。
