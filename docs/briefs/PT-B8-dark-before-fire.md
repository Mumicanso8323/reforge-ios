# PT-B8 最初の行為の前は暗い場面(dev の hotfix)(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。**土台: `main` の 1d33989**。dev に早く入れる小さな単位。
なぜ: オーナーの決定(2026-10-02)「最初の行為(火を起こす)までは、地図を見せない」。時計の保留(`clock.held`)の間は、地図の無い暗い場面に、押せるボタンを 1 つだけ出す。押したら地図が開く。HF-01(保留の間に歩く)は、この形に置き換えて取り下げた。

## 本体(Linux で確かめる)
設計の決定(非公開の計画の序盤の設計 v0.9 の DEC-O8・§2.8.3 の 4): 保留を解くのは、最初の行為の**成功**(火が点いた)だけ。序の後・火の前は、ほかのゲームの命令を断る。地図は、火が点いた同じ Frame で初めて出る。

- 内容の `StartClockDef` に `firstAct: InteractionID?` を足す(暗い場面で出す行為)。`ContentValidator`: あれば `interactions` にあること。`held == true` で `firstAct` が無ければ警告(エラーにしない)。
- **断る**: `clock.held` で、序の場面が無く、`firstAct` がある間は、`Simulation.apply` は次の命令だけを受け、ほかは `Rejection("reason.start.first_act")` で断る: `firstAct` の行為(始める・押し続ける・離す)・`.narrative(.advanceScene)`・`.narrative(.fireFromEffect)`(効果の出来事)。文の ID `reason.start.first_act` を 5 言語で足す(ja「いまは、これしかできない」の程度の中立の文)。
- **保留を解く**: `firstAct` がある内容では、今の `releasesHold`(受け付けたら解く)を使わない。代わりに、`settle` の後で「`interacted(interaction: firstAct)` が出て、かつ建造物の火床が 1 つでも燃えている(`lit`)」なら保留を解く(同じステップの中で `clock.held = false`・`changes.mark(.clock)`)。火起こしが確率で失敗した時(効果の点火が外れた)は、保留のまま、ボタンが残る。`firstAct` が無い内容(公開の層・古いデータ)は今の `releasesHold` のまま。
- **押している間だけ進む**: 最初の行為は押し続けて時間のかかる行為(`hold`・`seconds`)なので、保留の間に進める必要がある。`Simulation.advanceHeld(_ world: inout WorldState, realSeconds: Double, carry: inout Int64) -> StepReport` を足す。
  - 条件: `run.isActive`・`clock.held`・ノアの進行中の行為(`exploration.active[.noah]`)が `firstAct`。欠けたら何もしない(世界を 1 ビットも変えない。読む速さ・待つ時間は世界に効かない)。
  - 歩みの数は今の `advance` と同じ換算。繰り越しは `world.clock.realCarry` を使わず、引数の `carry`(GameHost が持つ。保存しない。保留が解けたら 0)。
  - 1 歩で行うのは、ノアの `firstAct` の進み(`Interactions.advance` を人と行為で絞った口)と `settle` だけ。**時計・ほかの人・配属・消費・生存・敵・出来事の予定は進めない**。行為が終われば効果(火床を置く・点ける)が `settle` で効き、上の規則で保留が解ける。
  - `GameHost.tick(realSeconds:)`: 保留の間は `advanceHeld` を呼ぶ。
- `Frame` に `darkStart: DarkStartView?` を足す。`DarkStartView { action: FootCard.Action }`。
  - 出す条件: `run.isActive`・`clock.held`・序の場面が無い・止める決断が無い・出す行為がある。
  - 行為: ノアのマスの足元カードの行為のうち `firstAct`(無ければ最初の行為)。足元カードの行為の作り方(`FrameBuilder.footCard`)をそのまま使う(進み `progressPermille` も)。行為が無ければ `darkStart` は nil(地図をいつもどおり出す。詰まらせない)。
  - 地図の題(場所の名前)は暗い場面に出さない(ボタンだけ。オーナーの言葉どおり)。
- 保存の形は変えない(`darkStart` は Frame だけ。`carry` は保存しない)。始まりの一員や地図の開け方はデータの側(非公開の層の担当)。

## 画面(アプリ。main の形の上で)
- `GameStore.run`(と統合の枝の `clockStep`)の `guard clock.running` を `clock.running || clock.held` にする(保留の間も `host.tick` を呼ぶ。本体が、押していなければ何もしない)。
- `GameScreen`: `store.darkStart` が非 nil の間は、地図・状態の帯・足元カード・タブを作らず、`DarkStartScene` だけを出す(序の層 `PrologueLayer` と同じ地の色 `InkColor.field`。安全域の外まで覆う)。
- `DarkStartScene`: 画面の下の 3 分の 1(親指の届く所。下端から安全域 + 72pt ほど)の中央に、行為のボタン 1 つ。高さ 56pt・幅 240pt(押せる範囲は 44pt 以上)。文字は行為の名前(`action.label`)。縁がゆっくり脈打つ(1.6 秒の周期で縁の不透明度 0.4 ↔ 1。動きを減らす設定では脈打たず、強調の色の縁のまま)。ほかの文字や絵は出さない。
  - 行為が押し続ける形(`hold`)・続く形なら、足元カードと同じ押し方と、ボタンの下に進みの細いバー(`progressPermille`)。
  - 断られたら(`store.notice`)、ボタンの上に 1 行(足元カードと同じ文)。
  - 識別子: `darkStartScene`・`darkStartAct`。
- 開く移り: `darkStart` が nil になったら、地図が 0.8 秒でノアのまわりから外へ灯る(地図の不透明度とノアを中心にした円の切り抜きを広げる)。動きを減らす設定では 0.3 秒のフェード。序から暗い場面へは、地の色が同じなので、序の文字が消えるだけ。
- 撮る起動(`ScreenshotMode`)に `darkStart` の画面を足す(公開の層の世界で `clock.held = true` にして開く)。`ScreenSnapshotTests` の画面の一覧にも足し、検査を 1 つ: 地図・帯・足元カード・タブの識別子が無い・`darkStartAct` が 44pt 以上で画面の下半分にある。

## テスト
- (Linux)公開の層の試験の内容に、押し続ける試験の火起こし(`firstAct`。火床を置いて点ける効果。秒は短く)を足した内容で:
  - 保留・序なし → `darkStart` が非 nil で、行為は `firstAct`。`held == false` なら nil。序の場面の間は nil。ノアのマスに行為が無ければ nil。
  - 保留の間、歩く・ほかの行為は `reason.start.first_act` で断られる。
  - `firstAct` を押し始めて `GameHost.tick` を回すと、進みが増え、`clock.now` と `realCarry` は変わらない。離すと進みが止まる。
  - 終わって火が点いた同じ Frame で、保留が解け、`darkStart` が nil、時計が動き出す。
  - 点火の効果が外れる組(確率 0)では、終わっても保留のまま、`darkStart` が残る。
  - 何も押さずに `tick` を 100 回 → 世界(保存の形の JSON)が変わらない。
  - `firstAct` の無い内容は、今の規則(受け付けた最初の行為で解く)のまま。
- (アプリ)`AppTests`: 序から始まる層では序を読み終えた後、`darkStart` があれば押し続けて `run` か `clockStep` を回し、火が点いて `darkStart` が nil・時計が動く。公開の層では `firstAct` の試験の内容で同じこと。
- 統合担当が非公開の層を重ねて回す(`firstAct` と始まりの一員は非公開の層の担当)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。
- 静的: `check-app-switches.py`(画面の case を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 凍った見本 `save-v1-dev-*.json` は作り直さない。

## 統合の枝に入れる時(統合担当がやる。Codex はしない)
統合の枝には PT-B6(画面全体の序 `PrologueScene`)・L-10a(角の設定のボタン)がある。暗い場面は `PrologueScene` の地の色(`prologueGround`)で出し、序の終わりの移り(文字が消える 0.6 秒 → 黒 0.3 秒)の後に暗い場面へつなぎ、地図が灯る移りは暗い場面の終わりで行う。角の設定のボタンは暗い場面では隠す(DEC-F9: 「はじめから」から地図が出るまで、押せる物は暗い場面のボタン 1 つだけ)。PT-B5 の方向のボタンは地図が開いてから(地図が無い間は出ない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
