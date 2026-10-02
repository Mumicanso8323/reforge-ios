# PT-HK 最初の 1 時間の手応え 5 つ(HK-02・04・05・07・08)(Codex への説明書)

書いた人: architect(統合担当。game-designer の「ハマらせる設計」から、PT-B1〜B4 と重ならない物を型にした)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭(**PT-B1〜B4 の後**。B3 の `Frame.pulses` と B2 の夜の締めを使う)。
どれも文は足さない。画面の文言は固定の文言 + 数と物の名前だけ。物語の行・順番・条件は変えない。どの行為・分かれ道・獣に付けるかは非公開の層のデータ(U14)が決め、公開の層には中立の試験の見本だけを置く。
5 つは別々のコミットにする(1 つずつ見直せるように)。

## HK-02 押せると分かる縁(本体の欄 1 つ + 画面)
- `InteractionDef.beckon: Bool?` を足す。付いた行為は、**その遊びでまだ一度も成し遂げていない間**、足元カードのボタンの縁がゆっくり脈打つ(周期 1.6 秒・不透明度 0.35〜1.0)。
- `FootCard.Action.beckons: Bool`(本体が出す)。判定は来歴から(新しい世界の状態を足さない。同じ行為の来歴が 0 件の間 true)。
- 端末の「視差効果を減らす」が入っているときは脈打たず、縁を 1 段太くするだけ。
- テスト: (Linux)`beckon` の付いた行為は、成し遂げる前は `beckons == true`、1 度成し遂げた後は false。付いていない行為は常に false。

## HK-04 地図が灯る瞬間(画面 + B3 の脈の 1 つ)
- B3 の `FirePulse` に `firstLit` を足す(その遊びで初めて火床が灯ったステップ。来歴から判定)。`Pulse.fire(.firstLit)` には火床の場所を付ける: `case fire(FirePulse, at: WorldPoint?)` に直してよい。
- 画面: `firstLit` のとき、見えるようになったマスを、火床から近い順に 1.2 秒かけて輪で明るくする(ease-out)。音は `ui_ignite` より 1 段強い `ui_ignite_first`(B3 の生成の道具に 1 つ足す)、触覚は `hapIgnite` を中の強さで。2 度目からは B3 の `fire(.lit)` のまま。
- 「動きを減らす」の入では、輪の動きを出さず、一度に明るくする(音と触覚はそのまま)。
- テスト: (Linux)初めて灯ったステップだけ `firstLit` が入り、消してもう一度灯すと `lit`。(アプリ)「動きを減らす」の入で輪の動きを作らない。

## HK-05 頼んだ仕事の進み(本体 + 画面)
- `FootCard.crew: [CrewProgressView]`(最大 3):
  ```swift
  public struct CrewProgressView: Equatable, Sendable { public var person: PersonID; public var name: String; public var label: String; public var progressPermille: Int }
  ```
  足元カードのマスから半径 3 以内の場所で、行為をしている(`.interacting`)仲間。並びは(距離, 人の ID)。`label` は行為の名前、進みは今の単位の進み(千分率)。
- 画面: 足元カードの行為のボタンの下に、名前・行為・細いバーを 1 行ずつ。ノアの手のバー(B1 の `progressPermille`)と同じ見た目で並べる。
- テスト: (Linux)仲間 2 人に採取を頼んだ世界で、カードの `crew` に 2 人が距離の順に入り、ステップごとに進みが増え、1 単位で 0 に戻る。半径の外の仲間は入らない。

## HK-07 分かれ道の見込み(本体の定義 1 つ + 画面)
- 新しい定義(内容の束の上の段のキー `forks`。upsert と remove が効く):
  ```swift
  public struct ForkDef: ContentDef, Equatable {
      public var id: String                  // "fork." で始める
      public var when: Condition              // 見込みを出している間(例: 目標が立っていて、まだ着いていない)
      public var target: PlaceSelector        // 行き先
      public var branches: [Branch]           // 2〜3 本
      public struct Branch: Codable, Equatable, Sendable {
          public var label: TextID            // 今ある文の ID だけ(地形や場所の名前)。新しい文を足さない
          public var via: [GridPoint]         // 通る点(地表)
      }
  }
  ```
- 本体の純関数 `ForkRules.outlook(_ w: WorldState, _ c: ContentDB) -> [ForkOutlookView]`。枝ごとに:
  - 道のり: ノアの今の場所から `via` を順に通って行き先までの歩く時間(今の歩きの経路と速さ。時間の整数)。
  - 途中で採れる物: 経路の 1 マス以内の地形と場所から採れる品のうち、**名前を知っている物**(認識の層を通した名前)を多い順に 2 つまで。知らない物は数だけ(「ほか 2」)。
  - 気配: 経路から、獣の巣(見つけていなくても)の縄張りの半径(`RaidLureDef.territoryRadius`。無ければ 15)以内に巣があるか(あり / なし)。巣の場所は出さない。
- 枝に入った(最初の `via` の 1 マス以内に着いた)ステップで、出来事 `DomainEvent.forkTaken(fork: String, branch: Int)` を出し、その分かれ道の見込みは消える。`when` が成り立たなくなっても消える。B4 の記録は、見込みが出たときに `offer`、入ったときに `fork` を書く。
- 画面: 帯に枝ごとに 1 行(「〈label〉: 道のり 〈h〉 時間・〈物〉・〈物〉・獣の気配 あり」)。押せる物ではない。
- 公開の層に、枝 2 本の試験の分かれ道を 1 つ置く。2 日目の道のデータは U14。
- テスト: (Linux)枝 2 本の地図で、道のりの時間・採れる物・気配が手で数えた値と合う。名前を知らない品は名前を出さない。最初の通る点に着くと `forkTaken` が 1 度だけ出て、見込みが消える。

## HK-08 獣の寄りやすさの見込み(本体 + 画面)
- 本体の純関数 `Threats.lureOutlook(_ w: WorldState, _ c: ContentDB) -> LureOutlookView?`。今の寄り方の式(`Threats.lure`)を、`StepContext` を使わずに `WorldState` と `ContentDB` から計算できるよう 1 か所に寄せ、両方から呼ぶ(式を 2 つ持たない)。
  - 対象: 寄り方(`RaidDef.lure`)を持つ獣のうち、`requiresFact` が成り立ち `untilFact` がまだの物。無ければ nil(見込みを出さない)。
  - 今夜の見込み: 煙 = 今燃えている火床の数、縄張り = 今日伐った回数(`felledToday`)、闇 = 今、焚き火が 1 つも燃えていないか。しきい値の型なら合計としきい値の比、確率の型なら一晩の率から、3 段(低い・中くらい・高い。しきい値の型: 合計 < しきい値の半分 / < しきい値 / それ以上)。
  - どの入力が効いているか: 0 より大きい入力を、大きい順に(煙・伐採・闇)。
  ```swift
  public struct LureOutlookView: Equatable, Sendable {
      public enum Level: String, Sendable { case low, medium, high }
      public enum Factor: String, Sendable { case smoke, felling, dark }
      public var level: Level
      public var factors: [Factor]
  }
  ```
- `Frame.lure: LureOutlookView?`。画面: 昼の後半(日没の 2 時間前から)と夜の締め(B2 の 3 行目の候補に入れる。急ぐ順は「高い」なら火や食料より先)に、「獣の寄りやすさ: 高い(煙・伐採)」の 1 行。
- テスト: (Linux)しきい値の型の試験の獣で、煙・伐採・闇の組の表(6 組)で段と入力の並びが合う。`requiresFact` が無い間は nil。寄せた式で、今の寄りのテスト(`ThreatTests` など)が全部そのまま通る。

## 記録の印との突き合わせ(B4)
| HK | 確かめ方の数 | B4 で取れるか |
|---|---|---|
| HK-02 | 最初の火の時刻・地図が出てから最初に押すまでの秒数 | 取れる。節目(`mark`)を 2 つ: 地図が出た・最初の火(条件は非公開の層)。秒数は「地図が出た」の `mark` から次の `command` まで |
| HK-04 | 問い(覚えていること) | 記録ではなく問い |
| HK-05 | 頼んだ後に、頼む相手を増やした・変えた人の割合 | 取れる(`command` に頼んだ相手を足した) |
| HK-07 | 選ぶ前に止まった秒数・次の回の枝 | 取れる(`offer` と `fork` を足した) |
| HK-08 | 3 日目の夜までに柵か罠を置いた人の割合 | 取れる(`command` の建てる物の ID と日) |

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。macOS の CI でアプリのビルドと単体テスト。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 保存の形は変えない(どれも世界の状態を足さない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
