# HF-01 時計の保留の間も歩ける(dev の hotfix)(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。**土台: `main` の 1d33989**(統合の枝ではない。1 本の小さな単位)。最優先。
なぜ: オーナーの言葉「初めのマスから移動しようと思っても移動できない。1 マス分移動してそこでストップして、でも多分内部上は移動してなくて、別の場所をタップしてみたら初めの場所にいることになってて、またそこからその方向に 1 マス分移動して止まる」。

## 原因(確かめた)
1. 序の後、時計は最初の行為(火を起こす)まで保留(`clock.held`)。`Simulation.advance` は `!world.clock.held` で早く返るので、`CrewSystem.step` の `Walking.advance` が回らない。歩く命令は受け付けられ(`motion` が付く)、位置は動かない。
2. アプリの `GameStore.run` も `guard isActive, clock.running` で、保留の間は `host.tick` を呼ばない(Frame が来ない)。
3. 画面の補間 `ActorSprite.position(elapsed:)`(RFPresent/Camera.swift)は、Frame を受け取ってからの経過時間で進みを先へ延ばし、`to` のマスで止める。Frame が来ないので、絵だけ 1 マス先で止まる。次の Frame(別のマスのタップ)で、本当の位置(初めのマス)に戻って見える。

## 決まり(序盤の設計 §2.8.3・DEC-O7)
「時計は止まったまま。歩く・止まるでは動かない」は「歩いても時計を動かさない」の意味で、歩くこと自体は禁じていない。**保留の間は、時間を進めずにノアだけ歩ける**のが正しい形。

## 本体(Linux で確かめる)
- `Simulation` に `advanceHeld(_ world: inout WorldState, realSeconds: Double, carry: inout Int64) -> StepReport` を足す。条件: `world.run.isActive`・`world.clock.held`・`world.clock.phase == .day`・止める決断が無い・ノアに `motion` がある。どれかを欠けば何もしない(空の `StepReport`)。
  - 歩みの数は今の `advance` と同じ換算(`dayRealSeconds`・`SimStep.gameSeconds`・`maxRealSecondsPerAdvance`)で出す。ただし繰り越しは **`world.clock.realCarry` を使わず**、引数の `carry`(GameHost が持つ。保存に入れない。保留が解けたら 0 に戻す)を使う。世界の時計の繰り越しに触らないため。
  - 1 歩で行うのは、ノアの `Walking.advance`(今の `CrewSystem.step` と同じ速さの式)と、`Vision.update` と、霧の先を通る経路の引き直し(`Walking.replan`)だけ。それぞれを `CrewSystem` から呼べる静的な口(例: `CrewSystem.walkNoahOnly(&ctx)`)にまとめる。**時計(`clock.now`・日の残り)・タイマー・ほかの人・配属・消費・生存・敵・戦闘・出来事の予定は進めない**(`systems` の `step` を呼ばない)。
  - 歩いて出る出来事(`walked`・`arrived`)は、今のコマンドと同じく `settle` で配る(保留の間に受け付けたコマンドも今 `settle` している。同じ扱い)。ただし保留の間の `walked` は `staminaCost: 0` で出す(消費しない)。
  - 歩みの後に `Disclosure.record` を呼ぶ(`runSteps` と同じ)。
- `releasesHold` は変えない(歩く・止まるでは保留を解かない)。
- `GameHost.tick(realSeconds:)`: 保留の間は `advanceHeld` を呼び、歩みが 1 以上か出来事があれば Frame を作り直す。保留が解けたら `heldCarry = 0`。
- **守ること**:
  - 読む速さは世界に影響しない: ノアに `motion` が無ければ `advanceHeld` は世界を 1 ビットも変えない(何もしないで待つ時間は無関係)。
  - 決定性: 保留の間に変わるのは、プレイヤーの歩く命令の結果(ノアの位置・向き・見た範囲・開示)だけ。同じ命令の列と同じ歩みの数なら同じ世界。時計・乱数の列(`world.rng` を使う処理を呼ばない)は進まない。
  - 保存の形は変えない(`carry` は保存しない)。

## 画面(アプリ)
- `GameStore.run`(と統合の枝の `clockStep`)の `guard clock.running` を、`clock.running || clock.held` にする(保留の間も `host.tick` を呼ぶ。本体が「歩く人がいなければ何もしない」)。設定を開いている間(`isPaused`)は今のまま呼ばない。
- **見た目だけ進んで戻る形を出さない**: `Frame` に `actorsAdvance: Bool`(次の tick で本体が歩みを進めるか。`FrameBuilder` が、時計が走っている、または保留でノアが歩いている、で決める)を足し、`ActorSprite.position(elapsed:)` はそれが false なら補間で先へ進めない(`progress` のまま)。また、先へ進める時間に上限を付ける(`elapsed` は最大 0.25 秒まで。Frame が遅れても、来ていない歩みの先まで描かない)。

## テスト
- (Linux)公開の層: 新しい世界で `clock.held = true` にし、ノアの隣の歩けるマスへ `.crew(.walk)` を送ってから `GameHost.tick(realSeconds: 0.25)` を数回 → ノアの位置がそのマスになる・`clock.now` と `realCarry` が変わらない・`clock.held` が true のまま・食料などの在庫と仲間の位置が変わらない。
- (Linux)歩く命令を出さずに `tick` を 100 回 → 世界(保存の形に書いた JSON)が変わらない。
- (Linux)保留の間に歩いて着いた後、火を起こす → 保留が解け、そこから時計が進む。保留の間に歩いた世界と、同じ位置へ歩いた後に保留が解けた世界で、以後の 10 歩が同じ(決定性)。
- (Linux)`position(elapsed:)`: `actorsAdvance == false` なら `elapsed` によらず同じ位置・true でも `elapsed` 0.25 秒より先へは進まない。
- (アプリ)`AppTests`: 序の場面から始まる層では序を読み終え(`readThroughPrologue`)、そうでない層では `clock.held = true` の世界で、ノアの隣のマスへ歩く → `run` か `clockStep` を回して、`host.world` のノアの位置が変わる・時計が進まない。
- 統合担当が非公開の層を重ねて Linux とアプリのテストを回す。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 保存の形は変えない(凍った見本 `save-v1-dev-*.json` は作り直さない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
