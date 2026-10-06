# A-05 採った後の木のマスを、形と色で見分ける(SL-36 の本体の部分。実装の説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl。上限なら reforge-impl)。土台: 出す時点の `integration-c` の先頭。本体(RFPresent・RFExploration)と、アプリの色の表だけ。
もと: 最初の 10 分の版の SL-36(マスの種類を形で見分ける。「枝の拾える森」と「枝の拾えない木」)。game-designer の決め: 形(字)と色の**両方**で分ける・凡例は置かない・色だけの違いは不可。**この版は日本語だけ**。物語の語を書かない。

## 目的
- 枝を拾える森のマスと、拾った直後で今は拾えない(クールダウン中の)森のマスを、地図の上で**字の形と色**で見分けられるようにする。今は拾った後も同じ字・同じ色で、押すと「拾えない」と断られる(押せない物がボタンに見える)。
- 仕組み: 行為(`InteractionDef`)が `target.terrain(tag:)` で `cooldownDays > 0` のとき、そのマスで拾った日(`ExplorationState.harvestedDay`。キーは `ExplorationState.countKey(def.id, poi: nil, at:)`)から `cooldownDays` 日たつまで、そのマスは「使い切り」の見た目にする。

## 1. 本体
- `MapProjector.tile`(`RFPresent/MapProjection.swift`)の地形のマス(POI・鉱脈でない場合)で、そのマスの地形のタグを対象にする行為のうち `cooldownDays > 0` のどれかが、そのマスで今クールダウン中なら、見た目を変える: `glyph = TilePalette.spentGlyph`(新しい定数。「∴」)、`tint = TilePalette.terrain(id) + ".spent"`。クールダウン中かの判定は、`Interactions.checkLimits` の式(`w.clock.day - last < cd`)と同じ 1 か所の関数(例: `Interactions.isCoolingDown(def, at:, world:)`)にして、`checkLimits` もそれを使う。
- 区画の版: 採った時(`Interactions` で `harvestedDay` を書く所)に `ctx.changes.markTile(at)`(`cooldownDays > 0` のとき)。クールダウンが明けた日(日が変わった歩み)に、明けるマスも `markTile` する(`harvestedDay` のキーから点を引く関数 `ExplorationState.point(fromKey:)` を足す。層 ID とマス座標の形は `countKey` の逆)。明けたら元の字・色に戻る。
- `TilePalette.style`(`RFPresent/Palette.swift`): `tint` が `terrain.<id>.spent` で終わる時、`terrain.<id>` の色ではなく「地面」の暗い色(`ground` の 60% の明るさ)を返す(背景なし)。`spentGlyph` は定数として公開する(`public static let spentGlyph = "∴"`)。
- 保存の形は変えない(`harvestedDay` は既にある)。

## テスト(`RFPresentTests` と `RFExplorationTests`)
1. 枝を拾う行為(公開の層の `interaction.pick_sticks`。森のタグ・クールダウン 5 日)を送る前後で、そのマスの `TileView` が「元の字・森の色」から「`TilePalette.spentGlyph`・`.spent` の色」へ変わる。隣の森のマスは変わらない。
2. `markTile` が効いて、そのマスの区画の `revision` が上がる(ほかの区画は上がらない)。
3. 5 日後の日が変わる歩みで、そのマスが元の見た目に戻り、区画の `revision` が上がる。4 日後はまだ使い切りのまま。
4. `Interactions.checkLimits` と見た目が食い違わない(使い切りのマスでは行為が `reason.explore.cooldown` で断られ、使い切りでないマスでは通る)。
5. 保存して読み戻しても同じ見た目(`harvestedDay` から導く)。
6. `TilePalette.style("terrain.forest.spent")` の色が `terrain.forest` と違い、字(`spentGlyph`)が森の字(`TilePalette.pickGlyph` の候補)と違う。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る(note の `rf-note-test`)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- 全部のテストを回し、終わるまで待ってからコミットまで進める(途中で返事を終わらせない)。
- 物語の語を公開のリポジトリに書かない。

## コミット
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
