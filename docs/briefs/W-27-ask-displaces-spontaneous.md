# W-27 ノアの頼みは、仲間の自発の作業を押しのけて枠を取る(実装の説明書)

書いた人: architect(統合担当)。決めたのは game-designer(SL-21。まだ人が遊んで確かめていない仮説)。土台: 出す時点の `integration-c` の先頭。本体だけ(RFRules の `CrewWork` と、配属を適用する所)。保存の形は変えない。

## 穴
夜明けにシリカへ水を頼むと `reason.assign.no_slot` で断られる。シェルターの前は枠(INV-O10: 火の枠 + 寝床の枠 = 2)が、クロムの採取とカーボの自発の漁りで埋まるため。SL-21(クロムへ枝・シリカへ水)は 10 分の背骨なので、断る形は不可。

## 決め
- 「自発の作業」= 内容の効果 `overrideAssignment` で付いた配属(`PersonState.override`。時間つき。頼まれずに始めた漁りや、炉を置いた時に寄ってくる手伝い)。ノアの頼み = ノアが `.crew(.assign(...))` で出した配属(`PersonState.assignment`)。
- ノアの頼みが枠の数を超える時、**override の作業をしている人を数えない**(`CrewWork.refusal` の `others` から、`override != nil` で働いている人を除く)。結果、頼みは受かる。
- 枠を取られた自発の作業の人は、手を止めて待つ: `CrewWork.working` で、枠に入れる順を「ノアの頼み(頼んだ順)→ 自発の作業」にする(超えた分は自発の作業から休む)。休む人の `override` は消さない(時間が来るまで残る。枠が空けばまた働く)。
- 自発の作業同士、ノアの頼み同士では押しのけない。ノアの頼みが枠を超えたら、今まで通り `no_slot`。枠の数は変えない。
- 新しい状態・保存の項目は足さない(`override` の有無で区別する)。

## テスト(`RFCrewTests` または `RFRulesTests` に足す)
1. 枠 2・クロムの頼み 1 + カーボの `override` の作業 1 のとき、シリカへの頼みが受かる。カーボは休む(`working` に入らない)。
2. 枠 2・ノアの頼み 2 のとき、3 人目の頼みは `no_slot`(今まで通り)。
3. 枠 2・`override` 2 のとき、`override` 同士は押しのけない(`working` は先着 2 人)。
4. 押しのけられたカーボの `override` は消えていない。ノアの頼みが 1 つ減る(別の配属に変える)と、カーボがまた働く。
5. `crewWork` の無い内容は何も縛らない(今のまま)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。**note は使えない時間がある(rf-note-test が exit 75 で断ったら使わない)。hub では rf-swift-slot(同時 3 本まで)で、写しと `.build` は `/data/ashwell/tmp/<名前>/` に置く(/ は満杯に近い)。終わった写しは片付ける。**
- 物語の語を書かない。コミットの末尾:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
