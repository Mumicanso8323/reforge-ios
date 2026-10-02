# 説明書 S-04: 自動と手動の枠を画面で分けて出す・タイトルから読む

作業の単位: 保存の画面(設計: `docs/architecture/D-save.md` §7。オーナーの決定「セーブの枠を手動用と自動用に分ける」)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: なし。土台: integration-c の先頭。
**保存の形は変えない**(`SaveSlot`・ファイル名・`SaveEnvelope`・`schemaVersion`・凍らせた見本・`save-v1.json`)。

## 1. 目的
D §7 の決まりを、本体のテストで固め、画面で自動と手動を見分けられるようにする。中断の枠が読めないときに、タイトルから「セーブから読む」で遊びに戻れるようにする。

## 2. 本体(ReForgeCore)
1. `SaveBook` に、一覧を 2 つに分けて返す口を足す(今の `savePoints()` は残す):
```swift
public struct SavePointGroups: Equatable, Sendable {
    public var auto: [SavePoint]     // 夜明け(新しい順)
    public var manual: [SavePoint]   // 手動(番号順。空いた枠は含めない)
}
public func savePointGroups(activeOnly: Bool) throws -> SavePointGroups
```
2. テスト(`Tests/RFSaveTests/SaveSlotsTests.swift` を新規。D §7.5):
   - 4 択のそれぞれ(`Recovery.perform`)の後の枠の一覧が D §7.1 の表どおり(最初から: 自動と中断が新しい 1 日目だけ・手動は残る / 巻き戻し: 戻った夜明けより先の自動が消える / 失って続ける: 自動はそのまま・中断が書き直される / セーブから読む: 別の走行の自動が消え・手動は残る)。
   - 失って続けた後、次の夜明けで自動の枠が 1 つ足される。
   - 寝る(`.time(.sleep)`)で夜明けに着いた世界に `autosaveDawn` を当てると自動の枠が 1 つ増える。4 日分たまると古いものから消える(3 つ残る)。
   - `savePointGroups(activeOnly: true)` が終わった走行の枠を含めない。読めない枠は `problem` つきで残る。
   - 凍らせた見本(`save-v1-dev-*.json`)の読み込みのテストはそのまま通る。

## 3. 画面(ReForge。macOS の CI でしかコンパイルされない。型と API の名前は目で確かめる)
1. 拠点のタブの「記録」(`Tabs/BaseTab.swift` の `saves`。持ち主 U18。コミットのメッセージに「U18 のファイル」と書く)と、4 択の「セーブから読む」の一覧(`GameOverView.swift`。持ち主 U18)を、**自動と手動の 2 つの節**に分ける。
   - 見出し: `Text("夜明けの記録")`・`Text("自分の記録")`。
   - 自動の行: `Text("\(d) 日目の夜明け")`(今の `slotText` のまま)。
   - 手動の行: `Text("手動 \(i + 1)")` と、中身があれば `Text("\(day) 日目")`、空きは `Text("空き")`(今のまま)。拠点の「記録」では、手動の行に「書く」のボタン(今のまま)。
2. タイトル(`Screens/TitleView.swift`。持ち主 art-director。メッセージに書く): 中断の枠が無い・読めないときに、自動か手動の枠が 1 つでもあれば「セーブから読む」のボタンを出す(識別子 `loadFromTitle`)。押すと、上と同じ 2 節の一覧の札を開き、選ぶと `AppModel` がその枠の世界で遊び始める(`SaveBook.adoptTimeline` と `writeResume` を当ててから。`GameStore.load` と同じ手順)。
   - `AppModel` に `hasSavePoints: Bool` と `loadFromTitle(_ slot: SaveSlot)` を足す(`ReForgeApp.swift`)。
3. 新しい日本語の文言は `Text("…")` のリテラルにする(F §4。L-11 で文言の表に移る)。統合担当がカタログを作り直すので、`Localizable.xcstrings` は触らない。

## 4. 確かめのコマンド
```
~/.local/bin/rf-note-test . --filter 'RFSaveTests|RFFailureTests'
~/.local/bin/rf-note-test .                        # 全体(公開の層)
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
```
- note に ssh できなければ予備(hub)の `rf-swift-slot`。土台を替えたら `rf-note-test -c`。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFSave/SaveBook.swift`、`ReForgeCore/Tests/RFSaveTests/`(新しいテスト)、`ReForge/Sources/Game/Tabs/BaseTab.swift`(記録の節だけ)、`ReForge/Sources/Game/GameOverView.swift`(ロードの一覧だけ)、`ReForge/Sources/Screens/TitleView.swift`(ボタン 1 つと札)、`ReForge/Sources/ReForgeApp.swift`(`AppModel` の 2 つ)。
- 触らない: `SaveCodec`・`SaveSlot`・`SaveEnvelope`・`Fixtures/`・`Recovery` の規則(読むだけ)・`content/`・`Localizable.xcstrings`。

## 6. 約束(F §4)
- 公開リポジトリに物語の語を書かない。
- 保存の形を変えない。凍らせた見本を作り直さない・飛ばさない。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(F §4)。
- 枝の名前・先頭のハッシュ・4 の結果(件数)・ほかの担当のファイルを触った所。
