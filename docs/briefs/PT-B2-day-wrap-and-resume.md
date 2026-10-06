# PT-B2 夜の締めの 3 行・再開の 1 行・考える画面の時計(Codex への説明書)

書いた人: architect(統合担当。game-designer の下書きから型を決めた)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭(PT-B1 の後。夜の締めの 3 行目で火の見込みを使う)。
なぜ: 1 日(昼 3 分 + 夜)を 1 回の遊びの単位にする。1 日の終わりに「今日の成果と明日の見込み」で締め、また開いたときに「前回と次の一手」で迷わず戻れるようにする。

## 1. 夜の締めの 3 行(本体: RFPresent)
- `Frame.dayWrap: DayWrapView?` — 日没(夜作業か寝るかを選ぶ帯が出ている間)だけ入れる。
  ```swift
  public struct DayWrapView: Equatable, Sendable {
      public var made: [CountedName]   // 今日できた物(多い順に 3 つまで)
      public var running: String?      // 動いている物の 1 行
      public var outlook: String?      // 明日の見込みで一番急ぐもの 1 つ
  }
  public struct CountedName: Equatable, Sendable { public var name: String; public var count: Int }
  ```
  1. 今日できた物: その日の夜明けから今までの来歴(`crafted`・`produced`・`built`・`trialed`・`designed`・`mined`・`gathered`)を、物の名前(認識の層を通した名前)ごとに数え、多い順・同数は名前の順に 3 つまで。
  2. 動いている物: 動いているラインの数と、仕事に就いている仲間の数。その日に初めて動いた物があれば、それを先に書く。
  3. 明日の見込み: 火(PT-B1 の 4 段)・食料と水の残り日数・止まりそうなライン(理由つき)のうち、一番急ぐもの 1 つ(急ぐ順の決め方は 1 つの関数にし、表で確かめる)。
- 画面: 帯の 2 つのボタン(夜作業 / 寝る)の上に 3 行を出す。シートや確認は使わない。ボタンを押すと消える。文言は固定の文言 + 数と物の名前だけ。

## 2. 再開の 1 行(本体は 1 行を作るだけ。実時刻はアプリ)
- 本体の純関数 `FrameBuilder.resumeLine(_ w: WorldState) -> ResumeLine`:
  ```swift
  public struct ResumeLine: Equatable, Sendable { public var last: String?; public var next: String? }
  ```
  `last` は、ノアの最後の目立つ行為(`built`・`designed`・`trialed`・`crafted`・`placed` の来歴の最後の 1 つ。無ければ nil)。`next` は今の目標の 1 行(今の目標の表示と同じ)。
- アプリ: 前回の操作の実時刻は**保存の外**(`UserDefaults`)に持つ。アプリが前に出たとき、前回の操作から実時間で 10 分以上(`resumeAfterMinutes`。アプリの定数)たっていれば、帯に「前回: 〈last〉。次: 〈next〉」を出す。最初の命令を出すか、その日が終わると消える。保存から読んだときも同じ。`last` が nil なら「前回:」の部分を出さない。
- 実時刻は `WorldState` と保存に入れない。

## 3. 考える画面の時計(アプリ。開発の設定だけ)
- 設定に開発の節(DEBUG のビルドと dev のビルドだけ。ビルドの設定で出し入れ)を置き、「設計とノートを開いている間、時計を止める」の切り替え(既定は切。今と同じ)。入のとき、設計の画面かノートを開いている間、アプリは本体の時計(`tick`・`advance`)を呼ばない。
- 製品の設定には、PT で決まるまで出さない。値は `UserDefaults`(保存に入れない)。

## 4. 不変条件
- INV-B2-1 締めと再開の行は世界を変えない。保存の形を変えない。
- INV-B2-2 時計を止める切り替えが切のとき、今とまったく同じに動く。
- INV-B2-3 締めの数は来歴から数えた値と一致する(別の数え方を持たない)。

## 5. テスト
| ID | 中身 |
|---|---|
| TEST-B2-1 | (Linux)1 日に試験の品 A を 3・B を 2 作った世界で、日没の締めの 1 行目が「A 3・B 2」の順 |
| TEST-B2-2 | (Linux)初めてラインが動いた日に、2 行目がその行を先に出す |
| TEST-B2-3 | (Linux)3 行目が、火・食料・水・ラインの中で一番急ぐもの 1 つになる(表で 6 組) |
| TEST-B2-4 | (アプリ)再開: 実時間 9 分では出ない、11 分では出る。最初の命令で消える(時刻は差し替えられる時計で) |
| TEST-B2-5 | (アプリ)時計を止める切り替えが切のとき、開く前後でゲームの時刻の進みが今と同じ。入のとき、開いている間は進まない |
| TEST-B2-6 | (Linux)`resumeLine` の `last` が、最後の目立つ行為の来歴から作られる。無ければ nil |

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。macOS の CI でアプリのビルドと単体テスト。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 保存の形は変えない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
