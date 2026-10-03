# W-28 最初の焚き火の置き場に「水が昼の視界の中」を足す(実装の説明書)

書いた人: architect(統合担当)。決めたのは game-designer。土台: 出す時点の `integration-c` の先頭。本体だけ(`RFMap/World/OpeningRules.swift` の `placeOpeningSites`)。

## 穴
昼の視界(半径 8。`VisionRule` から引く `dawnDayRadius()`)に水のマスが入るのは、1000 seed のうち 561 だけ(焚き火から最も近い水のマスは中央 6・最長 9)。「川が近い」の一言と水を汲む行為の開きの前提が崩れる。

## 決め
- 最初の火の置き場(`placeOpeningSites` の `fire`)の候補(`ring(start, radius)` の中の乾いた空きマス。今の順で)から、**最も近い水のマス(岸 `shore`・浅瀬 `ford` を含む。`TerrainDef.isWater` か、生成の `Biome` の水)が、そのマスから `dawnDayRadius()` 以内(`VisionRule.inCircle`)にある**最初の候補を選ぶ。条件を満たす候補が無ければ、今の選び方に戻す(置き場を変えるだけ。地形は変えない)。
- 森の保証(`firstLightForestMin`・`startReachForestMin`)と、夜明けの置き場の規則(W-23 の `dawnFind`)は今のまま保つ。火の位置が変わるので、その後の規則はそのまま新しい `fire` で再計算される。
- 乱数を使わない(今と同じ決まった順)。

## テスト(`RFMapTests/OpeningSiteTests.swift` に足す。1000 seed)
1. 条件を満たす候補がある seed で、火から昼の視界の円の中に水のマスが 1 つ以上ある。
2. 1000 seed のうち、水が視界に入らなかった seed を一覧にして、数が 0 でなければテストは失敗せず**一覧を `print`** する(U14/リーダーが条件の緩め方を決める)。数を報告に書く。
3. 既存の W-23 のテスト(森の保証・`dawnFind`・夜 0 の灯りの外)が全部通る。`MapGenerationTests` の指紋が変わったら、変わった理由を確かめてから更新する(火の位置だけが変わる範囲に限る)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る(`OpeningSiteTests` は 1000 seed で長い)。**note は使えない時間がある(rf-note-test が exit 75 で断ったら使わない)。hub では rf-swift-slot(同時 3 本まで)で、写しと `.build` は `/data/ashwell/tmp/<名前>/` に置く(/ は満杯に近い)。終わった写しは片付ける。**
- 物語の語を書かない。コミットの末尾:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
