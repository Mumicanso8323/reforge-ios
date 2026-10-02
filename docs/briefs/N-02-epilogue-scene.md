# N-02 結末の後の暗い場面(場面の型 `epilogue`)(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭(PT-B6 の後。B6 の `PrologueScene` を使う)。
なぜ: 結末の後に、序と同じ暗い画面で 1 行を出したい(U14 の結末のデータ。中身は非公開)。今の本体では、序の型(`style: prologue`)の場面は、行に条件を置けず(`scene.prologue.when`)、ふつうの場面の `then` や結末からは始められず(`scene.prologue.start`)、時間では進まない。序の決まりは序のために正しいので緩めず、**別の型を足す**。

## 型
- `SceneStyle` に `epilogue` を足す。
- 確かめ(`ContentValidator`):
  - `epilogue` の場面の行には `when` を置いてよい(ふつうの場面と同じ。始めたときに成り立たない行は飛ばす)。少なくとも 1 行は条件なしか、条件が互いに補い合うことまでは確かめない(データの責任)。
  - `epilogue` の場面は、ふつうの場面の `then`・結末の効果・`startScene` の効果から始めてよい。`epilogue` から序(`prologue`)は始められない。`epilogue` の `then` は `epilogue` だけ。
  - 序の 2 つの確かめ(`scene.prologue.when`・`scene.prologue.start`)は変えない。
- 進み方: 序と同じく**タップで送る**(`.narrative(.advanceScene)`)。時間では進まない(`sceneTick` は `epilogue` を進めない)。最後の行の後の送りで場面が終わる。
- `epilogue` の間は、序と同じく、ほかの命令を `reason.scene.reading`(序の理由と同じ文の ID を使ってよい)で断り、時計は進めない。終わったら、結末の後の今の流れ(結末の画面・タイトルへ)に戻る。
- `Frame`: 今の序の表示(`PrologueView`)に `kind: prologue | epilogue` を足し、`epilogue` の場面のときも同じ欄で渡す(行・送りを待っているか)。

## 画面
- `epilogue` も、PT-B6 の `PrologueScene`(画面全体・安全域の外まで・角の設定のボタンを隠す・タップで送る)で出す。地の色は序と同じ。終わりの移り方は、序の「地図が灯る」ではなく、暗いまま 1.2 秒置いてから結末の後の画面へ。
- 序の見せ方の 3 案の設定(A・B・C)は、`epilogue` にも同じく効く。

## テスト
- (Linux)公開の層の試験の内容で: ふつうの場面 → `then` → `epilogue` の場面に移る / 結末の効果から `epilogue` を始められる / `epilogue` の行の `when` が成り立たない行は出ない(2 行のうち 1 行だけ出る組) / タップの送りで進み、時間では進まない / 間は命令が断られ、時計が進まない / 終わると結末の後の流れに戻る / 序の 2 つの確かめは今のまま効く(序の行に `when` があればエラー)。
- 公開の層の試験の場面は中立の文(「試験の終わりの一行」など)。画面の写真 `epilogue` を 1 枚足す(ScreenshotMode)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す(U14 の結末のデータは、この単位が入ってから置く)。
- 静的: `check-app-switches.py`(`SceneStyle` に case を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 保存の形は変えない(場面の進みは今の形)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
