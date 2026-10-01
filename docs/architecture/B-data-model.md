# B. データモデル — 世界状態(WorldState)

正本のコード: `ReForgeCore/Sources/RFWorld/`。ここは形と約束の説明。

## 1. 全体と持ち主
`WorldState` は値型(struct)・`Codable`・`Equatable`・`Sendable`。**名前・文章は持たない**(真実の ID と数だけ)。**浮動小数を持たない**(`Purity` 万分率・`Milli` 千分率・`GameTime` 整数秒)。同じ seed と同じコマンド列から、同じ WorldState と同じ出来事の列になる。

| 切れ端 | 型 | 持ち主(書く) | 巻き戻しで |
|---|---|---|---|
| `rng` | `RandomStreams`(seed + 流れ別の状態) | 各システム(自分の流れだけ) | 戻す |
| `ids` | `IDAllocator` | 共通 | **続きから**(番号を重ねない) |
| `clock` | `ClockState`(now・day・phase・dayStartedAt・realCarry) | RFTime | 戻す |
| `map` | `MapState`(層 → `MapLayer`) | 地形の変化・鉱脈の残り: RFExploration / RFProduction | 戻す |
| `people` | `PeopleState`(人 → `PersonState`) | RFCrew | 位置・生死・体は戻す。**関係と、またぐ記憶は残す** |
| `placements` | `PlacementsState`(実体 → `Placement`) | モジュール: RFProduction、建造物: RFBase | 戻す |
| `inventory` | `InventoryState`(在り処 → 山の並び) | 共通(`StepContext` の在庫操作) | 戻す |
| `invention` | ライン札(`LineDesign`) | RFInvention | 戻す |
| `notebook` | 試作の記録・出典つきの書き留め・図鑑・聞いたヒント | RFInvention | **残す** |
| `logistics` | 運搬の経路・流量(電力は R2) | RFLogistics | 戻す |
| `knowledge` | 知っている事実・地図の既知・発見・見たもの | 共通(`StepContext.learn`)・地図の既知は RFCrew | **残す**(事実はコンテンツの scope = memory のもの) |
| `ledger` | `ProvenanceLedger`(来歴) | 共通(`StepContext.record`) | 戻す(覚えておく印の記録は `run.pastLives` に写す)。番号は続きから |
| `survival` | 拠点全体の数値(隠れた値を含む)・飢えと渇きの日数・天候と季節 | RFSurvival | 戻す |
| `exploration` | POI の進み・有限の部品の状態・行為の回数 | RFExploration | 戻す |
| `base` | 拠点グレード・範囲 | RFBase | 戻す |
| `combat` | 地図上の脅威・進行中の戦闘 | RFCombat | 戻す |
| `research` | 研究の進み・完了・解禁の集合 | RFResearch(解禁は効果からも) | 戻す |
| `auras` | 範囲の効果 | 共通(効果と定義から) | 戻す |
| `abilities` | 特別な力の熟達 | RFAbilities | 戻す(R3 で再検討) |
| `narrative` | 発火済み・決断待ち・予約・カウンタ・目標・章・場面・結末 | RFNarrative | 戻す |
| `run` | 周回の番号・結果・前の周回の記録 | RFFailure | 増やす |

切れ端を足す・消すのは統合担当だけ(`WorldState.swift`)。切れ端の中身は持ち主が足してよい(省略可能な項目にする必要はない。保存の版は D の手順で上げる)。

## 2. ID の約束
- 真実の ID は文字列の型付き ID(`TypedID<Tag>`。`FactID`・`ItemID`・`ModuleKindID`・`PersonID`…、`RFKernel/IDs.swift`)。取り違えを型で防ぐ。JSON では文字列、辞書のキーにしてもオブジェクトになる。
- 物の ID は原作の `item_id` と同じ綴り(`"iron_ore"`・`"wood"`)。モジュールの ID は RFMatter の工程の種類と同じ(`"minehead"`・`"furnace"`)。事実・出来事などは名前空間つき(`"fact.…"`・`"event.…"`)。
- ゲーム中に生まれる実体(置いた物・地図上の敵・唯一品・決断・範囲)は `EntityID`(世界ごとの連番)。
- 来歴の記録は `ProvenanceID`(連番)。

## 3. 地図(層を足せる)
- `MapState.layers: [LayerID: MapLayer]`。最初は `layer.surface` だけ。地下は層を足す(R2)。座標は層の中の `GridPoint`、層を含む位置は `WorldPoint`。
- `MapLayer`: 大きさ・地形(パレットの添字の配列)・鉱脈(`DepositState`: 位置・鉱石の種類・純度・残り回数)・POI(`POIState`: 種類・位置・占めるマス)。
- 地図の既知は `knowledge.mapKnown[層]`(ビット列)。見えている範囲は毎ステップ計算する(保存しない)。
- 形の細部は地図の担当が決める(`RFMap/Boundary.swift` は骨組み)。

## 4. 人(ノアと仲間)— マップ上の実体
`PersonState`:
- `presence`: まだ会っていない / 会った / 一員 / 不在 / 死んだ(来歴で死因を指す。戻らない)。総数は内部にだけある(見せない)。
- `position`(`WorldPoint`)・`facing`・`motion`(経路と次のマスへの進み 0〜1000。画面の補間にも使う)。
- `assignment`(プレイヤーが決めた役割: 運搬・モジュールに付く・見張り・建造・採取・ついて行く・休む)と `activity`(いま実際にしていること)。
- `override`(出来事や範囲の効果が配属を上書きしているとき。範囲が消えれば上書きも消える)。
- `body`(体力・スタミナ・満腹・水分・精神力・状態)・`relation`(ノアとの関係の点とランク)・`ideology`(思想の軸 → 値)・`memories`(`MemoryRecord`: 種類・いつ・どの周回・**何について(来歴)**・巻き戻しをまたぐか)・`skills`・`equipment`。
- ノアも同じ型(`PersonID.noah`)。ノアだけが特別だと比べられる値は持たせない(全員が同じ体の規則)。

## 5. 在庫(純度・形・来歴を持つ物)
- 在り処(`HolderID`): 拠点の蓄え(`base`)・人の持ち物(`person:<id>`)・置いた物の中(`placement:<n>`)。モジュールの入出力の待ちは `ModuleRuntime.input/output`。
- 山(`StockEntry`): 中身(`Stuff` = `.item(ItemID)` か `.matter(Matter)`)・数・**来歴(来歴 → 数。上限 16、あふれは「不明」へ)**・唯一品の実体 ID・減ったら戻らない品の残り。
- 純度・形・熱・硬さは RFMatter の `Matter` が持つ。名前は持たない(`NameGenerator` が名前の部品を返し、認識の層が文字にする)。
- 同じ中身の山は合わせる(唯一品は合わせない)。純度の違う物を平均して合わせるかは物質の担当が決める(`StepContext.addStock` を直す)。

## 6. 来歴(MECH-01 / REQ-S6)
`ProvenanceRecord`: 誰が(`actor`)・いつ(`at`・`day`・`run`)・何を(`act: ActKind`・`subject: SubjectRef`)・どこで(`place`)・何から(`inputs`: 材料や引き金の来歴)・印(`tags`)・まとめた回数(`count`)・詳細(`detail`)。
- 追記のみ。後から変えてよいのは `tags`(後で意味が付く: 効果 `tagRecords`)と `count` だけ。
- 「工業の初めて」の索引(`firsts`: 行為 × 対象の種類 → 最初の記録)。条件 `firstTime` が使う。
- 来歴の木を下る `descendants(of:)`(あのとき作った鉄から作られた物すべて)。
- ラインの生産は 1 個ずつ残さない。置いたモジュールの記録の `count` を増やす。
- 物の山・置いた物・ライン札・試作・事実・仲間の記憶・決断・範囲の効果・前の周回の記録は、すべて来歴の ID を持つ。後の開示は「この ID の行為」を指して世界を変える。
- 有限の部品(残骸の区画など)は `exploration.poi[id].parts[名前]`(無傷 / 取り外した / 解体した / 作り直した。それぞれ来歴つき)。
- 数で数える来歴(観測した夜の数・ある仲間がノアの近くで働いた時間)は追跡カウンタ(`TrackerDef` → `narrative.counters`)。

## 7. 知っている事実(認識の層の入力)
- `knowledge.facts: [FactID: FactRecord]`(いつ・どの周回・何で知ったか)。Era は事実の 1 つとして扱う(Era 単位でなく事実単位で切り替わる)。
- 事実の定義(コンテンツ `FactDef`): `scope`(memory = 巻き戻しても残る / timeline = その時間軸だけ)・`implies`(知ると同時に知る事実)。
- 事実を知るのは `StepContext.learn` だけ(来歴を残し、`factLearned` を出し、見え方を引き直す印を付ける)。

## 8. 時計と乱数
- `clock.now` はゲーム開始からのゲーム秒。1 日 = 昼 + 夜(長さはコンテンツの `clock`)。`phase`: 昼(リアルタイム)/ 日没(止まる)/ 夜作業(行為ごとに進む)。
- `clock.realCarry`: 実時間の端数の繰り越し(整数。C §3)。
- `rng`: seed と流れの名前(`RandomStreamID`)から各流れの初期状態が決まる(FNV-1a + SplitMix64。Swift の `hashValue` は使わない)。システムは自分の流れだけを使う。出来事の確率も物語の流れ(MECH-07)。

## 9. 出来事・決断・範囲の効果・隠れた値
- 出来事の進み(`narrative`): 発火の記録(回数・最後の来歴)・決断待ち(`PendingDecision`: 選べた選択肢・止めるか・来歴)・予約・カウンタ・目標・章・場面・結末。
- 範囲の効果(`auras.active`: 種類・中心(点/人/置いた物)・半径・強さ(千分率。半分にできる)・来歴・期限)。中身(何がどう変わるか)はコンテンツの `AuraDef`。各システムは `Auras.modifiers(at:)` で読む(REQ-S10)。
- 隠れた値(REQ-S11): `survival.stats` に内部の値として持つ(内訳を別の数値に分け、合計を `StatDef.sumOf` で持つ・季節の暦など)。見せ方は認識の表の `StatDisplay`(hidden → 段階の言葉 → 数)で、開示の事実で切り替わる。人の総数は `people` に `unmet` として内部にある。
- 期限・失敗は日数でなく値で判定する(`FailureRuleDef.when` に条件を書く)。

## 10. 決めていないこと(担当が決める)
- 地図の生成の細部(U1)・物質の山の合わせ方(U2)・体の数値の規則(U4)・関係の点の式(U5)・モジュールの処理の細部(U7)。どれも切れ端の中身なので、担当が自分の切れ端の中で決めてよい。
