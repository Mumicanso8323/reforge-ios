# A-02 決断の帯: 問いの文と、画面の下に重ねる置き方(Codex への説明書)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 出す時点の `integration-c` の先頭。本体(RFContent・RFPresent)とアプリの両方。
もと: 最初の 10 分の版(非公開の計画の SL-17)と、初見の監査の 2・3。**この版は日本語だけ**(翻訳はしない)。

## 目的
- 決断(選ぶ帯)に**問いの文**を 1 行つけられるようにする。問いが無いと、選ぶボタンだけが出て、何を決めるのか分からない。
- 決断の帯と夜の帯(夜作業・寝る)を、**画面の下 1/3 に重ねて出す**。今は地図の下に並べているので、帯が出入りするたびに地図の高さが変わり、地図が動く。重ねれば地図は動かない。

## 1. 本体: 問いの文
- `EventDef`(`ReForgeCore/Sources/RFContent/Schema/Defs.swift`)に `public var prompt: TextID?` を足す。既定は nil(今の内容は壊れない。`Codable` は省略可で読める)。`choices` があるイベントだけが使う(無い時に書かれていたら検証でエラー: rule `event.prompt.no-choices`)。
- `ContentValidator.nonPerceptionRefs`(`ContentValidator.swift`)に、`prompt` のテキスト鍵を足す(`choices` の `label` と同じ扱い。足りないと、文の表の欠けの確かめが落ちる)。
- `DecisionView`(`RFPresent/Frame.swift`)に `public var prompt: String?` を足し、`==` に入れる。`FrameBuilder.decision` で `content.events[d.event]?.prompt.map { p.text($0) }` を入れる(認識の層 `Perceiver.text` を通す。名前を出す文は、既に N-03 の見出しを通る)。
- 保存には何も足さない(`PendingDecision` は変えない。問いはイベント定義から引く)。

## 2. アプリ: 重ねる置き方
- `GameScreen.swift` の `game` は `VStack` で、地図の `ZStack` の下に `MapActionBand`、その下に `FootCardView`、`TabBarView` を並べている。`MapActionBand` を `VStack` から外し、**地図の `ZStack` の下端に `overlay(alignment: .bottom)` で重ねる**。地図の大きさ・位置は、帯が出ても出なくても同じ。足元カードとタブの棒は今のまま。
  - 帯が重なる範囲は、地図の領域の下端から帯の高さまで。帯の背景は今のとおり半透明のパネル(`InkColor.panel.opacity(0.96)`)。
  - 帯が出ている間の地図のタップは、帯の外では今のまま通る(帯の上は帯のボタンが受ける)。
- `MapActionBand` の決断の帯: 上に問いの文(`decision.prompt` があれば。折り返してよい。文字は `InkFont` の本文の段)、その下に選ぶボタンの並び。ボタンは **44pt 以上**。文が無い決断(今の内容)は、今と同じボタンの並びだけ。
- 夜の帯(`bandActions`)と取り消しの帯(`UndoBand`)も同じ位置に重ねる(中身は今のまま)。一日の締めの文(`DayWrapLinesView`)は帯の中に今のまま。
- VoiceOver: 問いの文は、ボタンの前に読まれる(上から下の順)。`accessibilityIdentifier("decisionPrompt")` を付ける。

## テスト
- 本体(`RFPresentTests`): 問いのあるイベントの決断で `Frame.decision.prompt` が文になる。問いの無いイベントでは nil。検証(`RFContentTests`): `prompt` の鍵が文の表に無いとエラー・`choices` の無いイベントに `prompt` があるとエラー。
- アプリ(`ReForgeTests`): 帯が出る・出ない、で地図のビューの枠が変わらない(`MapActionBand` を重ねる側の枠の計算を、純粋な関数に出して確かめる。例: `BandOverlayLayout.mapFrame(container:band:)` が帯の高さによらず同じ値を返す)。
- 画面の写真(`ScreenSnapshotTests` の `decisionBand`): 見本の決断に問いの文をつける(`ScreenshotMode` の見本の内容)。写真で、問いの文が見える・選ぶボタンが画面の下 1/3 にある(要素の枠の中心 y が画面の高さの 2/3 より下)・地図の枠が帯のある写真とない写真で同じ。

## 受け入れ
- 本体: `swift test --package-path ReForgeCore` が公開の層で全部通る(note の `rf-note-test`)。
- 静的: `check-app-switches.py`・`check-app-names.py`・`gen-xcstrings.py --check`・`check-public-spoilers.py`。
- アプリは hub で組めない(macOS の CI で統合担当が確かめる)。`@MainActor` の `GameStore` と SwiftUI の型に気をつけて書く。
- 物語の語を公開のリポジトリに書かない(見本の問いは「テスト用の文」のような中立の文)。確認のダイアログを足さない。押せない行動のボタンを出さない。

## コミット
メッセージは中立に。末尾は統合担当の決まりの 2 行:
```
Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Bk5mMUPjcpLyRtpyHwRQNF
```
