# N-03 物語の途中で画面全体に出す場面(`SceneStyle.stage`)と、行で知ること(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 出す時点の `integration-c` の先頭。
もと: 最初の 10 分の版(非公開の計画の SL-10・SL-14・SL-17・SL-19・SL-30。DEC-F10・F11)。**N-02 はこの単位に含める**(結末の後の場面も `stage` で出す。N-02 の別の型は作らない)。

## なぜ
物語の途中の大事な場面を、地図の上のふきだし(`bubble`)ではなく、序(PT-B6)と同じ画面全体で、1 行ずつタップで読ませたい。今の序の型(`prologue`)は「冒頭だけ・行に条件なし・ほかから始められない」の決まりで正しいので緩めず、**別の型を足す**。
あわせて、人の名前は、その人が名乗る行を読んだ後にだけ画面に出したい(名乗る前は「？」)。名前の出し分けは今の認識の層(人の `name` の見出しの見え方を、知っていることで切り替える)でできるので、本体に要るのは「この行を読んだら、これを知る」の 1 つだけ。

## 型
- `SceneStyle` に `stage` を足す。
- `SceneDef.Line` に `learns: [FactID]?` を足す。**その行が画面に出た時点で**(場面の始まりの最初の行・送りで次の行に移った時)、その事実を知る(効果 `learn(fact:)` と同じ処理・同じ来歴)。`bubble`・`prologue`・`stage` のどの場面でも効く。保存の形は変えない(場面の進みは今の形。知った事実は今の形で保存される)。
- 名前を伏せるのは**データの側**(U14): 人の `name` の見出しの見え方を「名乗りの事実を知っていれば名前、でなければ「？」」にする。本体は、仲間の一員になった(`join`)ことを名前の見え方の条件に勝手に足さない。

## 決まり(`stage`)
- 確かめ(`ContentValidator`): `stage` の行には `when` を置いてよい(始めた時に成り立たない行は飛ばす。ふつうの場面と同じ)。`stage` はふつうの場面の `then`・出来事の場面・効果 `startScene` から始めてよい。`stage` から `prologue` は始められない(序の 2 つの確かめ `scene.prologue.when`・`scene.prologue.start` は変えない)。
- 進み方: **タップで送る**(`.narrative(.advanceScene)`)。時間では進まない(`sceneTick` は `stage` を進めない)。最後の行の後の送りで終わり、`then` があれば続ける。
- 間は**時計が止まる**: `stage` の場面がある間、`Simulation.advance` は世界を進めない(序と違い、時計も回さない)。ほかの命令は `reason.scene.reading`(新しい文の ID。公開の層 5 言語に中立の文)で断る。効果からの出来事(`fireFromEffect`)は今の序と同じく通す。
- 時計の保留(PT-B8 の `clock.held`)とは別の仕組み。暗い場面の間に `stage` が始まっても、保留はそのまま。
- 話し手: `Line.speaker` があれば、その人の `name` の見出しを認識の層を通して出す(名乗る前は、データの見え方のとおり「？」)。

## Frame
- 今の `PrologueView` に `kind: Kind`(`enum Kind { case prologue, stage }`)と、行と同じ数の `speakers: [String?]` を足す。`stage` の場面の時も `frame.prologue` の欄で渡す。`stage` の間は、序と同じく、地図・帯・足元カード・暗い場面(`darkStart`)を出さない(今の序の分岐に `stage` も入れる)。
- `stage` で出す行は、序と同じく、読んだ所まで(`prefix(line + 1)`)。

## 画面
- `stage` も PT-B6 の `PrologueScene`(画面全体・安全域の外まで・角の設定を隠す・タップで送る)で出す。行の上に話し手の名前を小さく出す(`speakers` が nil の行は出さない)。地の色・文の明るさは序と同じ。
- 終わりの移り方: 序の「地図がノアのまわりから灯る」は**しない**(地図はもう見えているので、0.3 秒で場面を消すだけ。動きを減らす設定では即時)。
- `AppModel.activePrologue`・`cornerButtonVisible` は `stage` も序と同じに扱う。

## 名前の監査の口(テスト用。SL-30・TEST-F9)
- `RFTestSupport` に `FrameText.allStrings(_ frame: Frame) -> [String]`(Frame の中の、画面に出るすべての文字列を集める。`Mirror` で再帰してよい)を足す。非公開の層のテスト(U14)が「名乗る前のどの Frame にも、その名前の文字列が無い」を確かめるのに使う。公開の層では、試験の人の名前で確かめる。

## テスト(Linux。公開の層の試験の内容。文は中立)
- ふつうの場面 → `then` → `stage`、出来事から `stage`、効果 `startScene` から `stage` が始まる。
- `stage` の行の `when` が成り立たない行は出ない(2 行のうち 1 行だけ出る組)。
- タップで進み、時間では進まない。間は `advance` で `clock.now` が変わらず、ほかの命令が `reason.scene.reading` で断られる。終わると時計が動く。
- `learns`: 行が出た時に事実を知る(最初の行・送った後の行の両方)。試験の人の `name` の見え方を事実で切り替えるデータで、知る前の全部の Frame(`FrameText.allStrings`)に試験の名前が無く、話し手の欄は「？」。知った後は名前が出る。`join` だけでは名前は出ない。
- 序の 2 つの確かめは今のまま効く(序の行に `when` があればエラー)。
- 画面の写真: `ScreenshotMode` に `stage` を 1 枚足す(公開の層の試験の場面。話し手つき)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`(`SceneStyle`・`PrologueView.Kind` の case を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 凍った保存の見本(`save-v1-dev-*.json`)は作り直さない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
