# P-13 行為ごとの掘り出しの純度の上積み(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭。

## 目的
手作業と自動化の違いを「量」ではなく「質」にする。同じ鉱脈でも、行為によって掘り出した鉱石の純度に上積みを付けられるようにする。
例: 手で掘る行為は上積み +5%(`500`)、採掘口のような置いた物の作業は上積み無し(鉱脈の純度のまま)。値はコンテンツが決める(非公開の層の U14 が手で掘る行為に 500 を付ける)。

## 型(RFContent)
- `InteractionDef` に任意の欄を 1 つ足す:
  ```swift
  /// 鉱脈から掘り出した物の純度への上積み(万分率。Purity.basisPoints と同じ単位)。nil・0 は上積み無し。
  /// 掘り出すとき、掘れた物ごとの純度に足し、0...10000 に収める。持ち主: 統合担当(P-13)
  public var extractPurityBonus: Int?
  ```
- JSON のキーは `extractPurityBonus`。無ければ nil(今までのコンテンツはそのまま読める)。
- `ContentValidator` に確かめを 1 つ足す: 値は `0...10000`。外れたら error(規則の名前は `interaction.extractPurityBonus`)。負の値(下げる)は、今は認めない。

## 規則(RFExploration)
- `Interactions.swift` の、行為を終えたときに鉱脈から掘り出す所(`map.extract(dep, …)` の結果を `ctx.addStock(Loot.stuff(for: o), …)` で在庫に入れる所)で、`def.extractPurityBonus` が正なら、掘れた物ごとの `OreYield.purity` に足してから在庫にする。上限は 10000(`Purity` の最大)。
- 足すのは純度を持つ物(今は鉄鉱石。`Loot.stuff(for:)` が `.matter(… purity:)` にする物)だけ。純度を持たない物の ID(`.item`)は変わらない。
- 鉱脈そのもの(地図の `Deposit` の純度・残量)は変えない。在庫に入る物の純度だけを変える。
- 乱数の流れ(`.exploration`)の引き方は変えない(同じ seed で、上積みの無い行為の結果は今とまったく同じ)。
- 誰がやったか(ノア・仲間)では変えない。行為の定義で決まる(仲間に頼んだ同じ行為にも付く)。

## テスト(新しいテストのファイル、または `RFExplorationTests` の近い所)
1. 上積みの無い行為(欄が無い)で掘った結果が、今と同じ(純度・数・乱数の消費)。古いデータで今までどおり動くことの受け入れ。
2. `extractPurityBonus: 500` の行為で同じ鉱脈・同じ seed で掘ると、在庫の鉄鉱石の純度が、上積み無しのときより 500 高い。数は同じ。
3. 上限: 純度 9800 の鉱脈を 500 で掘ると 10000。
4. 純度を持たない物(item)は変わらない。
5. JSON: `extractPurityBonus` があってもなくても読める。`ContentValidator` が 10001 と -1 を error にする。
6. 公開の層には、試験用の行為を 1 つ足してもよい(中立の名前。例 `interaction.test.dig_fine`)。足したら文言・認識の表も合わせる(`text/ja/`)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る(テストの数が減らない)。
- 静的: `python3 tools/check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 統合担当が、非公開の層(欄の無い古い形と、欄のある新しい形)を重ねて回す。
- 保存の形は変えない(凍らせた見本 `save-v1-dev-*.json` は作り直さない・飛ばさない)。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
