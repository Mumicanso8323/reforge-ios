# 説明書 W-06: 鉱滓(炉の出口の溜め・詰まり・捨て場)

作業の単位: 序盤 W-06(設計: reforge-plan `docs/plans/2026-10-02-opening-and-industry-depth.md` v0.7 以降の §5.2 の副産物と詰まり・§5.7.1 の鉱滓・OPEN-O4・TEST-O6)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: W-03(炉の熱。`FurnaceHeat`。integration-d に入っている)。土台: integration-d の先頭。
OPEN-O4 の答えは設計の既定を採る(オーナーの判断を待たない非ブロッカー): 炉の熱は R1・**鉱滓は R1 の後半、石灰の道にだけ**出る。叩き重ねの道には出ない。いつ出るか(後半)は本体では決めず、データ(石灰の混ぜ鉢と捨て場の解禁の時期)で決める。

## 1. 目的
石灰を炉の前に混ぜると、炉が 1 回の処理ごとに鉱滓を 1 つ出口に溜める。出口の溜め(既定 12)が鉱滓で満ちると炉が止まり、運び出すか、隣の捨て場が受けると動き出す。捨て場は 60 で満ちる。工業に「捨て場と運搬の手間」という重さを 1 つ足し、石灰の道と叩き重ねの道の選びに差を付ける。
止まったことは**文では見せない**。止まった印の色(落とした赤)と小さな印だけで見せる(理由の文・説明を画面に出さない)。

## 2. 作るもの
今のコードにあるもの(作り直さない): RFMatter の規則 `.byproduct(.slag)`(石灰を持つ鉱石を溶かす規則だけが出す。`RuleBookR1.smelt`)と `ProcessChain.advance` の結果 `StepOutcome.byproducts`、`PlacementStatus.stopped(reason:)`、`Modules.blocker`。**無いもの**: 生産の側が副産物を受ける所(`Modules.processOne` は今 `o.byproducts` を捨てている)・捨て場・止まった印。

### 2.1 RFContent: 副産物の行き先の表
```swift
// ContentDB に 1 つの設定(後の層が同じキーを上書き。JSON のキーは "byproductItems")
public var byproductItems: [ByproductID: ItemID] = [:]
```
- 表に載っている副産物だけが、モジュールの出口に品として溜まる。載っていない副産物(今の砕石・砂・排気)は今までどおり捨てる(何も溜めない)。
- **表が空のコンテンツ(古いデータ・今の公開の層)では、今までとまったく同じに動く**(INV-W06-1)。
- `ContentLoader` の `checkTopLevelKeys` と `ContentFile` に `byproductItems` を足す。`ContentValidator`: 値の品の ID が空でないこと。
- 公開の層(`content/public/`)の JSON は**変えない**。試験は 3 の中で重ね(`ContentLoader.apply(json:to:name:)`)、中立の ID(`item.test.slag` など)を使う。

### 2.2 RFProduction: 出口に溜める・止まる
```swift
// ProductionSystem.swift の ProductionText に足す(止まった理由の鍵。保存に文字列として残る)
public static let wasteFull: TextID = "reason.module.waste_full"
```
- `Modules.cycleOnce` の `.process`: 1 回の処理(`batch` 個ぶんまとめて 1 回)で、`ProcessChain.advance` が返した副産物のうち `byproductItems` に載る物を、**種類ごとに 1 つ**(`batch` が 2 でも 1 つ)、`StockEntry(stuff: .item(item), quantity: 1, origins: [その回の生産の来歴: 1])` で `output` に入れる(`processOne` の返り値で副産物を集める。設計 §5.7.1 の「1 回の処理ごとに鉱滓 1(1 日 9.75)」)。
- 副産物の数: `wasteCount(m, content)` = `output` のうち、品が `byproductItems.values` に入る山の数の合計。
- `Modules.blocker` の `.process` の判定を次の順にする:
  1. `wasteCount >= m.capacity` なら `(ProductionText.wasteFull, nil)`(止まる)。
  2. 出口の物(製品)の数 = `m.outputCount - wasteCount` に 1 を足して `m.capacity` を超えるなら、今までどおり `outputFull`。**鉱滓は製品の置き場を食わない**(製品の溜めと鉱滓の溜めは別々に `capacity` まで)。`.extract`・`.produce` の `outputFull` の数え方も、同じ式(製品の数)にそろえる。
  3. 残りは今のまま。
  開始前に判定するので、1 回の処理が終わったとき鉱滓は `capacity` を超えない。
- 止まっている間は今と同じに進みを進めず、`idleSeconds` を数え、出来事 `.moduleStopped` / `.moduleResumed` を出す(`setStatus` のまま)。
- `Modules.pushOut`: **鉱滓(`byproductItems.values` の品)は、直結の下流へ渡さず、拠点の中でも蓄えへ自動で入れない**(経路が無くても溜まる。これが詰まりの元)。鉱滓が出口を満たしていても、製品の受け渡しは今までどおり動く。鉱滓が出口から出る道は 2 つだけ: (a) 運搬の経路(`Hauling` の既存の動き。経路の行き先が拠点の蓄えなら鉱滓も運ばれる。**`Hauling` は変えない**)、(b) 隣の捨て場(2.3)。
- 片付け(`Placing` の撤去)は今のまま(出口の物は蓄えへ戻る)。

### 2.3 RFProduction: 捨て場
- 建造物の `provides["dump"]` = 受けられる数(60 など)。建て終えた(建造中・壊れていない)建造物だけが受ける。
- 数は `StructureRuntime.parameters["dump.held"]`(既にある `[String: Int]`。**保存の形は変えない**)に持つ。置き場所の型は新しく作らない。
- 新しい `enum Dumps`(RFProduction)に純関数を置く:
  ```swift
  /// モジュールの足(footprint)に辺で接するマス(同じ層)にある、受けられる捨て場(ID の小さい順)。
  static func adjacent(of id: EntityID, in w: WorldState, content: ContentDB) -> [EntityID]
  /// 出口の鉱滓を、隣の捨て場の空きだけ移す(移した数を返す)。移した分は無くなる(捨てた)。
  static func accept(from id: EntityID, _ ctx: inout StepContext) -> Int
  ```
  `Modules.pushOut` の最後で、鉱滓が出口にあれば `Dumps.accept` を呼ぶ。移した数は `today.sent` に数える。捨て場が満ちたら受けない(炉は 2.2 の判定で止まる)。
- 捨て場を片付けたら、溜まった数は消える(戻す物は無い)。

### 2.4 RFPresent: 止まった印(文を出さない)
```swift
/// 文ではなく印と色で見せる止まり方。
public enum StopKind: Equatable, Sendable {
    case wasteFull
    /// 止まった理由の鍵から。印で見せない理由(今までの材料が来ていない等)は nil。
    public static func of(reason: TextID) -> StopKind?
}
```
- `PlacementSprite` に `public var stopKind: StopKind? = nil`(初期化子の引数の既定値 nil で足す)。`BaseView.Built.State` に `case blocked(StopKind)` を足す。
- `.stopped(reason:)` の鍵が `StopKind.of(reason:) != nil` のとき、**`Perceiver.stoppedText` を呼ばない**。`PlacementSprite.stoppedReason` は nil、`State` は `.blocked(kind)`。つまり、鉱滓で止まったことを表す文は Frame のどこにも出ない(`FrameText.allStrings` に理由の文が入らない)。
- ほかの止まり(材料が来ていない・出口が詰まった等)は今のまま(この単位では触らない。後の掃除で印に寄せる)。

### 2.5 アプリ(`ReForge/`。macOS の CI でビルドを確かめる。hub では型検査できない)
- 拠点のタブ `BaseTab.swift` の `state(_:)` に `.blocked(let k)` を足す: `Text("■")`(`.foregroundStyle(InkColor.alert)`。予約の赤 `InkColor.reserved` は使わない)。文字は出さない。読み上げ用に `accessibilityLabel` は `Text("止まっている")` の固定の語でよい。
- 地図: 止まっているモジュールは今も `TilePalette.stopped`(落とした赤)で描かれる(`MapScene`)。変えない。
- `tools/check-no-reason-text.py` の `FILES` に、足した画面のファイルがあれば足す。`gen-xcstrings.py` で `Localizable.xcstrings` を作り直す(「止まっている」だけ増える)。

### 2.6 データの側(**データは統合担当が非公開の層に置く。Codex は書かない**)
- `byproductItems` の表(鉱滓の副産物 → 鉱滓の品)・鉱滓の品(名前・字・色の系統は認識の層)・捨て場の建造物(費用・建てる時間・`provides: {"dump": 60}`・解禁の時期)・石灰の混ぜ鉢の解禁の時期(R1 の後半に合わせる)。
- 非公開の層のテキスト表に `reason.module.waste_full` を**足さない**(足してもよいが画面には出ない)。`BaseTabReasonTextTests` の鍵の一覧にも入れない(印で見せるため)。

## 3. テスト(`Tests/RFProductionTests/WasteTests.swift` を新規。`RFPresentTests` に 1 本。TEST-O6)
共通: `ProductionFixture`(`RFProductionTests/Fixture.swift`)に、`byproductItems = ["slag": "item.test.slag"]` と、`provides["dump"]` を 60 にした中立の建造物 `test.dump`(1 マス)を重ねる(`ProductionFixture(edit:)` か `ContentLoader.apply(json:…)`)。札は採掘口 → 混ぜ鉢(石灰)→ 炉 → 叩き台と、石灰なしの札の 2 通り(`RFProductionTests/ProductionSystemTests.swift` の石灰の札の作り方を見る)。
1. **石灰の道だけ出る**: 石灰を入れた札で炉が N 回処理すると、炉の出口の `item.test.slag` がちょうど N 個。石灰なしの札・叩き重ね(炉で熱し直す段だけを足した札)では 0 個。`batch` 2 の炉でも 1 回の処理につき 1 個。
2. **満ちたら止まる**: 出口の鉱滓が `capacity`(既定 12)に届くと、状態が `.stopped(reason: ProductionText.wasteFull)`・`.moduleStopped` が 1 回・進みが進まない。**製品は流れ続ける**(出口の製品は下流へ渡り、鉱滓だけが残る)。鉱滓が 12 でも製品の置き場は別に 12 ある。
3. **運び出すと動き出す**: 炉から拠点へ経路を引き専任の運び手を付ける(`RFProductionTests`/`RFLogisticsTests` の経路の作り方に合わせる)と、鉱滓が運ばれ `.running`・`.moduleResumed` が出る。経路が無い拠点の中の炉でも、鉱滓は拠点の蓄えに**自動では入らない**(蓄えの鉱滓は 0 のまま)。
4. **隣の捨て場**: 炉に辺で接する `test.dump` があると、鉱滓は捨て場へ移り、炉は止まらず回る。`dump.held` が 60 になった後は受けず、炉は `wasteFull` で止まる。保存の量の釣り合い: 作った鉱滓の数 = 捨て場の数 + 出口の数 + 運ばれた数。建造中・壊れた捨て場、辺でなく斜めの捨て場は受けない。
5. **表が空なら今まで通り**: `byproductItems` の無いコンテンツで石灰の札を 50 回回しても鉱滓は出ず、`wasteFull` で止まらない(既存のテスト全部が通ることでも確かめる)。
6. **決定的**: 同じ seed・同じ入力を 2 回回して、世界が一致する。夜の一括(`.time(.sleep)`)と 1 ステップずつで鉱滓の数が一致する。
7. **保存**: 出口に鉱滓がある・`dump.held` がある世界を `SaveCodec` で往復して一致する。**凍らせた見本(`RFSaveTests/Fixtures`)は作り直さない・読み込みが落ちない**。
8. **印**(`RFPresentTests`): `wasteFull` で止まっている炉は、`Frame` の `PlacementSprite.stopKind == .wasteFull`・`stoppedReason == nil`・`BaseView` の状態が `.blocked(.wasteFull)`。`FrameText.allStrings(frame)` に、`wasteFull` を理由とする文(`content.texts` に同じ鍵の文を重ねて確かめる)が**入らない**。動き出したら `.running`。
9. **検証**: `byproductItems` の値が空文字だと error、公開の層は error 0。

## 4. 確かめのコマンド(テストは hub だけ。絞って回す)
```
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter WasteTests --filter ProductionSystemTests --filter FurnaceHeatTests --filter DestructionTests --filter RFSaveTests --filter RFContentTests
~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter RFPresentTests
python3 tools/check-app-switches.py
python3 tools/check-app-names.py
python3 tools/check-no-reason-text.py
python3 tools/gen-xcstrings.py --check
python3 tools/check-public-spoilers.py
```
- 全体は回さない(統合担当が非公開の層を重ねて回す)。アプリのビルドは macOS の CI。

## 5. 触ってよいファイル / 触らないファイル
- 触ってよい: `ReForgeCore/Sources/RFContent/`(`ContentDB.swift`・`ContentLoader.swift`・`ContentValidator.swift`)、`ReForgeCore/Sources/RFProduction/`(`Modules.swift`・`ProductionSystem.swift` の `ProductionText`・新規 `Dumps.swift`)、`ReForgeCore/Sources/RFPresent/`(`Frame.swift` の `PlacementSprite`・`Panels.swift` の `BaseView`・`FrameBuilder.swift`・新規 `StopKind.swift`)、テスト(`RFProductionTests`・`RFContentTests`・`RFPresentTests`)、`ReForge/Sources/Game/Tabs/BaseTab.swift`・`ReForge/Resources/Localizable.xcstrings`(`gen-xcstrings.py` で)・`tools/check-no-reason-text.py`。
- 触らない: `RFMatter`(規則 `.byproduct(.slag)` は既にある)・`RFLogistics`(運搬)・`RFWorld` の保存の型(`ModuleRuntime`・`StructureRuntime` に項目を足さない)・`content/public/*.json`・`content/private`・`ReForgeCore/Tests/RFSaveTests/Fixtures`。

## 6. 約束
- 公開リポジトリに物語の語を書かない。品・建造物の ID は中立(`item.test.*`・`test.*`)。
- `ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない。整数だけで計算する。
- 押せない物をボタンにしない。確認のダイアログを足さない。止まった理由を文で出さない(印と色)。
- 保存の形を変えない。物語の本文を変えない。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(統合担当が非公開の層を重ねて回す)。
- 枝の名前・先頭のハッシュ・4 の結果(件数)・`Hauling` を変えずに 3 が通ったか・既存のテストで落ちたもの(あれば名前だけ)・2.6 のデータの側で統合担当が置く物の一覧(鍵と ID だけ)。
