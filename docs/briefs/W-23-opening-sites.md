# W-23 始まりの火の置き場を生成の時に決め、まわりの森を保証する(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 出す時点の `integration-c` の先頭。小さな単位。
もと: game-designer の最初の 5 分の見直し v0.2 の INV-F3。最初の火を点けた直後に、手の届く所と灯りの中に、採れる森が無い始まりがある。今の `OpeningRules.emberForestRadius 3 / emberForestMin 6` は残骸(拠点の中心)から数えていて、ノアの始まりのマスや、火の置き場の灯りの中とは限らない。

## 決めたこと(名前は統合担当の決め)
- **火の置き場を生成の時に決める**: 地図の生成(`OpeningRules` の始まりの整え)の最後に、ノアの始まりのマスから今の `OpeningRules.firstFireSite`(`StructureSites.spot` と同じ順)で置き場を探し、地図の層に `firstFireSite: GridPoint?` として持つ(`MapLayer`。生成の結果なので保存の形に入る場合は、欄を任意にして古い保存は nil で読む。凍った見本は作り直さない)。
- **置き場を指す形**: `PlaceSelector` に `case openingSite(kind: OpeningSiteKind)`(`enum OpeningSiteKind: String, Codable { case firstFire }`)を足す。`.openingSite(.firstFire)` は層の `firstFireSite` を指す。置き場が無い・建てられない(塞がった)時は、今の探し方(`StructureSites.placeFromEffect` の近くを探す形)に戻す。
- **森の保証**: `OpeningRules` に `startReachForestMin: Int`(既定 1)と `firstLightForestMin: Int`(既定 2)を足す。生成で、ノアの始まりのマスの隣 8 マスに森が `startReachForestMin` 以上、`firstFireSite` から半径 2(チェビシェフ)に森が `firstLightForestMin` 以上になるよう、足りなければ乾いた陸(草地・整地。置き場とノアのマスと残骸は除く)を森にする(乱数を使わない。近い順・同じなら y → x)。
- データの側(非公開の層の `light_fire` の `placeStructure.at` を `.openingSite(.firstFire)` に替える)は U14。

## 追加(最初の 10 分の版 SL-16): 夜明けに初めて見える置き場
- `OpeningSiteKind` に `dawnFind` を足し、層に `dawnFindSite: GridPoint?` を持つ(任意の欄。古い保存は nil)。
- 決め方(生成の時。乱数を使わない): `firstFireSite` から見て、**最初の夜の灯りの中には入らず**(火床の最大の段の灯りの半径より外。ノアの始まりのマスの隣 8 マスにも入らない)、**1 日目の夜明けの昼の視界には必ず入る**(昼の視界の今の決まりで、夜明けにノアが `firstFireSite` のそばにいる時に見える範囲の内側 1 マス以上)。その帯の中で、乾いた陸・建てられるマスを、残骸(拠点の中心)から遠い順 → y → x で 1 つ。無ければ帯を 1 マスずつ広げる。
- データの側(U14)は、今の効果 `placeStructure(at: .openingSite(.dawnFind), built: true)` で、その置き場に物を置く。行為の無い物なので、足元カードにボタンは出ない(PT-B5 §2c と同じ決まり)。
- テスト: 1000 個の seed で `dawnFindSite` が非 nil・最初の夜の灯りの外・1 日目の夜明けの昼の視界の中(視界の計算は本体の今の関数を呼ぶ。式を写さない)。

## テスト(Linux。公開の層)
- 1000 個の seed で: 始まりのマスの隣 8 マスに森が 1 以上・`firstFireSite` が非 nil で建てられる・その半径 2 に森が 2 以上(TEST-F3)。
- `.openingSite(.firstFire)` で `placeStructure` すると、`firstFireSite` に置かれる。塞いでおくと、今の探し方で近くに置かれる。
- 生成の決定性: 同じ seed で同じ地図(今のテストのまま)。地図の見本のテストがあれば、変わる分だけ直す(凍った保存の見本は作り直さない)。

## 受け入れ
- `swift test --package-path ReForgeCore` が公開の層で全部通る。統合担当が非公開の層を重ねて回す。
- 静的: `check-app-switches.py`(`PlaceSelector` に case を足すので)・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
