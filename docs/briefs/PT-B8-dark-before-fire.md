# PT-B8 最初の行為の前は暗い場面(dev の hotfix)(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。**土台: `main` の 1d33989**。dev に早く入れる小さな単位。
なぜ: オーナーの決定(2026-10-02)「最初の行為(火を起こす)までは、地図を見せない」。時計の保留(`clock.held`)の間は、地図の無い暗い場面に、押せるボタンを 1 つだけ出す。押したら地図が開く。HF-01(保留の間に歩く)は、この形に置き換えて取り下げた。

## 本体(Linux で確かめる)
- 内容の `StartClockDef` に `firstAct: InteractionID?` を足す(暗い場面で出す行為)。`ContentValidator`: あれば `interactions` にあること。`held == true` で `firstAct` が無ければ警告(エラーにしない)。
- `Frame` に `darkStart: DarkStartView?` を足す。`DarkStartView { action: FootCard.Action }`。
  - 出す条件: `run.isActive`・`clock.held`・序の場面が無い(`prologue == nil`)・止める決断が無い・**出す行為がある**。
  - 行為: ノアのマスの足元カード(`FrameBuilder.footCard`)の行為のうち、`firstAct` があればそれ、無ければ最初の行為。行為が 1 つも無ければ `darkStart` は nil(地図をいつもどおり出す。詰まらせない)。
  - 押した命令は、今の足元カードと同じ(`GameStore.act`)。受け付けられれば今の `releasesHold` で保留が解け、次の Frame で `darkStart` が nil になる。本体の規則は変えない。
- 保存の形は変えない(`darkStart` は Frame だけ)。

## 画面(アプリ。main の形の上で)
- `GameScreen`: `store.darkStart` が非 nil の間は、地図・状態の帯・足元カード・タブを作らず、`DarkStartScene` だけを出す(序の層 `PrologueLayer` と同じ地の色 `InkColor.field`。安全域の外まで覆う)。
- `DarkStartScene`: 画面の下の 3 分の 1(親指の届く所。下端から安全域 + 72pt ほど)の中央に、行為のボタン 1 つ。高さ 56pt・幅 240pt(押せる範囲は 44pt 以上)。文字は行為の名前(`action.label`)。縁がゆっくり脈打つ(1.6 秒の周期で縁の不透明度 0.4 ↔ 1。動きを減らす設定では脈打たず、強調の色の縁のまま)。ほかの文字や絵は出さない。
  - 行為が押し続ける形(`hold`)・続く形なら、足元カードと同じ押し方と、ボタンの下に進みの細いバー(`progressPermille`)。
  - 断られたら(`store.notice`)、ボタンの上に 1 行(足元カードと同じ文)。
  - 識別子: `darkStartScene`・`darkStartAct`。
- 開く移り: `darkStart` が nil になったら、地図が 0.8 秒でノアのまわりから外へ灯る(地図の不透明度とノアを中心にした円の切り抜きを広げる)。動きを減らす設定では 0.3 秒のフェード。序から暗い場面へは、地の色が同じなので、序の文字が消えるだけ。
- 撮る起動(`ScreenshotMode`)に `darkStart` の画面を足す(公開の層の世界で `clock.held = true` にして開く)。`ScreenSnapshotTests` の画面の一覧にも足し、検査を 1 つ: 地図・帯・足元カード・タブの識別子が無い・`darkStartAct` が 44pt 以上で画面の下半分にある。

## テスト
- (Linux)公開の層の世界で `clock.held = true`・序なし → `darkStart` が非 nil で、行為はノアのマスの行為。`firstAct` を与えた内容ではその行為。行為の命令を送る(受け付け)→ 保留が解け、`darkStart` が nil。`held == false` なら nil。序の場面の間は nil。ノアのマスに行為が無ければ nil。
- (アプリ)`AppTests`: 保留の世界で `store.darkStart` が非 nil → `store.act(action, pressing: true)` → `refresh` の後に nil になり、時計が動く。序から始まる層では、序を読み終えた後に `darkStart` が非 nil(または行為が無く nil)であることだけ確かめる。
- 統合担当が非公開の層を重ねて回す(`firstAct` は非公開の層の担当に頼む)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。
- 静的: `check-app-switches.py`(画面の case を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 凍った見本 `save-v1-dev-*.json` は作り直さない。

## 統合の枝に入れる時(統合担当がやる。Codex はしない)
統合の枝には PT-B6(画面全体の序 `PrologueScene`)・L-10a(角の設定のボタン)がある。暗い場面は `PrologueScene` の地の色(`prologueGround`)で出し、序の終わりの移り(文字が消える 0.6 秒 → 黒 0.3 秒)の後に暗い場面へつなぎ、地図が灯る移りは暗い場面の終わりで行う。角の設定のボタンは暗い場面でも出す。PT-B5 の方向のボタンは地図が開いてから(地図が無い間は出ない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
