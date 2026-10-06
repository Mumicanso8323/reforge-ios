# W-20 蓄えの上限を原作に合わせる(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。もと: 上限と容量の欄の棚卸し(本体が読んでいないのは `provides["storage"]` だけ)と、game-designer の原作の上限の表(非公開の計画 original-capacity-limits)。
決まり(リーダー 2026-10-02): **値と仕組みは原作のまま**。原作で遊べた 2 つ(品ごとの量・食料と水の合計)だけを入れる。原作で一度も効いていなかった「品の種類の数」は入れない。新しい値は作らない。溢れて消える分は、見せ方だけを足す(見えない損にしない)。
2 つに分ける: **W-20a 食料と水の合計**(F0)と、**W-20b 品ごとの量**(拠点の格 RW-21 と一緒。F2)。

## W-20a 食料と水の合計(F0)
- 定義(内容の束の上の段のキー `stockCaps`。任意。無ければ上限は無い。今までと同じ):
  ```swift
  public struct StockCapDef: ContentDef, Equatable {
      public var id: String                     // "cap." で始める
      public var items: [ItemID]                // 合計して数える品(例: 食料の 2 品)
      public var limit: Int                     // 上限(原作の既定の難易度の値)
      public var multiplier: CapMultiplier?     // 建物で増える
      public struct CapMultiplier: Codable, Equatable, Sendable {
          public var structure: StructureKindID // この建物が 1 つでもあれば
          public var permille: Int              // 掛ける(2000 = 2 倍)。数は重ならない
      }
  }
  ```
- 本体: **夜明け**(1 日の終わりの判定と同じ所)に、合計が上限を超えていたら、超えた分を捨てる。捨てる順は、品の並び(`items` の後ろから)・同じ品の中は純度の低い方から(決定的)。採取や運びは止めない(原作どおり)。
- 捨てたら出来事 `DomainEvent.stockSpoiled(cap: String, item: ItemID, quantity: Int)` を出す。来歴にも残す(何がいくつ消えたか)。
- 見せ方: PT-B2 の夜の締めの行(無ければ夜明けの帯の 1 行)に「腐って捨てた: 〈物〉 n」「溢れて流れた: 〈物〉 n」(どちらの言葉にするかは上限の定義の任意の欄 `lossLabel: TextID` で。データが原作の「腐敗」「流出」の文の ID を置く)。上限に近い(9 割以上)ときは、帯の食料・水の値の横に「上限 60」を出す。
- データ(U14): 食料の合計と水の合計を別々に、上限 60(原作の既定 Normal。移植に難易度は無い)、保管箱(原作の `storage_crate`。木材 6・鉄板 2)で 2 倍。保管箱は今の r1 に無いので U14 が足す。
- テスト: 合計 70・上限 60 で、夜明けに 10 捨てて `stockSpoiled` が出る / 保管箱が 1 つで上限 120、2 つでも 120 / 定義の無い内容では今とまったく同じ / 捨てる順が決定的。

## W-20b 品ごとの量(F2。RW-21 拠点の格と一緒)
- 品 1 種類ごと(純度のある品は純度の段ごとに別)の上限。拠点の格 1: 255 / 2: 500 / 3: 999 / 4 以上: 9999(原作の値)。建物では増えない。
- 拠点に足すとき(採る・作る・運ぶ・漁る・選択の効果)に上限で切る。原作は溢れた分を黙って消していた。値と切り方は原作のまま、見せ方を足す: 切ったとき、足元カードに理由の 1 行(「〈物〉はもう持てない(上限 255)」)と、帯に 1 度だけの知らせ。手の続けて採る(PT-B1)は、上限に届いたら次の単位を始めずに止まる(「近くにもう無い」と同じ止まり方で、理由を替える)。
- 定義: `BaseGradeDef`(RW-21)の各段に `stackLimit: Int`。格の無い内容では上限は無い。
- テスト: 254 + 3 で 255 になり 2 が切られて理由が出る / 純度の段ごとに別に数える / 格が上がると上限が上がる / 続けて採るが上限で止まる。

## 移植の `provides.storage: 10` について
原作の小倉庫(費用が同じ)は、効いていなかった「品の種類の数」に +30 するだけだった。原作に合わせ、**効き目の無い建物**にする(本体は `storage` を読まないまま。`BaseRules.storageSlots` は使われていないので消す)。非公開の層の `provides.storage: 10` は、U14 が消す(新しい値を作らない)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る(公開の層に試験の上限と保管箱を置く)。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`(出来事を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 保存の形は変えない(上限は内容の定義。捨てた記録は今の来歴の形)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
