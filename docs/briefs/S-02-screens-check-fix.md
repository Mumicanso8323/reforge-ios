# 説明書 S-02: 画面の写真の検査を直す

作業の単位: 画面の写真(`screen-snapshots.md` の続き)。CI の `ci/integration` の回で、`screens` のジョブが検査で落ちた分の直し。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: なし。土台: integration-c の先頭。
アプリと UI テストは macOS の CI でしかコンパイルされない。Linux では確かめられないので、API の名前と型は目で確かめる。

## 1. CI で見えたこと(リーダーが写真と `screens/report.json` を見た)
1. `title` で、タイトルの「設定」の文字のボタン(frame 61,801 280x36)が識別子 `settingsButton` を持っている。そのため TEST-L16 の「右上の 52x52 の外」で落ちる。本物の設定のボタン(右上の角)は L-10 で入る。
2. 「右上の角に入っている」の検査が、画面全体の入れ物(frame 0,0 409x885)や、画面の中央の文字まで拾っている。原因は、角の範囲を `corner.union(settingsFrame)` にしているため(設定のボタンが角の外にあると、範囲が画面の大半に広がる)と、入れ物が葉として数えられているため。
3. `offscreen` に「識別子なし 43」が出る。幅 0 で文字の長さ 0 の要素。
4. `research` の写真が、拠点の頁の上のまま撮れていて、研究の節が写っていない。

## 2. 直すこと

### 2.1 タイトルの設定のボタンの識別子(`ReForge/Sources/Screens/TitleView.swift`)
- 今の文字のボタンの識別子を `titleSettingsButton` に替える。`settingsButton` は L-10 の右上の角のボタンだけが持つ(L-10 の説明書と F §4 の約束)。
- この識別子を使っている UI テスト(`ReForgeUITests/`)があれば合わせる。

### 2.2 角の検査(`ReForgeUITests/ScreenSnapshotTests.swift` の `inspect`)
- 角に入っているかを見る範囲は、右上の 52x52(`corner`)だけにする。`settingsFrame` との和を取らない。
- 数える要素は「葉」の中でも、次を外す:
  - 入れ物: 種類が `.other`・`.scrollView`・`.table`・`.collectionView`・`.group`・`.layoutArea`・`.layoutItem` のもの、または frame が窓の面積の 1/4 より大きいもの。
  - 設定のボタンそのものと、その中身(今のまま)。
  - アプリの印(今のまま: `screenshotGuard`・`inkFitReport`・`Ink…`)。
- 設定のボタンが無い画面(L-10 の前)は、今のとおり TEST-L16 を飛ばす。

### 2.3 `offscreen` の誤り(同じ関数)
- 幅か高さが 1pt 以下で、かつ文字の長さ(`label.count`)が 0 の要素は、`offscreen` の対象から外す(子は今のとおり見る)。
- 外した数は数えておき、`report.json` の画面ごとの行に `ignoredZeroSize` として出す(後で増えたら気づけるように)。

### 2.4 研究の写真
- 研究の節は拠点のタブの中にある(`BaseTab.swift` の `ResearchSection`。行の識別子は `research-<ID>`、隠れた件数は `researchHidden`)。
- 撮る起動(`ReForge/Sources/Debug/ScreenshotMode.swift`)で `research` のときは、拠点のタブを開いた後、研究の節が画面の上に来るように**アプリの側で**巻き取る(`ScrollViewReader` の `scrollTo`。節に `.id("researchSection")` を付ける。`#if DEBUG` の中で、`ScreenshotMode.screen == .research` のときだけ)。UI テストの `swipeUp` の繰り返しはやめる。
  - `BaseTab.swift` の持ち主は U18。触るのは `.id` と DEBUG の `scrollTo` の数行だけにし、コミットのメッセージに「U18 のファイル」と書く。
- 撮る世界で研究の節が出ない(`entries` が空で `hiddenCount` も 0)なら、それを `report.json` に `research: empty` として出し、テストは落とす(空の写真を撮って緑にしない)。公開の層の研究の定義(`content/public/research/research.json`)で節が出るはずなので、出ない場合は理由を報告に書く(データは変えない)。

## 3. 確かめ
- Linux では UI テストもアプリもコンパイルできない。次だけ回す:
```
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
python3 tools/gen-xcstrings.py --check
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); yaml.safe_load(open('project.yml'))"
```
- 本体(`ReForgeCore/`)には触らないので、swift test は要らない。
- 確かめの本番は、リーダーが手動の起動(`screens=true`)で回す CI。

## 4. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeUITests/ScreenSnapshotTests.swift`、`ReForge/Sources/Screens/TitleView.swift`(識別子 1 つ)、`ReForge/Sources/Debug/ScreenshotMode.swift`、`ReForge/Sources/Game/Tabs/BaseTab.swift`(2.4 の数行だけ)、`tools/collect-screens.py`(`ignoredZeroSize` と `research: empty` を report に通すなら)。
- 触らない: `ReForgeCore/`・`content/`・`.github/workflows/ci.yml` の release の名前・タグ・ipa の名前。

## 5. 約束
- 公開リポジトリに物語の語を書かない。アプリに日本語のリテラルを足さない(識別子は英字)。
- コミットのメッセージの末尾は、渡された 2 行の trailer。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(F §4。この単位は公開の層だけで撮るが、決まりどおり書く)。
- 枝の名前・先頭のハッシュ・3 の結果・目で確かめた XCUI の API の名前(`XCUIElement.ElementType` の case 名など)。
