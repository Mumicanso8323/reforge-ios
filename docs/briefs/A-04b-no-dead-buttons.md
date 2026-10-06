# A-04b 押せない物をボタンにしない・「？」の行を並べない・上の帯の見出し(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl。上限なら reforge-impl)。土台: 出す時点の `integration-c` の先頭(A-04a の後)。本体の小さな直し(W-22)とアプリ(一覧・上の帯)。
もと: 最初の 10 分の版(非公開の計画の SL-31・SL-37・SL-38)と、初見の監査の 12・22。オーナーの決まり「できない行動のボタンは置かない」。**この版は日本語だけ**。
原則: 説明・チュートリアル・確認のダイアログで直さない。

## 1. 解禁の要る行為を、解禁まで出さず受けない(W-22。SL-31)
- `docs/briefs/W-22-interaction-unlock-gate.md` のとおり実装する(本体だけ。説明書の「土台は main」は読み替えて、この単位の土台に載せる)。要点: `Interactions.isUnlocked(_:world:gated:)` を 1 か所に置く・`gatedUnlocks` は読み込み時に 1 回だけ作って持つ・`Interactions.start` 系の最初の確かめで `reason.explore.locked`・足元カードの行為の選び出しで解禁前を弾く・保存の形は変えない。文の ID は日本語の表だけに足す(「まだやり方が分からない」程度の中立の文)。
- テストは W-22 の説明書の「テスト」のとおり(公開の層の試験の内容に、試験の研究 1 つと、それで解く試験の行為 1 つを足す)。

## 2. 材料の足りない「建てる」を、押せる形で出さない(M-23。SL-31)
- `BaseTab.build`(`ReForge/Sources/Game/Tabs/BaseTab.swift`)の「建てる」は、足りない物も `Button` で、行に「足りない」と出している。**足りない物は `Button` にしない**: 押せる物(`affordable`)だけ今の `Button`。足りない物は、押せない行(`InkRow` を薄く。`Button` でも `.disabled` でもなく、タップに反応しない)で、`detail` に足りない材料を出す(例: 「あと 木×2」。`BaseView.Buildable` に `missing: [(name: String, quantity: Int)]` を足し、本体の射影 `BaseView` が数える。名前は認識の層を通す)。
- 押せない行にタップの効果・触覚・押下の見た目を付けない。VoiceOver では「足りない」を読み上げの値にする(ボタンの特性を付けない)。
- テスト: 本体(`RFPresentTests`)で、材料が足りない世界の `BaseView.buildable` の `missing` の数。足りる世界では空。アプリ(`ReForgeTests`)で、`BaseTab` の「建てる」の行の種別を決める純粋な関数(例: `BuildRowKind.of(_ option:) -> .button/.plain`)が、足りる物は `.button`、足りない物は `.plain`。
- 使えないタブ(解放前のタブ)は、今も `UIElements` で出していないはずなので、その確かめのテストだけ足す(解放前のタブが `TabBarView` に並ばない)。違えば直す。

## 3. 「？」の行を並べない(SL-38)
- `BaseTab.build` の「半分の気配の影」(`glyph: "？"`・名前と `have/need` の行)をやめる。**知っている作り方だけ**を並べ、知らない物は、影の分も合わせて **1 行**にする: 「まだ作り方を知らない物 N 件」(`glyph` の「？」を付けない。数は `v.unknownStructures + v.shadows.count`。HNT-13 は残す。`accessibilityIdentifier("buildUnknown")` はそのまま)。
- 研究の節の「この先にまだ N 件」(`researchHidden`)も、行頭の「？」の字を外す(文は今のまま)。
- 本体(`FrameBuilder`・`BaseView`)の影の計算(`HintRule.halfway`)は消さない(他で使われている。画面に出さないだけ)。
- 写真(`ScreenSnapshotTests` の `base`): 「？」の字が画面に 0。

## 4. 上の帯の棒は、いつも見出しと今の言葉(SL-37)
- `StatusBandView` の棒(`store.status`)は、`label`(見出し)と `value`(今の言葉)が**どちらも空でない物だけ**を出す。本体の `FrameBuilder.statusItems` で、`label` が認識の層の「不明」(`Perceiver.unknownText` と同じ文)になる物と、`value` が空の物を**作らない**(棒は意味が分かってから出す。今の解禁のまま)。
- 目標の文(`objective`)は 1 行で切らない: `lineLimit(1)` を外し、折り返して全文を出す(帯の高さは増えてよい。ほかの要素を押し下げて地図の枠が動かないよう、帯の外の高さは今の計算のまま)。
- 棒の目盛り(`gauge`)は今のまま(見え方が `showMarks` の時だけ)。
- テスト: 本体(`RFPresentTests`)で、見出しが不明の統計と値が空の統計は `Frame.status` に入らない。写真(`ScreenSnapshotTests`): 上の帯の棒に、見出しの無い物が 0。目標の文が切れない(省略記号「…」が無い)。

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
Claude-Session: (依頼の文で渡される URL)
```
