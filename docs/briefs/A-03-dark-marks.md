# A-03 暗がりの印: 灯りの外でも見える置いた物(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 出す時点の `integration-c` の先頭(A-02 の後)。本体の小さな足し(RFContent・RFPresent)と、アプリの描き(`MapScene.drawMoving`)。
もと: 最初の 10 分の版(非公開の計画の SL-18)。夜の灯りの縁の外に、見えるだけの印を出せるようにする。**物語の語を公開のリポジトリに書かない**(印の見た目の名前は中立に: 「暗がりの印」)。

## 目的
- 内容(非公開の層)が、効果 `placeStructure(structure:at:built: true)` で置いた物を、**灯りの外・未踏のマスにあっても見える**ようにする。見えるだけで、押せる行為は無い。
- 内容は同じ仕組みで、後から `schedule` の出来事 → `destroyPlacements` で消せる(今ある効果。新しい効果は足さない)。
- 内容の側(U14)は、この印を「暗がりに見える物」と「夜明けに残る物」の 2 種に使う。**本体は「目」も「足跡」も知らない**。ただ「灯りの外でも見える」を `StructureDef` の印にするだけ。

## 1. 本体
- `StructureDef`(`RFContent/Schema/Defs.swift`)に `public var seenInDark: Bool?` を足す(既定 nil = false。今の内容は壊れない。`Codable` は省略可で読める)。コメント: 「置いた物が、灯りの外・未踏のマスにあっても見える(見えるだけ。行為は別に定義した物だけ)」。
- `PlacementSprite`(`RFPresent/Frame.swift`)に `public var seenInDark: Bool = false` を足し、`==` に入る形にする(既存の init に既定値で追加。呼び出し側を壊さない)。
- `FrameBuilder.placements`(`RFPresent/FrameBuilder.swift`)の「既知か視界の中のマスにあるものだけ」の絞りを、`seenInDark` の構造は常に通すように変える。通した物は `PlacementSprite.seenInDark = true`。**足元カード・長押しの文・読み上げは今のまま、その場所を押す・調べる時だけ**(遠くの暗がりの印を、押せる物として出さない。DEC-F13)。
- 地図の区画の版(`MapChunk` の revision)には入れない(置いた物は区画に入っていない。区画を作り直さない)。

## 2. アプリ(`MapScene.drawMoving`)
- `placements` のループで、`placement.seenInDark` の物は、視界の外でも描く。明るさは、視界の中なら今の `lit`、視界の外でも **`TilePalette.nightVisible` と同じ段**で描く(見えることが目的。消えかけの「記憶」の暗さにしない)。
- 動きは軽く: `elapsed` から、ゆっくりした明滅(周期 3 秒、明るさ ±15%)をつける。「動きを減らす」の時は明滅なし(一定)。PERF-01 の動く層に描く(新しい Canvas・タイマーを足さない。`drawTerrain` の区画の画像に混ぜない)。
- 灯りの外の暗がりの印の下の黒い塗りは、今のままの `ctx.fill(Path(rect), with: .color(.black))`(霧の黒と同じ)。

## テスト
- 本体(`RFPresentTests`): `seenInDark` の建造物を、視界の外・未踏のマスに `built: true` で置く → `Frame.placements` に入り `seenInDark == true`。通常の建造物を同じマスに置いても入らない(今の挙動のまま)。`destroyPlacements` で消した次のフレームから消える。保存して読み戻しても同じ(置いた物は世界の状態)。
- 本体(`RFContentTests`): `seenInDark` の省略は今までの内容と同じに読める。
- 本体: 暗がりの印のマスを足元カードに出しても、行為のボタンが出ない(定義した行為が無い時)。
- アプリ(`ReForgeTests`): 暗がりの印の明るさの決め方を純粋な関数に出して(例: `PlacementBrightness.value(seenInDark:visible:night:reduceMotion:elapsed:)`)確かめる。視界の外でも `nightVisible` の段。明滅は `reduceMotion` で一定。
- 画面の写真(`ScreenSnapshotTests`): 夜の灯りの縁の外に見本の暗がりの印を 1 つ置いた写真を 1 枚足す(`ScreenshotMode` の見本。内容は中立の形)。印が灯りの外に見えている。

## 受け入れ
- 本体: `swift test --package-path ReForgeCore` が公開の層で全部通る(note の `rf-note-test`)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- アプリは hub で組めない(macOS の CI で統合担当が確かめる)。
- 確認のダイアログを足さない。押せない行動のボタンを出さない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: (依頼の文で渡される URL)
```
