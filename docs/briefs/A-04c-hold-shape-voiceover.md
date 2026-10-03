# A-04c 長押しの行為の形と輪・読み上げの名前(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl。上限なら reforge-impl)。土台: 出す時点の `integration-c` の先頭。アプリだけ(本体の変更は無いか、ごく小さい)。
もと: 最初の 10 分の版(非公開の計画の SL-33・SL-44)と、初見の監査の 10・24。**この版は日本語だけ**。
原則: 説明・チュートリアル・確認のダイアログで直さない。押せない行動のボタンを出さない。

## 1. 長押しの行為は形で分かる(SL-33)
- 足元カードの行為(`ActionButton`・`ReForge/Sources/Game/FootCardView.swift`)と、暗い場面の行為(`DarkStartActionButton`・`DarkStartScene.swift`)で、`action.hold == true` の行為は、**押すだけの行為と形が違う**ようにする。
  - 形: 長押しの行為は、ラベルの左に**輪**(直径 22pt の細い円。縁 2pt、`InkColor.rule`)を置く。押している間、輪の縁が `action.progressPermille`(0...1000)に合わせて 12 時の位置から時計回りに満ちる(`Circle().trim(from: 0, to:)`、色は `InkColor.accent`)。押していない時は縁だけ(満ちていない)。押すだけの行為には輪を付けない。
  - 押した瞬間(次の `Frame` を待たない)、輪は 0 から満ち始める(押し始めの `progressPermille` が nil でも、画面が自分で 0 として描き、`Frame` の値が来たらそれに合わせる。M-17)。
  - 「動きを減らす」の時も輪は満ちる(動きではなく進み具合の表示)。ただし、満ちる動きを補間のアニメにしない(`Frame` の値に合わせて刻む)。
  - 輪はボタンの押せる範囲(44pt 以上)の内側に収める。ラベルが長い時は、ラベルを折り返さず `lineLimit(1)` + 縮小(`minimumScaleFactor(0.8)`)。
- 部品: `HoldRing`(`ReForge/Sources/Theme/` に新しい 1 ファイル)。進みの値 → 描く弧の長さを決める純粋な関数 `HoldRing.trim(permille: Int?, pressing: Bool) -> CGFloat`(nil で押していなければ 0、押していて nil なら 0、値があれば 0...1 に丸める)を `ReForgeTests` で確かめる。
- 写真(`ScreenSnapshotTests`): 足元カードに、押すだけの行為と長押しの行為が並ぶ写真を 1 枚(公開の層の試験の内容にある長押しの行為と、押すだけの行為を使う)。長押しの行為の要素に輪の識別子(`holdRing`)があり、押すだけの行為に無い。

## 2. 読み上げの名前と読む順(SL-44)
- 次の 4 つに、読み上げの名前を付ける。
  1. 暗い場面の最初の行為(`darkStartAct`): 名前は `action.label`(「火を起こす」に当たる文。内容から来る)。長押しの時は、値として「長押し」を付ける(ボタンの特性 `isButton` も)。
  2. 操作棒(`stickControl`): 今の「移動の操作棒」に、`accessibilityHint` は付けない(説明はしない)。調整可能な要素(`accessibilityAdjustableAction`)にして、上げる・下げるで 8 方向のうち東・西へ 1 歩ずつ歩く、は**作らない**(説明が要る操作を足さない)。名前だけ。
  3. 場面の送り(`prologueScene`・全画面の場面): 今の名前(全行を読み上げ)・ボタンの特性・既定のアクションのまま。確かめのテストだけ足す。
  4. 足元カードの行為(`ActionButton`): 名前は `action.label`。長押しの行為は値「長押し」、特性 `isButton`。押すだけの行為は `Button` の標準のまま。
- 読む順: 画面の上から下。`GameScreen` の読む順の優先度(`accessibilitySortPriority`)で、上の帯(状態) → 地図(操作棒) → 足元カード → タブの棒の順にする。全画面の場面と暗い場面の間は、その場面の要素だけ(地図・タブは作らない現状のまま)。
- テスト(`ReForgeUITests`): 暗い場面で `darkStartAct`、地図で `stickControl`、足元カードの行為、全画面の場面の送り、の 4 つが `isAccessibilityElement` で、`label` が空でない。地図の要素の `accessibilityFrame` の y が、上の帯 < 地図 < 足元カード < タブの棒 の順。
- 純粋な関数に出せる所(読み上げの値の文: 長押しなら「長押し」、押すだけなら nil)は `ReForgeTests` で確かめる。

## 受け入れ
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`(文を足したらカタログを作り直す)・`check-public-spoilers.py`。
- 本体を変えた場合は `swift test --package-path ReForgeCore` が公開の層で全部通る(note の `rf-note-test`)。
- アプリは hub で組めない(macOS の CI で統合担当が確かめる)。`@MainActor` の `GameStore` と SwiftUI の型に気をつけて書く。
- 全部のテストを回し、終わるまで待ってからコミットまで進める(途中で返事を終わらせない)。
- 物語の語を公開のリポジトリに書かない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
