# A-07 10 分の通しの台本を、アプリへ流し込んで録画する(実装の説明書)

書いた人: architect(統合担当)。土台: 出す時点の `integration-c` の先頭。本体のテスト(ボットの台本の書き出し)とアプリの DEBUG の部品。公開リポジトリには物語の語を書かない。
目的: 非公開の層を重ねた 10 分のボット(`FirstTenMinutesBotTests`)が送った命令を、時刻つきの台本として書き出し、アプリの DEBUG の組みが、その台本を本物の `GameStore` に流し込む。CI(別ジョブ `rec`)がシミュレータでそれを録画する(録画の暗号化は CI の側)。

## 1. 台本の書き出し(ボット側。テストのファイル 1 つ)
- 環境変数 `REFORGE_TENMIN_SCRIPT=<パス>` がある時だけ、ボットの命令の口(`FirstTenMinutesBotTests` の `send(_ c: Command)`)が、送った命令を記録する。1 回の通し(seed 1 つ)の分だけ書く(`REFORGE_TENMIN_SEEDS=1`)。
- 台本の形(JSON。`Codable`):
  `{"version": 1, "seed": Int, "seconds": Double, "commands": [{"step": Int, "command": <Command の Codable>}]}`
  `step` は命令を送った時のシミュレーションの歩みの通し番号(世界の `clock.now` の秒を `SimStep.gameSeconds` で割った値でよい)。`seconds` は最後の命令までの実時間の見込み(歩み × 実時間の 1 歩の長さ)。
- ボットは今まで通り。台本を書かない時の挙動は変えない。出力に内容の名前を出さない(`print` の文は今のまま、ファイルにだけ台本を書く)。
- テスト(`ReForgeCore`): `Command` の配列の往復(`JSONEncoder` → `JSONDecoder`)が同じ。台本の書き出しを関数(`ReplayScript`。`RFTestSupport` ではなくアプリでも使える場所 = `ReForgeCore/Sources/RFPresent/` の公開の型 `ReplayScript: Codable`)にして、書く・読むの往復を公開の層のテストで確かめる。

## 2. アプリの流し込み(DEBUG だけ)
- 起動引数 `-ReForgeReplay <台本のパス>`(`-ReForgeReplayDone <完了の印のパス>` も)で、`#if DEBUG` の `ReplayDriver` が働く。通常の起動・撮る起動(`-ReForgeScreenshot`)には何も起きない。
- 動き: 台本の `seed` で新しい世界を開き(`GameBootstrap.newWorld`・保存を読まず書かない。撮る起動と同じ作り)、`GameStore` を普通に動かす(実時間のループ)。`clock.now` が台本の `step` に届くたびに、その命令を `store.send` で送る。序の場面の送り(`.narrative(.advanceScene)`)も台本の命令なので、同じように送る(人の読む間を置くため、場面の送りの命令は前の命令から 1.5 秒以上あける)。
- 台本の最後の命令の後 5 秒たったら、完了の印のファイルを書く(中身は空でよい。書くのは 1 行 `done`)。
- 流し込みの間、画面の操作は受けない(`allowsHitTesting(false)`)。画面は普通の画面のまま(録画に映る)。
- テスト(`ReForgeTests`): 小さな台本(ノアの歩き 1 回)を流し込むと、`clock.now` が進み命令が送られ、完了の印が書かれる。台本が無い・壊れている時は何もしない(クラッシュしない)。

## 受け入れ
- 本体: `swift test --package-path ReForgeCore` が公開の層で全部通る(hub の docker。note は使えない時間がある)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- アプリは hub で組めない(macOS の CI で確かめる)。`@MainActor` と SwiftUI の型に気をつけて書く。

## コミット
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
