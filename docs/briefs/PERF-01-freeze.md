# PERF-01 操作中に止まる・重なるを減らす(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の 0046e96(PT-B8 の取り込みの後)。
なぜ: オーナーの報告「画面操作中に、定期的に重なってフリーズし、しばらくして動く」。コードを読んだ見立て(見込みの高い順):
1. 本体の 1 歩と Frame の作り直しが重い時に、命令が後ろに並ぶ(GameHost は actor。重い 1 歩の間、タップの `await host.apply` が待つ)。
2. 主スレッドで保存の JSON を作って書く(`saveResume`・`saveDawn`。日没・夜明け・背面のたび。来歴が増えるほど長い)。
3. 動く人が 1 人でもいる間、地図の全マスを毎フレーム描き直す(TimelineView 60fps + Canvas)。

この単位は 3 つの小さな直しを入れる。挙動(ゲームの規則・保存の形)は変えない。

## (a) 重い 1 歩を記録する
- `GameStore.clockStep` で `host.tick` の前後の時刻(`ContinuousClock`)を取り、50ms を超えたら記録する: `Logger`(サブシステム `reforge`・カテゴリ `perf`)に 1 行(ms・歩みの数・Frame を作り直したか)と、`os_signpost` の区間(Instruments で見る)。
- 同じ値を `GameStore.slowSteps`(直近 20 件の輪。DEBUG と dev のビルドだけ)に入れ、設定の「開発」の節に「重い歩み: 件数・最長 ms」の 1 行を出す(dev の版でオーナーの端末から読めるように)。
- 命令の待ち: `GameStore.send` から `host.apply` が返るまでが 100ms を超えたら、同じく 1 行(`kind: apply`)。
- PT-B4(遊びの記録)が入ったら、この 2 つを記録の `step`・`apply` の行に流す口(`PerfSink` プロトコル。今は Logger だけの実装)にしておく。

## (b) 保存を主スレッドの外へ
- 保存の JSON を作る所(`SaveCodec.encode`)と書く所(`FileSaveStorage.write`)を、主スレッドで呼ばない。
- 形: `GameHost` に `func saveData(slot: SaveSlot, stamps: [ContentStamp]) throws -> Data`(actor の中で世界を写さずに encode)を足す。書くのは新しい `actor SaveWriter`(1 本の列。書く順を保つ。`FileSaveStorage` を持つ)。`GameStore.saveResume`・`saveDawn`(`SaveBook.autosaveDawn` の書き込み)・手動の保存は、`host.saveData` → `saveWriter.write` の順に await する(主スレッドは待つだけで、作る・書くはしない)。
- 背面に回った時: `UIApplication.beginBackgroundTask` の中で書き終える(終わったら end)。
- 夜明けの枠の数の整理(直近 3)などの今の決まりは変えない。テストの `FileSaveStorage` の使い方も変えない(`SaveWriter` は差し替えられる)。

## (c) 地図は動いた所だけ描き直す
- 地形の層(区画のマスの字と地の色・霧・夜の色)と、動く層(人・経路の点線・置く物の照準・ふきだしの印)を分ける。
- 地形の層: 区画(`MapChunk`)ごとに、描いた結果を画像に控える(`GraphicsContext` で描いた `Image`。鍵は区画の番号・`revision`・1 マスの大きさ・昼夜の色・視界の形)。Canvas は控えた画像を並べるだけにする。区画の `revision` が替わった区画だけ描き直す。控えは見えている区画と、そのまわり 1 つまで(それ以外は捨てる)。
- 動く層だけを TimelineView(動く人がいる間)で描く。地形の層は Frame が来た時と視点が動いた時だけ描く。
- 字の `resolve` の控え(`texts`)は、draw ごとに作り直さず、1 マスの大きさと昼夜が替わるまで持つ。
- 見た目は今と同じ(写真の検査が今のまま通ること)。

## テスト
- (Linux)保存: `GameHost.saveData` が、今の `SaveCodec.encode(SaveEnvelope(...))` とバイト列で同じ。凍った見本の読みは今のまま通る。
- (アプリ)`SaveWriter` が書く順を保つ(続けて 3 回書いて、最後のものが残る)。背面の保存が `beginBackgroundTask` の中で終わる(差し替えた口で確かめる)。
- (アプリ)`clockStep` の測り: 差し替えた時計で 60ms かかった歩みが `slowSteps` に入り、40ms は入らない。
- (アプリ)地図の控え: 区画の `revision` が替わらない Frame では、その区画を描き直さない(描いた回数を数える口で確かめる)。
- 画面の写真(screens)が今のまま通る。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す。macOS の CI(ios と screens)が通る。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 保存の形は変えない(凍った見本 `save-v1-dev-*.json` は作り直さない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
