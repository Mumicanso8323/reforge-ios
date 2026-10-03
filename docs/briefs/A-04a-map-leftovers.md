# A-04a 地図の残り: 拡大の既定・帯と操作棒の重なり・ノアの印・縁の線・確かめの穴(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl。上限なら reforge-impl)。土台: 出す時点の `integration-c` の先頭(A-03・W-26 の後)。
もと: 最初の 10 分の版(非公開の計画の SL-20・SL-32・SL-35)と、PT-B5 の未完の分(`docs/briefs/PT-B5-map-touch.md` §2c)、A-02 で出た重なり。**この版は日本語だけ**。
原則: 説明・チュートリアル・確認のダイアログで直さない。押せない行動のボタンを出さない。

## 1. 拡大の既定は 44pt(SL-20)
- `MapZoomPlan.defaultZoom`(`ReForge/Sources/Game/MapTouchSettings.swift`)の既定を、どの案でも **1 マスが 44pt 以上の段**にする(案 B なら添字 2 = 44pt)。起動・新しい世界・夜明けの視界の広がりで、段を自動で変えない(10 分の中は 44pt のまま。ピンチと「＋」「−」の手動は今のまま使える)。
- 画面に収まらない範囲は、追従(ノアを中央に置く)で見る。歩ける範囲全体を 1 画面に入れることは求めない。
- テスト(`ReForgeTests`): 3 案すべてで既定の段が 44pt 以上。新しい世界のカメラの `cellSize` が 44 以上。

## 2. 帯と操作棒・「＋」「−」「◎」の重なり(A-02 の続き)
- A-02 で、決断・夜・取り消しの帯が地図の下端に重なるようになった。操作棒(台 132pt)と「＋」「−」「◎」は同じ下端にあるので、帯が出ている間は**帯の上へ、帯の高さだけ持ち上げて**置く(重ならない。地図の枠そのものは動かさない)。帯の高さは `PreferenceKey` で `GameScreen` へ上げる(`BandOverlayLayout` に、持ち上げ量を返す純粋な関数 `controlLift(band:)` を足す)。帯が無い時は今の位置。
- テスト(`ReForgeTests`): `controlLift` は帯が無ければ 0、帯があればその高さ(最大でも地図の領域の高さの半分)。写真(`ScreenSnapshotTests` の `decisionBand`): 帯の枠と操作棒の枠が交わらない。

## 3. 選んでから歩く(SL-32)の確かめ
- PT-B5 で入っているはずの形(1 度目のタップは選ぶだけ・同じマスをもう 1 度押すと歩く)を、アプリのテストで固める。`GameStore.select(_:)` の後で `route` と Noah の行き先が変わらない。同じマスの 2 度目の `select` で歩き出す(`walkToSelection` 相当)。選びは保存しない(`GameStore` を作り直すと nil)。
- 食い違いがあれば、PT-B5 の §2 に合わせて直す(直した所を報告する)。

## 4. ノアの印を 1 つに(SL-35)
- 地図(`ActorSprite`)・仲間の画面・足元カードで、ノアを表す字が食い違っている(パネルの側に直書きの "@" がある)。`TilePalette.noahGlyph` を**唯一の出どころ**にし、アプリの画面(`ReForge/Sources/**`)に直書きの "@" を残さない(`MapCanvasView` の「◎」の中の字も `noahGlyph` を引く)。
- 仲間の印: 地図では一員が全員 `noahGlyph` で描かれ、色だけで分けている。ノア以外の一員は、ノアと同じ字のまま色を変えるのをやめ、**字の形を分ける**: 仲間の字は 1 つ別にして(`TilePalette.memberGlyph`。仮に「○」。art-director が決め直せる)、向きの三角はそのまま。ノアの印は 1 つ。
- テスト(`ReForgeCore` の `RFPresentTests`): ノアの `ActorSprite.glyph == TilePalette.noahGlyph`、ノア以外の一員の glyph は `TilePalette.memberGlyph`。静的: `tools/check-app-names.py` に、`ReForge/Sources` の Swift に直書きの `"@"` が無いことの検査を足す(`noahGlyph` の定義の行は除く)。

## 5. 歩ける範囲の縁の線(B5 の残り)
- `Frame.walkable`(行ごとの横の範囲)の縁を、細い線(1.5pt、`InkColor.accent` の 60%)で描く。`MapScene.drawMoving`(PERF-01 の動く層)で、行の両端と、範囲の上下の端の外側にだけ引く(内側の線を引かない)。範囲が変わった時だけ作り直す(経路の `Path` を `MapScene` の外へ出して、`walkable` が同じ間は使い回す)。範囲の外は今まで通り黒。
- 夜の灯りの中、昼の視界の中のどちらでも出す。範囲が空(最初の行為の前)なら描かない。
- テスト: 縁の線の `Path` を作る純粋な関数(例: `WalkEdge.segments(spans:) -> [(from: GridPoint, to: GridPoint)]`)を `ReForgeTests` で確かめる(正方形の範囲 → 4 辺、凹んだ範囲 → 凹みの辺、空 → なし)。

## 6. 確かめの穴(B5 の残り。本体のテスト)
`ReForgeCore` の `RFCrewTests`(または `RFPresentTests`)に足す。実装が食い違っていたら、直して報告する。
1. **押した瞬間のバー(M-17)**: 押し続ける行為の開始の `Frame` で、そのカード(`FootCard.Action` または足元の作業の進み)の `progressPermille` が 0 で出る(nil ではない)。
2. **夜に灯りの縁で止まる**: 夜に火床が灯っていて灯りの半径が視界の半径(5)より小さい世界で、`steer` で縁へ向かうと `steerBlocked(edge)` が出て縁の外へ出ない。灯りが無い夜(半径 5 の視界)では、同じ操作が縁で止まらない(半径 5 の外までは歩かない)ことも確かめる。
3. `walk(to:)` の行き先が `Frame.walkable` の外なら `reason.crew.out_of_range` で断られる(夜と昼の両方)。

## 受け入れ
- 本体: `swift test --package-path ReForgeCore` が公開の層で全部通る(note の `rf-note-test`)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- アプリは hub で組めない(macOS の CI で統合担当が確かめる)。`@MainActor` の `GameStore` と SwiftUI の型に気をつけて書く。
- 全部のテストを回し、終わるまで待ってからコミットまで進める(途中で返事を終わらせない)。
- 物語の語を公開のリポジトリに書かない。

## コミット
メッセージは中立に。節ごとにコミットを分けてよい。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
