# 説明書 W-05: 生産ボットの基準の見直し(TEST-R1-02 を生成したコンテンツで測り、4.5 倍に)

作業の単位: 序盤 W-05(設計: reforge-plan `docs/plans/2026-10-02-opening-and-industry-depth.md` v0.7 以降の W-05・§4.2〜§4.4・DEC-O4・RISK-O3・§2.6.3・§5.7.1)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。土台: integration-d の先頭。
依存の確かめ(2026-10 の時点。コードで確認済み): W-03(炉の熱 `FurnaceHeat`・batch 2)・W-15 の 2 段目の本体(行為の `yieldsTo: site` と、建造物の中から経路で運ぶ `Hauling`)は**入っている**。W-13(序盤の表をなぞるボット `OpeningScriptBot`)は**無い**(`FirstTenMinutesBotTests` は最初の 10 分だけ)。W-12(石炭の鉱脈・森のマスの保証)は**無い**。だからこの単位に、**必要な最小のラインのボット**(2.2)を含める。W-13 が後で入ったら、2.2 の `Provision` を実際の採取に差し替える(ボットの方針の表はそのまま使う)。
**Codex は内容を調整しない。** 基準に届かなかったら、測った比と原因の手がかりを出して終える(5 の「つまみ」は統合担当が回す)。

## 1. 目的
今の TEST-R1-02(`ReForgeCore/Tests/AcceptanceTests/ProductionBotTests.swift`)は、試験の重ね(モジュール 3 つ・採掘口は鉄板 6 と薪・炉は薪 2・木炭 200 を最初から持つ・手作業は炉の熱なし)で測っていて、基準も 3 倍(`3 * best`)。設計は、これを根拠にしない(DEC-O4・レビュー H1)。次の 3 点を直す。
1. **生成したコンテンツ**(7 つのモジュール・本物の費用・始まりの持ち物は空)で測る。非公開の層が無い公開のみの実行では、**同じ数を中立の ID で写した公開の束**で回す。
2. **手作業ボットにも炉の予熱と保温を課し、手で溶かす(P-06)を使う**。仲間は維持・燃料・建設にだけ使い、掘る・溶かす・叩く・運搬のラインの仕事には付けない。
3. 基準を **ラインの最良日(4〜10 日目)≥ 手作業の最良日(1〜6 日目)の 4.5 倍**(`best * 9 / 2`)にし、**燃料の道 A(窯)と B(石炭)の両方**で縛る。B は 5 日目、A は 9 日目に越える見込み(設計 §4.4)。

## 2. 作るもの

### 2.1 内容の束(`Tests/AcceptanceTests/LineBotContent.swift` 新規)
```swift
enum LineBotContent {
    enum Source: String { case generated, publicBundle }
    /// 非公開の層があれば生成したコンテンツ(TestContent.full())。無ければ publicOnly() に Fixtures/LineBotPublicBundle.json を重ねる。
    /// 環境変数 REFORGE_W05_SOURCE=public で、非公開の層があっても公開の束にできる(突き合わせ用)。
    static func load() throws -> (content: ContentDB, source: Source)
}
/// ボットが引く ID と数(束の側が決める。ボットは数を直に書かず、ここと content から読む)。
struct LineBotKit { /* module/structure/handwork/interaction/item の ID。既定値は下の表 */ }
```
- 公開の束 `Tests/AcceptanceTests/Fixtures/LineBotPublicBundle.json`(新規。`Package.swift` の AcceptanceTests に `exclude: ["Fixtures"]`、読み込みは `#filePath` から。`RFSaveTests` と同じ作法)。**物語の語を含まない。ID は生成したコンテンツと同じ中立の語**。`TestContent.publicOnly()` に重ね、既にある `content/public` の定義と数が合わない所だけ上書きする。数(設計 §2.6.4・§4.2 の値。非公開の層は Codex には読めないので、この表が正):

| 物 | ID | 数 |
|---|---|---|
| 時計 | — | 昼 28800 ゲーム秒(実 180 秒)・夜 64800。1 回の処理 9600 ゲーム秒 |
| 採掘口 | `minehead` | 費用 石 4・木 2。鉱脈の上。1 回で鉱石 2(鉱脈を 1 減らす) |
| 炉 | `furnace` | 費用 石 8・粘土 4。**batch 2**。`hearth.furnace` は `FurnaceHeatDef()` の既定(1100℃・予熱 木炭 2・1.5 時間・保温 木炭 0.4/時・石炭 0.3/時・薪は 900℃ まで・燃料が来ないと 1 時間に 200℃ 下がる) |
| 叩き台 | `anvil` | 費用 石 4・木 1。batch 1(1 日 9.75 枚) |
| 窯 | `charcoal_kiln`(建造物) | 費用 石 4・木 6・建てる 3 時間。行為 `interaction.burn_charcoal`: 4 時間・押すと続く(`hold: false`)・木 3 → 木炭 2・`yieldsTo: site`(窯の中に溜まる) |
| 木を伐る | `interaction.chop_wood` | 2 時間で 4〜6 本(P-01) |
| 手作業 | `handwork.mine` / `handwork.smelt` / `handwork.hammer` | 掘る 12 回(鉱脈の上)・**溶かす 8 回(炉の隣・炉が 1100℃ 以上のときだけ)**・叩く 16 回 |
| 運搬 | 既定の `HaulingDef` | 1 人 1 日 10・8 マスを超えると落ちる |
| 仲間の速さ | `crewWork.gatherWorkPermille` | 600(採取と手作業。運搬と建設は 1000) |

### 2.2 ボット(`Tests/AcceptanceTests/LineBot.swift` 新規。今の `ProductionBotTests.Bot` の道具 `tick`・`walk`・`hold`・`pocket`・`craft`・`mine` を移して使う)
共通の決め:
- 世界: 新しい世界(始まりの持ち物は空)。仲間は 4 人(`content.people` のうち操作する人以外を ID 順に 4 人。入り方は測らない)。鉄の露頭(純度 20〜35%・30〜70 回)を拠点の 8〜20 マスに、2 つ目の鉄の鉱脈(露頭から 6〜12 マス・40〜70 回)を、石炭の鉱脈(炉から 12〜20 マス・40〜80 回)を、seed で置く(W-12 が入るまで今の `Bot.init` と同じ作法でボットが置く)。
- 日の数え方は今のボットと同じ(`w.clock.day`)。1 日 = 昼の実 180 秒 + 寝る。歩くのは 1 秒 4 マス。
- 材料の**授与**(`Provision`。W-13 までの代わり): 建造物の費用(石・粘土・木)は、置く直前にその分だけ拠点の蓄えへ足す。足した量は結果に記録して報告に出す(下の表。日は設計 §2.3・§2.6.1 の予定)。**燃料の元の木は授与しない**(下の労働の台帳で作る)。

| 日 | 置く物(授与する費用) |
|---|---|
| 2 | 炉 1 |
| 3 | 採掘口 1・叩き台 1・窯 1 |
| 4 | 叩き台 2 台目 |
| 5 | A: 2 つ目の窯(炉から 8 マス以内)/ B: 石炭の採掘口(炉から 12〜20 マス) |
| 6〜8 | 露頭の残りが 3 分の 1 を切ったら、2 つ目の鉱脈に採掘口・炉・叩き台を隣り合わせで置き直し、経路を付け替える(石 16・粘土 4・木 3。建てるのは仲間 6 時間) |

**手作業ボット `HandOnly`**: 毎日、昼の残りで、炉の予熱(木炭 2)→ 鉱脈まで歩く → 手で掘る → 戻って手で溶かす(炉の隣・炉が熱いとき)→ 手で叩く、を作れるだけ。炉は 2 日目に置く(1 日目は炉が無いので 0 枚でよい)。木炭は**仲間が用意する分として拠点の蓄えに授与してよい**(1 日 10 まで。保温の分の木炭を炉の入口へ入れる。毎晩冷える)。仲間は掘る・溶かす・叩く・運ぶに付けない(維持・燃料・建設だけなので、この台帳では何もしない)。
**ラインボット `Line(path: .A / .B)`**: 設計 §2.3・§2.6.3 の表をなぞる。
- 1〜2 日目は `HandOnly` と同じ。3 日目に採掘口・叩き台・窯を置き、`placeFromDesign` で札(`[採掘口, 炉, 叩き台]`)の経路を作る。4 日目に叩き台を 2 台にする。
- 燃料の道 A(窯): 炉から 8 マス以内に窯 2 つ。窯 → 炉の経路(`.logistics(.link(from: .placement(窯), to: .placement(炉)))`)。窯で炭を焼く行為は仲間に `.gather(interaction: burn_charcoal, at: 窯)` で付ける。運ぶ手は 4 日目まで 1 人、9 日目から 2 人(`.haul(route:)`。専任は夜も運ぶ)。
- 燃料の道 B(石炭): 石炭の採掘口 → 炉の経路。運ぶ手は 1 人。予熱の木炭 2 だけは窯(または授与しない木)から要る。
- **労働の台帳 `Labor`**: 仲間 4 人 × 8 時間 = 毎日 32 人時。配属(運搬・窯・建設)に使った時間と、**木を伐る時間**を記録し、**その日の伐る人時 × 内容の `interaction.chop_wood` の毎時の本数 × 0.6** の本数の木を、その朝に拠点の蓄えへ足す(W-13 までの代わり)。伐る人時 = 32 − 配属の人時(0 を下回らない)。32 を超える配属は作らない(超えるなら配属を減らし、結果の `laborShortfall` を日ごとに記録する)。
- 迷いは**手作業に有利な側**に倒す(ラインに有利な省略をしない)。倒した判断は報告に書く。
- 結果 `LineBotResult`: 日ごとの鉄板の数(手で作った分 + ラインの分)・日ごとの手で掘った鉱石 / ラインが掘った鉱石・各夜明けの手元の鉄板の累計・日ごとの炉が熱かった時間・日ごとの木炭の使用・授与した材料・`laborShortfall`。

### 2.3 基準(`ProductionBotTests.testR1_02_LineBeatsHandwork` を書き換える。名前は変えない)
seed ごと、道 A・B それぞれで:
1. **4.5 倍**: `lineBest = max(line.plates[d], d in 4...10)`、`handBest = max(hand.plates[d], d in 1...6)`。`lineBest * 2 >= handBest * 9`(設計の `best * 9 / 2` を丸めずに書いた形)。`handBest == 0` の seed は失敗(測れていない)。
2. **累計の逆転**: 5 日目の夜明けの手元の鉄板の累計が、手作業ボット以上(設計 §4.3: 生成したコンテンツでは 4 日目の夜〜5 日目の夜明け。今のテストの「4 日目の夜明け」は 1 日遅れる)。
3. **手の割合**: ラインボットの掘った鉱石のうち手で掘った割合が 1 日目 80% 以上・4 日目 30% 以下。
4. 失敗の文に、seed・道・`lineBest`・`handBest`・比(‰ の整数)を入れる。**成否にかかわらず**、seed 0 の日ごとの表と、全 seed の最小の比(‰)・最小の seed を `print` する(接頭辞 `W05|`。統合担当が読む)。
- seed の数は `REFORGE_R1_02_SEEDS`(既定 100・CI は 20 のまま)。走りごとに内容を読み直す今の作法を保つ。ヘッダのコメントを、新しい測り方(束・3 つの前提・基準)に書き直す。
- 1 本の走りが長いので、`Bot.systems`(時間・生産・運搬・発明)に、配属の実行に要る最小のシステム(人の配属で窯の行為と運搬を動かす `CrewSystem` など)だけを足す。重い歩く・見る・出来事は入れない。足したシステムの理由をコメントに書く。

### 2.4 小さな試験(`Tests/AcceptanceTests/LineBotTests.swift` 新規)
1. `HandOnly` の木炭の使用が、1 日 4〜6.5(予熱 2 + 保温 3.2 の前後)。
2. 同じ seed で 2 回走らせて結果が一致する。
3. `Labor`: 配属 + 伐る = 32 人時以下。伐る人時 0 の日は木が増えない。
4. 束: `LineBotContent.load()` が両方の源で、`LineBotKit` の ID を全部引ける(無ければ、どの ID が無いかを失敗の文に)。

## 3. 確かめのコマンド(テストは hub だけ。絞って回す)
```
REFORGE_R1_02_SEEDS=10 ~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -e REFORGE_R1_02_SEEDS -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter ProductionBotTests --filter LineBotTests
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-public-spoilers.py
```
- 100 走・全体は回さない(統合担当が非公開の層を重ねて回す)。10 走の所要時間を報告に書く(10 分を超えたら走りを間引く工夫を相談)。

## 4. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Tests/AcceptanceTests/`(`ProductionBotTests.swift`・`LineBot.swift`・`LineBotContent.swift`・`LineBotTests.swift`・`Fixtures/LineBotPublicBundle.json`)、`ReForgeCore/Package.swift`(AcceptanceTests の `exclude: ["Fixtures"]` だけ)。
- 触らない: `ReForgeCore/Sources` の全部(本体の数・規則を直さない)・`content/public`・`content/private`・`RFTestSupport`。本体のバグ(例: 経路が動かない)を見つけたら、直さず、再現の手順を報告に書く。

## 5. 届かなかったとき(統合担当が回す。Codex は回さない)
テストは 4.5 倍に届かなくても、測った表を出して終える(コミットの本文に最小の比(‰)を書く)。届かないときに動かすつまみは、設計 §4.4 の順番:
1. **手作業ボットに予熱と保温を正しく課しているか**を確かめる(表の `木炭の使用` が 1 日 5.2 前後か)。
2. **ラインのボットが叩き台 2 台と燃料の道を解いているか**を確かめる(`炉が熱かった時間` が B で 5 日目から 24 時間前後、A で 9 日目に 26 時間か。`laborShortfall` が 0 か)。
3. 木を伐る量(P-01。`interaction.chop_wood` の本数)と窯の取れ高(`burn_charcoal` の木炭)。データ(`world/actions.json` の行為)で直す。
4. 焼け残りの刃(作業の速さ 1.5 倍・9 日)をラインのボットが使う(`LineBotKit` の `useBlade` の旗を立てる。ボットは旗を読むだけで、既定は偽)。
数で埋めるのは最後。基準そのもの(4.5 倍)を下げるのは、設計の判断(DEC-O4)を覆すので統合担当が相談する。

## 6. 約束
- 公開リポジトリに物語の語を書かない。束の ID・人の ID は中立(`item.test.*`・`person.test_*` など。生成したコンテンツと共通の語は `minehead`・`furnace`・`anvil`・`charcoal_kiln` のような工程の語だけ)。
- 押せない物をボタンにしない(この単位はテストだけで、画面に触らない)。
- 整数だけで基準を書く(比の表示だけ ‰ の整数)。
- 物語の本文を変えない。保存の形を変えない。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(統合担当が非公開の層を重ねて回し、公開の束との数・ID の差を突き合わせる)。
- 枝の名前・先頭のハッシュ・3 の所要時間・seed 0 の日ごとの表(手作業・A・B)・全 seed の最小の比(‰)と道・授与した材料の合計・`laborShortfall` が出た日・手作業に有利な側へ倒した判断の一覧・W-13 で差し替える所(`Provision`・`Labor`)。
