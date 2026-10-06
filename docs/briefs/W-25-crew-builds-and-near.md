# W-25 仲間が自分で建てる効果・「置いた物の近く」の条件・火床のそばの物の効き(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 出す時点の `integration-c` の先頭。本体だけ(画面の変更なし)。
もと: 最初の 10 分の版(非公開の計画の SL-12・SL-22)。データの側(どの人が・何を・どの一言で)は U14。

## 1. 効果 `selfBuild`(仲間が自分で建てる)
- `Effect` に `case selfBuild(person: PersonID, structure: StructureKindID, near: PlaceSelector, radius: Int?)` を足す。
- 処理: `near` の指すマスから半径 `radius`(既定 3。チェビシェフ・同じ層)の中で、**プレイヤーの `Command.build(structure:at:facing:)` が受け付けるマス**を近い順 → y → x で探し、最初のマスに**未完成で**置く(置き方・材料の扱い・置ける決まりは `Command.build` と同じ関数を通す。写さない)。置けたら、その人の配属を `.build(placement:)` にする(上書きの配属 `overrideAssignment` と同じく、プレイヤーがあとで変えられる)。
- 置けるマスが無い・その人が一員でない・倒れている時は、何もしない(エラーにしない。デバッグの記録に 1 行)。
- 来歴: 置いたことは、プレイヤーが置いた時と同じ記録。建てた人はその人。
- 確かめ(`ContentValidator`): `structure` が存在する・`radius` は 1〜8。

## 2. 条件 `nearPlacement`
- `Condition` に `case nearPlacement(place: PlaceSelector, module: ModuleKindID?, structure: StructureKindID?, poi: POIKindID? = nil, radius: Int, includeUnfinished: Bool? = nil)` を足す。`poi` を置くと、その種類の POI(残骸の中の部品を含む POI 全体)までを測る。距離は、`place` の指す物の占めるマスと、相手の占めるマスの間のチェビシェフ距離の最小(1 マスの物は今の点の距離と同じ)。`module`・`structure`・`poi` は高々 1 つ。
- 意味: `place` の指すマスから半径 `radius`(チェビシェフ・同じ層)の中に、その種類の置いた物が 1 つ以上ある(`module`・`structure` の両方 nil は「何でも」。未完成は既定で数えない)。「5 以上離れている」は `not(nearPlacement(radius: 4))` で書く。
- 出来事の `trigger`(建った時の hook)の中で `place: .placement(...)` が、**いま建った物**を指せるかを確かめる。指せないなら、`PlaceSelector` に `case trigger`(出来事を起こした物のマス)が今あるのでそれを使う(無ければ足す)。
- 水の近さは今の `nearTerrain(place:tag:radius:)` で足りる。

## 3. 火床のそばの物の効き(建てた物の数の効果)
- 建造物の `provides` の 2 つの鍵を本体が読む(名前は統合担当の決め):
  - `"hearth.pile"`: その物が火床の灯りの中にある間、その火床の薪の山の上限(`pileMax`)に足す数。
  - `"hearth.burn_permille"`: その物が火床の灯りの中にある間、その火床の燃料の減り(`HearthRule.rate`)に掛ける千分率(900 = 0.9 倍)。複数あれば掛け合わせる。
- この 2 つの鍵を持つ物は、灯りの中の建造物の数(`structuresInLight`、減りを増やす側)に**数えない**。
- 完成した物だけ効く(未完成は効かない)。燃えていない火床にも上限は効く(減りは燃えている間だけ)。
- **見込みも同じ式**: 日没の帯の火の見込み(`outlookWithPile`・`duskFireOutlook`)と、尽きるまでの見込みは、`burn` と同じく掛け算と上限を通す(式を 2 か所に写さず、1 つの関数から読む)。
- 薪の山の上限の拒否(`reason.hearth.pile_full`)も新しい上限で判断する。

## テスト(Linux。公開の層の試験の内容。文は中立)
- `selfBuild`: 試験の人が一員の時、近くの置けるマスに未完成で置かれ、その人の配属が `.build` になり、時間を進めると建つ。置けるマスが無い時は何も起きない。一員でない人では何も起きない。
- `nearPlacement`: 半径の内・外の境(ちょうど半径・半径 +1)、未完成を数える/数えない、種類の nil。建った時の hook の出来事で、建った物の近さで別の出来事が起きる組。
- 火床: `"hearth.pile": 4` の物を灯りの中に置くと上限が 4 増え、外では増えない。`"hearth.burn_permille": 900` の物で、同じ秒数の燃料の減りが 0.9 倍(端数の扱いは今の `burnCarry` のまま)。見込み(`outlookWithPile`)が実際の `burn` と一致する(今の `testOutlookWithPileMatchesBurn` の形を、この 2 つの物ありで足す)。
- 凍った保存の見本は作り直さない(保存の形は変えない。`provides` は内容の側)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`(`Effect`・`Condition` に case を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
