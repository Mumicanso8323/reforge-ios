# PT-B1 続けて採る・火の見込みの 1 行(Codex への説明書)

書いた人: architect(統合担当。game-designer の下書きから型を決めた)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭。
なぜ: 最初の 5 分の手の動きが「同じボタンを何度も押す」になっている。押す回数を減らし、「何を集めるか・火に何本使うか」を選ばせる。人が遊ぶ試し(PT)の前に入れる。

## 1. 続けて採る(本体: RFContent・RFExploration・RFCrew)
### 型
- `InteractionDef` に任意の欄を 2 つ:
  ```swift
  /// 押し続けている間、1 単位ができたら次の 1 単位を自動で始める行為か(採集向け。漁る・掘る・建てるには付けない)。
  public var continues: Bool?
  /// 次の場所を探す半径(マス。既定 3)。
  public var continueRadius: Int?
  ```
  JSON のキーも同じ。無ければ今までどおり(1 単位で止まる)。
- 次の場所を選ぶ純関数 `ContinueRules.next(interaction:from:world:content:) -> WorldPoint?`(置き場は RFExploration か RFRules)。

### 振る舞い
- `continues == true` の行為を押し続けている間(`.exploration(.interact(…, holding: true))` の後、`holding: false` が来るまで)、1 単位ができたら次を始める。
- 次の場所(この順。決定的で乱数を使わない):
  1. 同じマスでまだ採れる(回数の上限・クールダウンが残る)なら、同じマス。
  2. 採れないなら、手の届く所(今の届く距離)にある、同じ行為が採れるマス。
  3. それも無ければ、ノアから半径 `continueRadius` 以内の、同じ行為が採れて今見えているマスへ歩いて移る(歩く時間は今の歩きと同じに数える)。
  4. どれも無ければ止まり、足元カードに「近くにもう無い」(固定の文言)を出す。
  - 候補が複数なら、(歩く距離, y, x)の小さい順の 1 つ。
- 離したら止まる。作りかけの単位の進みは捨てない(押し直せば続きから)。歩いている途中で離したら歩きを止める。
- 蓄えの上限に届いたら止まる。夜作業の時間に入ったら止まる(今の昼だけの規則のまま)。
- 仲間の採取の配属(`Assignment.gather`)も、配属のマスで採れなくなったら、**配属の時の場所から**半径 `continueRadius` の中の次のマスへ移る(同じ選び方)。半径の外へは出ない。
- `FootCard.Action` に `progressPermille: Int?`(今の単位の進み。押していないときは nil)を足す(PT-B3 のバーにも使う)。

## 2. 火の見込みの 1 行(本体: RFRules・RFPresent)
- 純関数 `HearthRule.outlook(_ state: HearthState, _ def: HearthDef, now: GameTime, clock: ClockDef, structuresInLight: Int) -> FireOutlook`。今の燃え方(`rate`・`burn` と同じ式)で燃料の残りがいつ尽きるかを、4 段で返す:
  ```swift
  public enum FireOutlook: String, Equatable, Sendable { case untilEvening, midnight, beforeDawn, throughNight }
  ```
  (夕方まで・夜半・夜明けの前・夜明けまでもつ。境目の時刻は時計の定義から出す。世界を変えない)。
- 「1 本くべた後」の見込み: `HearthRule.add` で燃料を 1 足した状態に同じ関数を当てる(くべる行為が使う品で)。
- `Frame`: 焚き火の足元カード(`FootCard`)に `fire: FireOutlookView?`(`now`・`afterOneMore`)。日没の帯にも、薪の置き場に残る本数での見込みを同じ 4 段で出す(PT-B2 の夜の締めの 3 行目でも使う)。
- 画面: 足元カードと「くべる」のボタンの近くに「今: 夜半に消える → 1 本くべると: 夜明けまでもつ」の形で 1 行(固定の文言 + 4 段の言葉)。

## 3. 不変条件
- INV-B1-1 続けて採っても、1 単位ごとの量・時間・来歴は、1 回ずつ押したときと同じ(同じ seed・同じ場所の並びなら、在庫と来歴が一致する)。
- INV-B1-2 離した時点で、作りかけの単位の進みは残る。材料は失わない。
- INV-B1-3 次の場所の選び方は決定的。乱数を使わない。
- INV-B1-4 見込みの関数は世界を変えない。

## 4. テスト(Linux)
| ID | 中身 |
|---|---|
| TEST-B1-1 | 採れるマスが 3 つ並んだ地図で、押し続けると 3 単位が採れ、4 単位目で「近くにもう無い」で止まる |
| TEST-B1-2 | 1 回ずつ 3 回押した世界と、続けて 3 単位採った世界で、在庫と来歴の数が同じ |
| TEST-B1-3 | 2 単位目の途中で離し、押し直すと続きから進む |
| TEST-B1-4 | 候補が同じ距離に 2 つあるとき、(距離, y, x)の小さい方を選ぶ |
| TEST-B1-5 | 火の見込み: 燃料の残りと時刻の組の表(8 組)で 4 段の答えが合う。くべた後の見込みが同じか良くなる |
| TEST-B1-6 | 仲間の採取の配属で、配属のマスが尽きたら半径の中の次のマスへ移る。半径の外へは出ない |
| TEST-B1-7 | `continues` の無い行為は今とまったく同じ(1 単位で止まる) |

公開の層の試験用の採集の行為に `continues: true` を付けてよい(中立の ID)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す(非公開の層の採集の行為に `continues` を付けるのは U14)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。macOS の CI でアプリのビルド。
- 保存の形は変えない(凍らせた見本は作り直さない・飛ばさない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
