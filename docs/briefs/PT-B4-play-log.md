# PT-B4 端末の中だけに残す行動の記録と、書き出し(Codex への説明書)

書いた人: architect(統合担当。game-designer の下書きから型を決めた)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭。
なぜ: 人の遊び方を、感想ではなく行動で測る(どこで迷い、どこでやめ、いつ何に着いたか)。ボットは歩く時間や読む時間を飛ばすので、人の時間は測れない。**通信はしない**。記録は端末の中だけに残し、遊んだ人が自分で書き出したときだけ外に出る。

## 1. 記録すること(1 行 1 件。JSON Lines)
| `kind` | 中身(`fields`) |
|---|---|
| `build` | 起動の 1 件目。版(`CFBundleShortVersionString`・`CFBundleVersion`)と、開発の設定(PT-B2 の時計の切り替えなど) |
| `session` | アプリが前に出た・後ろに下がった。その時の画面(地図・設計・ノート・設定…) |
| `command` | 出した命令の種類と、行為・建てる物・選んだ選択肢の ID、頼んだ相手(仲間の ID。配属の命令のとき)、受け付けたか・断られたか(理由の ID) |
| `idle` | 10 秒以上なにも押さなかった。その間の画面と長さ(秒) |
| `panel` | 画面を開いた・閉じた(設計・ノート・研究・倉庫・仲間・設定) |
| `mark` | データの節目の一覧(`ContentDB.playtestMarks`)の条件が、その遊びで初めて成り立った(節目の ID) |
| `offer` | 選ぶ物が画面に出た(決断の帯の出来事の ID・分かれ道の見込みの ID〈HK-07〉)。選ぶ前に止まった秒数は、`offer` から次の `command` までで数える |
| `fork` | 分かれ道のどの枝に入ったか(HK-07 の出来事。分かれ道の ID と枝の番号) |
| `day` | 夜明けごとに 1 件。その日の命令の数・決定の数・同じ行為の連続の最長 |

- 全部の行に、実時刻 `t`(ISO 8601)・ゲームの日 `day`・ゲームの時刻 `minute`(その日の 0 時からの分)を付ける。
- 決定の数の数え方: 選択肢を選んだ(`chose`)・ライン札にした(`designed`)・データで「分かれ道」の印が付いた建てる物を置いた・配属を変えた。数え方は 1 つの関数にする(印の付け方は、建てる物の定義の任意の欄 `branchChoice: Bool?` で。無ければ数えない)。
- 名前・端末の識別子・位置情報は記録しない。物語の文も記録しない(ID だけ)。

## 2. 型
- 本体(RFContent): 節目の定義。条件は今の `Condition` をそのまま使う(`known`・`firstTime`・`ledger`・`stat`・`members`・`hearthAtLeast` など)。事実にならない節目(最初の鋼・仲間の合流など)も来歴の条件で書ける。
  ```swift
  public struct PlaytestMarkDef: ContentDef, Equatable { public var id: String; public var when: Condition }
  // ContentDB.playtestMarks: [String: PlaytestMarkDef]。内容の束の上の段のキー "playtestMarks"(配列。ほかの定義と同じく upsert と remove が効く)
  ```
  - 確かめ(ContentValidator): `when` の中に `chance`・`trigger` を使わない(節目は決定的に判定する)。ID は `mark.` で始める。
  - 中身(どの節目を数えるか)は非公開の層に置く(物語の ID が入るため)。公開の層には `mark.test.*` の見本を 2 つだけ置く。
- 本体(RFPresent か RFSim): 判定は 1 か所の純関数と、外に持つ小さな追跡の型。アプリ(B4)とボット(本番の流れのボット・PT-03)が同じ物を使い、日付の表が同じ形になる。
  ```swift
  public struct PlaytestMarkTracker: Codable, Equatable, Sendable {
      public private(set) var reached: [String: GameTime]   // 初めて成り立った時刻
      /// まだ成り立っていない節目だけを評価し、今回初めて成り立った ID を(ID の順で)返す。
      public mutating func update(_ w: WorldState, _ c: ContentDB) -> [String]
  }
  ```
  - 追跡の型は `WorldState` と保存に入れない。アプリは記録の側(`playlog/marks.json`。遊び〈新しいゲームの seed〉ごと)に持つ。ボットは自分の中に持つ。
  - アプリが呼ぶのは、命令を出した後と、ステップの報告に来歴か事実の出来事が入っていたときと、夜明け。毎フレームは呼ばない。
- 本体(RFPresent): 新しい世界の状態は持たない。アプリは `Frame` と `StepReport` の出来事から読むだけ。事実を知った出来事が `StepReport` から読めなければ、読める形の出来事を足してよい(世界は変えない)。
- アプリ:
  ```swift
  struct PlayLogEvent: Codable { var t: Date; var kind: String; var day: Int; var minute: Int; var fields: [String: String] }
  final class PlayLog { func append(_ e: PlayLogEvent); func export() throws -> URL; func clear() }
  ```

## 3. 置き場と書き出し
- Application Support の `playlog/` に、実時刻の日付ごとのファイル(`yyyy-MM-dd.jsonl`)。全部で 2 MB を超えたら古いファイルから消す。
- 設定に「遊んだ記録を書き出す」(共有シートで 1 つのファイル。日付順に連結した JSON Lines)と「遊んだ記録を消す」(取り返しのつかない操作なので確認を 1 回だけ出す)。
- 記録を取るかの入切も設定に置く(既定は入)。切なら何も書かない。
- 通信のコードを足さない。プライバシーの申告は「データの収集なし」のまま(端末の外に自動で出ないため)。
- 書き込みは主スレッドを止めない(小さな直列のキューで追記する)。

## 4. 不変条件
- INV-B4-1 記録は世界と保存に何の影響も与えない(記録の入切で同じ世界)。
- INV-B4-2 通信を使わない(ネットワークの API を参照しない)。
- INV-B4-3 物語の ID・文言が公開のコードに入らない。印はデータで渡す。

## 5. テスト
| ID | 中身 |
|---|---|
| TEST-B4-1 | (アプリ)命令を 20 個流すと `command` が 20 件。受け付け・断りの別と理由が合う |
| TEST-B4-2 | (アプリ)10 秒の無操作で `idle` が 1 件。9 秒では出ない(差し替えられる時計で) |
| TEST-B4-3 | (Linux)`PlaytestMarkTracker`: 事実の条件と、来歴の初めての条件の節目が、それぞれ成り立ったステップで 1 度だけ返る。2 度目は返らない。追跡の型を Codable で書き戻して続けても同じ |
| TEST-B4-3b | (アプリ)節目が成り立ったときに `mark` が 1 件。決断の帯が出たときに `offer` が 1 件 |
| TEST-B4-4 | (アプリ)2 MB を超えると古いファイルから消える |
| TEST-B4-5 | (静的。Linux で回る Python)`ReForge/` のソースに `URLSession`・`NWConnection`・`Network` の import など、ネットワークの API の参照が無い(`tools/check-no-network.py` を足し、CI の Linux の段で回す) |
| TEST-B4-6 | (Linux)`playtestMarks` の有無の両方で内容が読める。`chance` を使った節目は確かめでエラー |

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。macOS の CI でアプリのビルドと単体テスト。統合担当が非公開の層を重ねて回す(節目の一覧は game-designer が決め、非公開の層に置くのは U14)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`・`check-no-network.py`。
- 保存の形は変えない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
