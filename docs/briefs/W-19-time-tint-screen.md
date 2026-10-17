# 説明書 W-19: 時刻の色(画面)

作業の単位: 序盤 W-19(設計: reforge-plan `docs/plans/2026-10-02-opening-and-industry-depth.md` v0.7 以降の §6.7・INV-O16・INV-O17・TEST-O22・TEST-O24・UI-03)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: W-18(入っている。integration-d の 5da4e03: `RFContent/Schema/TimeTint.swift`・`RFPresent/TimeOfDay.swift`・`Frame.timeMark`/`timeTint`・`TileView.brightness`)。土台: integration-d の先頭。
**2 回に分ける**。A = 本体(hub で確かめる)→ B = アプリ(macOS の CI で確かめる)。A が通ってから B を渡す(B は A の型を使う)。

## 1. 目的
W-18 が作った時刻の色を、画面に出す。部品(帯・札・パネル・タブ・ボタン)は暗い地のまま、端末の外観にも時刻にも依らず同じ。時刻は地図の地形の層にだけ掛け、昼を 64 段に刻んだ**段が変わったときに 1 回だけ**描き直す。帯の日の残りには、目印の点 4 つ・今の印・目印の言葉を足す。画面の写真のジョブに、時刻 4 点とライトの外観の撮りを足す。

## 2. 読んで分かったこと(この説明書の根拠)
1. 地図の区画の絵の鍵は今 `(区画の番号, revision, 1 マスの大きさ, 昼夜, 視界の形)`(`MapScene.swift` の `TerrainImageKey`)。**視界の形が鍵に入っているので、ノアが 1 マス歩くたびに、見えている区画が全部 `ImageRenderer` で描き直される**。しかも `images` は鍵ごとに溜まり、捨てるのは視界の外に出た区画だけ(古い鍵の絵が残り続ける)。時刻の段をそのまま鍵に足すと、溜まる量も描き直しも増える。オーナーの「定期的に重なる」の見立ての本命はここ。
2. W-18 は `TileView.brightness` を区画の中に焼き込む。昼は「視界の中か外か」(`MapProjector.chunk` が `map.isVisible` を渡す)で値が変わる。ところが `FrameBuilder.build` の区画の指紋(`signature`)に視界も灯りの円も入っていない。**区画の revision が同じまま、歩くと焼き込んだ明るさだけが古くなる**。段が変わったときは全区画の revision を上げるが、知っているマスが 1 つも無い区画(描く時刻の色が何も無い)まで上げて、全部引き直させている。
3. アプリは `TileView.brightness` をまだ読まない(`TerrainChunkImage.paint` が `night`・`vision`・`TilePalette.remembered` で自分で決めている)。
4. 帯の日の残りは `StatusBandView.phase` の `.day` の枝の `ProgressView` 1 つで、`store.clock.showsDayLeft`(時計を止めている間・`band.day` の門が閉じている間は false)の中にある。`Frame.timeMark` はアプリのどこでも読まれていない。言葉の表 `ui.time.*` は無い。
5. `preferredColorScheme(.dark)` は `ReForgeApp.swift` と `SettingsCorner.swift` にある。`Info.plist` に外観の固定は無い(システムの警告・キーボードなどは端末の外観に従う)。
6. 画面の写真は `-ReForgeScreenshot <画面>` の 1 点の時刻(新しい世界・時計は止める)で、時刻の指定もライトの外観の撮りも無い。シミュレータの外観は指定していない。

## 3. 作るもの: A 本体(hub で確かめる。`ReForgeCore/`)

### 3.1 区画の revision を、焼き込んだ明るさに合わせる
- `MapProjector.brightnessClass(at: GridPoint, visible: Bool) -> Int` を足し、`tileBrightness` はこの区分から値を出す(値の決め方は 1 か所)。区分: 0 = 時刻を掛けない(未踏・手がかり)、昼は 1 = 視界の中・2 = 視界の外、夜は 3 = 灯りの円の中・4 = 縁・5 = 円の外。光る物(`glow`)は区分に入れない(`tileBrightness` が nil にする今のまま。光る見え方が変わるのは `.perception` で全区画が上がる)。
- `MapProjector.signature(_ r:, vision:)` に、**知っているマスの区分**を混ぜる(`build` は `map.vision` を渡す)。これで歩いて視界の縁をまたいだ区画、火床の段が変わって灯りの円が変わった区画だけ revision が上がり、ほかは上がらない。
- 段が変わったときの全区画の引き上げ(`previous?.timeTint.step != tint.step`)は、**知っているマスが 1 つでもある区画だけ**にする(`MapProjector.hasKnown(_ r:)` を足す)。`ChangeSet.perception` の全区画の引き上げは今のまま。
- `MapChunk` に `public var timeTint: TimeTint`(既定 `TimeTint.neutral`)を足し、`MapProjector.chunk` が自分の `timeTint` を入れる。区画はその区画の `brightness` を作ったのと同じ色味を持つ(取りに行く間に世界が次の段に進んでも、1 枚の区画の中で食い違わない)。`TimeTint.neutral`(明るさ 1000・色味なし・段 0)を足す。序の間に返す空の区画(`FrameBuilder.chunks` の序の枝)は `neutral`。

### 3.2 日の棒の点と、目印の言葉
- `TimeOfDay.dayBarDots(_ def: TimeTintDef, clock: ClockDef) -> [Int]`: 昼の長さ(`dayGameHours × 60` 分)に対する ‰ の位置を、昇順・重複なしで返す。作り方: 昼の中(`at` < 昼の長さ)の目印を `at` の順に見て、**`mark` が前の点と変わった点**の `at × 1000 / 昼の長さ`、最後に 1000(日没)。= 帯の言葉が替わる所と日没(INV-O16 と同じ表から作る)。公開の層の表なら `[0, 187, 750, 1000]`。`timeTint` の無い古いデータの既定の表なら `[0, 1000]`。
- `TimeOfDay.wordID(_ mark: TimeMark) -> TextID`: `switch` で `ui.time.dawn`・`ui.time.day`・`ui.time.evening`・`ui.time.night` を返す(ID を文字の連結で作らない)。
- `Frame.timeWord: String?`(既定 nil)。`FrameBuilder.build` が `content.texts[TimeOfDay.wordID(mark)]` を入れる(表に無ければ nil。**日本語の文字列リテラルを本体に書かない**)。
- `content/public/text/ja/time.json` を新規: `{"language": "ja", "texts": {"ui.time.dawn": "夜明け", "ui.time.day": "昼", "ui.time.evening": "夕方", "ui.time.night": "夜"}}`(形は同じ場所の `map_touch.json` に合わせる)。後の層が同じ ID を持てば後の層が勝つ。

## 4. 作るもの: B アプリ(macOS の CI で確かめる。`ReForge/`・`ReForgeTests/`・`ReForgeUITests/`・`project.yml`・`tools/`・`.github/workflows/ci.yml`)
アプリは Codex の作業場でビルドできない。書いたら import・型・`await` と `@MainActor` を目で 2 回通す。

### 4.1 地形の絵(`MapScene.swift`・`MapCanvasView.swift`)
- **鍵と控え**: `TerrainImageKey = (index, revision, cellSize, step)`。`step` は `chunk.timeTint.step`。`night`・`vision` は鍵から外す(明るさは区画の `brightness` に入っている。3.1)。`images` は**区画の番号ごとに 1 枚だけ**(`[Int: (key, image)]`)。鍵が替われば置き換え、積まない。`discardOutside` は今のまま番号で捨てる。
- **描き方**(`TerrainChunkImage.paint`。`night`・`vision` の引数を外し、`MapChunk` の `timeTint` を使う):
  - `fog` が `.unknown`/`.visible` は描かない。`.hint` は影の字を今の手がかりの色で描く(時刻を掛けない)。`.remembered` は `tile.brightness` が `b` なら、字の色も地の色も `chunk.timeTint.apply(色, brightness: b)`(`RGB.scaled` は使わない)。`b` が nil(光る物)は色のまま。
  - 色の決め方は純関数 `TerrainTileColors.resolve(style:point:brightness:tint:) -> (fg: RGB, bg: RGB?)` に出す(試験のため)。
  - 字の `resolve` の控え(`texts`)は今のとおり 1 回の描き(1 区画)の中だけ。段をまたいで持たない(色が段ごとに替わるので、持つと増える)。
- **時刻の描き直しを滑らかに**(`MapTerrainCache`):
  - `refreshBudget = 2`: 1 回の `drawTerrain` で、**すでに絵がある区画の作り直し**は 2 枚まで。超えた区画は古い絵を出し続け、`hasPending` を true にする。初めて描く区画(絵がまだ無い)は数えず、その場で描く(黒を見せない)。`drawTerrain` の頭で `beginPass()`。
  - `hasPending` の間は続きを描く: 地形の `Canvas` の描き終わりに `if cache.hasPending { DispatchQueue.main.async { terrainTick &+= 1 } }`(`@State terrainTick` を `body` で読む)。残りが無くなれば止まる。60fps の `TimelineView` は地形に使わない。
  - 失敗の扱い(`failedAt`・`directDrawn`・`hasInk`)は今のまま。鍵が替わったら失敗の記録も新しい鍵で数える。
- `MapScene.night` は置いた物の明るさ(`PlacementBrightness`)が使うので残す。人・置いた物・照準・経路の描きは**変えない**(時刻の色を掛けない。INV-O16)。
- DEBUG: `ReplayStats` に `terrainRenders`・`terrainDeferred` を足し、通しの台本の終わりの報告(`ReplayDriver` の mark の行)に出す。
- 描き直しの数の上限(決め): **区画の revision と段が変わらない限り 0 回。変わったら見えている区画につき 1 回**(2 枚ずつ数フレームに分ける)。

### 4.2 帯の日の残り(UI-03。`StatusBandView.swift`・新規 `DayBarView.swift`)
- `GameStore` に `timeMark: TimeMark`・`timeWord: String?`(`refresh` で `Frame` から、値が替わったときだけ写す)と `let dayBarDots: [Int]`(`init` で `TimeOfDay.dayBarDots(TimeOfDay.resolved(content.timeTint, clock: content.clock), clock: content.clock)`)。
- `StatusBandView.phase` の `.day` の枝の `ProgressView` を `DayBarView(elapsedPermille: 1000 - store.clock.dayRemainingPermille, dots: store.dayBarDots, word: store.timeWord)` に替える。**外側の `if store.clock.showsDayLeft` は今のまま**(門・止めている間の規則を変えない)。`.dusk`(「日没」)と `.nightWork`(「夜」)の枝は今のまま(決断の状態の語で、目印の言葉ではない)。
- `DayBarView`: 幅 80pt・棒の高さ 3pt の横の棒 1 本。**今の位置から右(残り)を `InkColor.dusk`、左(過ぎた分)を `InkColor.rule`**(今の「残りが縮む」の見え方を保つ)。棒の上に点(直径 4pt・`InkColor.textDim`)を `dots` の位置に 4 つまで、今の位置に細い印(幅 2pt・高さ 10pt・`InkColor.text`)。右に言葉(`Text(verbatim: word)`・`InkFont.small`・`InkColor.textDim`。`word` が nil なら言葉は出さない)。数字・時刻・説明を出さない。色は全部 `InkColor` の固定の札(時刻でも外観でも替えない)。
- `StatusFlowLayout` の子は 1 つのまま(棒と言葉を `HStack` にまとめる)。幅が足りなければ今と同じく次の行へ折り返す。
- 読み上げ: `accessibilityElement(children: .ignore)`・ラベルは `word`(無ければ空)・識別子 `dayBar`。点は `accessibilityHidden`。数は読み上げない(HNT-10)。
- **ゼロから始める**: この単位で、最初の画面に増える部品は無い。`dayBar` は今の `ProgressView` と同じ条件の中にだけある。`darkStart`(最初の行為の前)の写真に `dayBar` が無いことを UI テストで確かめる。説明・チュートリアル・理由の文・ダイアログは足さない。

### 4.3 部品は暗い地のまま固定(INV-O16)
- `project.yml` の `ReForge` の `settings.base` に `INFOPLIST_KEY_UIUserInterfaceStyle: Dark`(システムの警告・キーボードも含めて端末の外観を読まない)。`.preferredColorScheme(.dark)` は `ReForgeApp.swift`・`SettingsCorner.swift` に**残す**。
- `tools/check-fixed-dark.py` を新規(python3 標準だけ。`ci.yml` の `app-switches` ジョブで `check-no-reason-text.py` の隣に step を足す): (1) 上の 2 つのファイルに `.preferredColorScheme(.dark)`、(2) `project.yml` に上の 1 行、(3) `ReForge/Sources/` に `\.colorScheme`・`userInterfaceStyle`・`traitCollection` の読みが無い(`#if DEBUG` の中は除く)。外れたらファイル:行を出して終了コード 1。

### 4.4 画面の写真のジョブ(TEST-O24・TEST-O22 の (2))
- `ScreenshotMode`(`#if DEBUG`)に起動引数 `-ReForgeScreenshotTime <dawn|noon|evening|night>`(`-ReForgeScreenshot map` のときだけ)。`startScreenshotGame(time:)` が、時計を止めたまま世界の時刻を置く: dawn = 夜明けから 20 分、noon = 240 分、evening = 420 分、night = `nightWork` で 780 分(`darkMark` の世界と同じ、燃えている焚き火とその外の柵を置く)。`held` は false。
- `ReForgeUITests/TimeTintSnapshotTests.swift` を新規(1 クラス。`-ReForgeScreenshot map` を時刻 4 点で撮る)。外観は環境変数 `REFORGE_APPEARANCE`(`dark`/`light`)で名前を決めるだけで、**外観の切り替えは CI が `xcrun simctl ui <udid> appearance` でする**(`XCUIDevice.appearance` に頼らない)。1 枚ごとに、添付 `time_<点>_<外観>`(PNG)と `timehash_<点>_<外観>`(JSON)を残す。JSON の中身: 地図の枠の外のすべての画素の SHA-256(上の安全領域の帯は除く)・タブの帯の画素の SHA-256(`tab-*` の識別子の要素の和の枠)・地図の枠の中の SHA-256・予約の赤の画素の割合・`dayBar` の有無・`dayBar` のラベルに数字が無いこと。予約の赤の判定は本体の整数の式(`TimeTintPalette.isReservedRed` と同じ。`r` が最大・`10×|g−b| ≤ 3×差`・`2×差 ≥ 255−|最大+最小−255|`)をテストの中に写す。
- `tools/collect-screens.py`: `timehash_*` を `screens/time-report.json` に集め、`time_*.png` 8 枚が無ければ失敗(今の 60 枚の数え方は変えない)。`tools/check-time-tint-shots.py time-report.json` を新規: ① 点ごとにダークとライトで「地図の外」の SHA-256 が同じ(TEST-O24 の本体)、② 全 8 枚でタブの帯の SHA-256 が同じ、③ 点ごとにダークとライトで地図の中が同じ、ダークの中で 夜明け≠昼・昼≠夕方・夕方≠夜(地図に色が掛かっている)、④ 予約の赤の割合が全部 0.1% 未満、⑤ `dayBar` は夜明け・昼・夕方にあり夜に無い、ラベルに数字が無い。外れたら点と外観を出して終了コード 1。
- `ci.yml` の `screens` ジョブ: 今の「画面の写真を撮る」に `-skip-testing:ReForgeUITests/TimeTintSnapshotTests` を足す。その後に step を 2 つ(ダーク → ライト): `xcrun simctl ui $UDID appearance <外観>` → `TEST_RUNNER_REFORGE_APPEARANCE=<外観> xcodebuild test-without-building … -only-testing:ReForgeUITests/TimeTintSnapshotTests`(序の動画の step と同じ形)。最後に外観をダークへ戻す。「添付を取り出す」の後に `check-time-tint-shots.py` の step(`if: always()`)。artifact に `time_*.png` を足す。
- `ScreenSnapshotTests.assertDarkStart` に `dayBar` が存在しないことの 1 行。

## 5. テスト

### 5.1 本体(hub。`Tests/RFPresentTests/TimeOfDayScreenTests.swift` を新規)
1. `dayBarDots`: 公開の層の表で `[0, 187, 750, 1000]`。古いデータの既定の表で `[0, 1000]`。どちらも昇順・重複なし・先頭 0・末尾 1000。
2. 言葉: 昼と夜の全部の段で、`Frame.timeWord == content.texts[TimeOfDay.wordID(Frame.timeMark)]`(日本語の文字列を直に比べない)。`ui.time.*` の無い内容では nil。
3. **revision が同じなら中身も同じ**(性質の試験): 昼に、ノアを数マス歩かせながら(視界の縁が区画をまたぐ)・段をまたぎながら・夜に火床の段を変えながら、毎回 `build(previous:)` して全区画を引き直す。前の Frame と revision が同じ区画は、引き直した `tiles` と `timeTint` が前に引いたものと**完全に等しい**。
4. 段が変わると、知っているマスのある区画の revision だけが上がり、知っているマスが無い区画は上がらない。ノアが歩くだけ(同じ段)では、視界の縁をまたぐ区画以外は上がらない。
5. 区画の `timeTint` が、その区画を作ったときの世界の時刻のもの(`Frame` の `timeTint` と同じ段で等しい)。序の間の空の区画は `neutral`。
6. W-18 の `TimeOfDayTests` が今のまま通る。

### 5.2 アプリ(macOS の CI。`ReForgeTests/TimeTintScreenTests.swift` を新規)
1. **段 1 つにつき 1 区画 1 回**: 区画 4 つで、同じ鍵を 120 回引いても `renderCount` は区画ごとに 1。`revision` と `timeTint.step` を 1 上げた区画を引くと、その区画だけ 1 増える。
2. **控えの上限**: 段を 10 回替えても、控えの数は区画の数を超えない(区画の番号ごとに 1 枚)。
3. **分けて描く**: 4 枚が全部古い状態で、1 回目の `drawTerrain` は 2 枚だけ作り直し `hasPending` が true、2 回目で残り 2 枚、3 回目は 0 枚で `hasPending` が false。区画ごとの作り直しは合計 1 回。絵がまだ無い 4 枚は 1 回目に全部作る。
4. `TerrainTileColors.resolve`: `brightness` nil なら元の色、`b` なら `timeTint.apply(元の色, brightness: b)` と等しい。強さ 0・明るさ 1000 なら元の色。
5. `GameStore`: 世界を 1 段進めた Frame を取り込むと、知っている区画の `chunk.timeTint.step` が Frame の `timeTint.step` に追いつく。`timeWord` が値の替わったときだけ更新される。
6. 画面(UI テスト): 4.4 の ①〜⑤。`darkStart` に `dayBar` が無い。

## 6. 確かめのコマンド
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 --memory=3g --memory-swap=3g -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter 'TimeOfDay|RFContentTests'
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/gen-xcstrings.py --check
python3 tools/check-no-reason-text.py
python3 tools/check-fixed-dark.py
python3 tools/check-public-spoilers.py
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
```
- hub では全体を回さない。note へ ssh しない(`rf-note-test` は使わない)。
- B は統合担当が macOS の CI(`ci/integration` の手動起動。`run_app_tests` と `screens` を true)で確かめる。実行の番号を終わりの報告に書く。

## 7. 触ってよいファイル / 触らないファイル
- A: `ReForgeCore/Sources/RFPresent/`(`TimeOfDay.swift`・`Frame.swift`・`FrameBuilder.swift`・`MapProjection.swift`)、`ReForgeCore/Tests/RFPresentTests/`、`content/public/text/ja/time.json`。
- B: `ReForge/Sources/Game/`(`MapScene.swift`・`MapCanvasView.swift`・`StatusBandView.swift`・`DayBarView.swift` 新規・`GameStore.swift` の `timeMark`・`timeWord`・`dayBarDots` だけ)、`ReForge/Sources/Debug/`(`ScreenshotMode.swift`・`ReplayDriver.swift` の統計)、`ReForgeApp.swift` の `startScreenshotGame` の引数、`ReForgeTests/`・`ReForgeUITests/`、`project.yml`(1 行)、`tools/`(新規 2 本と `collect-screens.py`)、`.github/workflows/ci.yml`(上の step だけ)。
- 触らない: `content/public/world.json` の `timeTint` の数(art-director が 4 点の写真を見て詰める。この単位では替えない。検証に当たるときだけ報告する)・`content/private`・保存の形・`Vision.swift` の規則・`Theme/` の色の札・人と置いた物の描き(`drawMoving`)・`.dusk`/`.nightWork` の帯の語。

## 8. 約束(F §4)と、この単位でやらないこと
- 公開リポジトリに物語の語を書かない。画面の固定の日本語は新しく足さない(目印の言葉は表から)。
- 時刻の色の計算に浮動小数を使わない(`TimeTint.apply` の整数だけ)。
- 説明・チュートリアル・理由の文・確認のダイアログを足さない。最初の画面の部品を増やさない。
- やらない(先送り。理由つき): ① 「寝る」で夜明けに飛ぶときの 0.8 秒の移し(設計 §6.7.1)。地形の 2 枚を重ねる描きが要り、主スレッドの描きを増やす。飛ぶ所では帯の語も替わるので、まず即時の切り替えで確かめる。② 昼の視界の縁の暗さを区画の絵から分ける作り。歩くたびに縁の区画が 1 枚ずつ描き直るが、今(見えている区画が全部)より少ない。実機の値は `ReplayStats` で測ってから決める。

## 9. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(統合担当がマージの前に、非公開の層を重ねて回す。`ui.time.*` を非公開の層が持つ・持たないの両方で)。
- A と B を別の報告にする。枝の名前・先頭のハッシュ・5.1 の件数・5.2 を書いた箇所(CI で回す前に目で通した所)。
- 4.1 の描き直しの数(5.2 の 1・3)と、`terrainRenders`・`terrainDeferred` が通しの台本で出した値(CI の記録から)。
- 予約の赤の割合(4.4 ④)が 0.1% を超えたら、時刻のせいか地図の色の表のせい(W-17)かを、4 点の数の比べで書く。
