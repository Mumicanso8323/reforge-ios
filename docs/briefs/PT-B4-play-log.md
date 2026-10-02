# PT-B4 端末の中だけに残す行動の記録と、書き出し(Codex への説明書)

書いた人: architect(統合担当。game-designer の下書きから型を決めた)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭。
なぜ: 人の遊び方を、感想ではなく行動で測る(どこで迷い、どこでやめ、いつ何に着いたか)。ボットは歩く時間や読む時間を飛ばすので、人の時間は測れない。**通信はしない**。記録は端末の中だけに残し、遊んだ人が自分で書き出したときだけ外に出る。

## 1. 記録すること(1 行 1 件。JSON Lines)
| `kind` | 中身(`fields`) |
|---|---|
| `build` | 起動の 1 件目。版(`CFBundleShortVersionString`・`CFBundleVersion`)と、開発の設定(PT-B2 の時計の切り替えなど) |
| `session` | アプリが前に出た・後ろに下がった。その時の画面(地図・設計・ノート・設定…) |
| `command` | 出した命令の種類と、行為・建てる物・選んだ選択肢の ID、受け付けたか・断られたか(理由の ID) |
| `idle` | 10 秒以上なにも押さなかった。その間の画面と長さ(秒) |
| `panel` | 画面を開いた・閉じた(設計・ノート・研究・倉庫・仲間・設定) |
| `mark` | データの印の一覧(`ContentDB.playtestMarks`)に入っている事実を知った |
| `day` | 夜明けごとに 1 件。その日の命令の数・決定の数・同じ行為の連続の最長 |

- 全部の行に、実時刻 `t`(ISO 8601)・ゲームの日 `day`・ゲームの時刻 `minute`(その日の 0 時からの分)を付ける。
- 決定の数の数え方: 選択肢を選んだ(`chose`)・ライン札にした(`designed`)・データで「分かれ道」の印が付いた建てる物を置いた・配属を変えた。数え方は 1 つの関数にする(印の付け方は、建てる物の定義の任意の欄 `branchChoice: Bool?` で。無ければ数えない)。
- 名前・端末の識別子・位置情報は記録しない。物語の文も記録しない(ID だけ)。

## 2. 型
- 本体(RFContent): `ContentDB.playtestMarks: [FactID]`(内容の束の上の段のキー `playtestMarks`。任意。無ければ `mark` は出ない)。印は非公開の層のデータで渡す(本体に物語の ID を書かない)。
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
| TEST-B4-3 | (アプリ)`playtestMarks` に入れた事実を知ったときに `mark` が 1 件。入れていない事実では出ない |
| TEST-B4-4 | (アプリ)2 MB を超えると古いファイルから消える |
| TEST-B4-5 | (静的。Linux で回る Python)`ReForge/` のソースに `URLSession`・`NWConnection`・`Network` の import など、ネットワークの API の参照が無い(`tools/check-no-network.py` を足し、CI の Linux の段で回す) |
| TEST-B4-6 | (Linux)`playtestMarks` の有無の両方で内容が読める |

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。macOS の CI でアプリのビルドと単体テスト。統合担当が非公開の層を重ねて回す(`playtestMarks` を置くのは U14)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`・`check-no-network.py`。
- 保存の形は変えない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
