# F. 実装担当への割り当て

段で区切らず、R4(結末)までの全システムを作る前提で、作業単位をシステムごとに切る。R1〜R4 は「どの順で中身を入れるか」(依存の順番)としてだけ使う。境界(型・切れ端・コマンド・出来事・コンテンツの定義)は R4 まで乗る形で先に置いてあるので、R2 以降で足すのは各切れ端・定義の中身。

## 1. 作業単位の表
「先に要るもの」が揃っていれば、その単位は今すぐ始められる。どの単位も骨組み(型・空のシステム・テストの置き場)は d50d08c に入っている。

| 単位 | 名前 | 持ちディレクトリ(`ReForgeCore/…`) | 書いてよい切れ端(B §1) | 先に要るもの | 最初の受け入れテスト(`swift test`) |
|---|---|---|---|---|---|
| U0 | 統合(設計担当) | `Package.swift`・`Sources/RFKernel`・`RFWorld/WorldState.swift`・`RFRules/{SimSystem,StepContext}.swift`・`RFSim`・`Tests/AcceptanceTests`・ブランチのマージ | `ids`・`ledger`・`inventory`・`knowledge` の共通操作 | — | 全ターゲットのビルド、決定性(同じ seed と操作 → 同じ世界と出来事)、昼の刻みによらない一致 |
| U1 | 地図(走行中) | `Sources/RFMap`・`Tests/RFMapTests` | `map`(生成) | — | 同じ seed で同じ地図 / 拠点・川・岩山・残骸の距離の範囲を 100 seed で保証 / 経路は通れないマスを通らない / 視界の半径(昼 8・夜 5・灯り +4) |
| U2 | 物質(レビュー対応中) | `Sources/RFMatter`・`Tests/RFMatterTests` | — | — | 既存(推理で届く・総当たりで届かない)+ 山の合わせ方の規則 |
| U3 | 認識とコンテンツ | `Sources/RFPerception`・`RFContent/{ContentLoader,ContentValidator}.swift`・`RFContent/Schema/Perception.swift`・`content/public`・`tools/content/`・CI の取り込み | — | — | 遡る書き換え(事実を知ると、作った物・置いた物・図鑑・ノートの出典・地図のラベル・過去の日誌が新しい名前に。保存データは同じ)/ 静的な監査が全段で 0 件 / 走行中の監査つき Perceiver / 非公開の層を重ねても公開だけでも検証エラー 0 |
| U4 | 時間と生存 | `Sources/RFTime`・`Sources/RFSurvival`・`RFWorld/Slices/{Clock,Survival}.swift` | `clock`・`survival`・人の `body` | U0 | 1 人 1 日 食料 1・水 1 の消費が昼のリアルタイムと寝るの一括で一致 / 食料切れ 5 日・水切れ 3 日で失敗の規則が成り立つ / 外で精神力が減りシェルターで戻る / 拠点全体の数値の内訳(基礎+上積み)と合計 |
| U5 | 人(ノアと仲間) | `Sources/RFCrew`・`RFWorld/Slices/People.swift` | `people`・`knowledge.mapKnown` | U1(経路・視界) | 歩く(1 秒 4 マス・経路どおり・行き先の変更)/ 視界で地図の既知が増える / 配属の実行(モジュールに付く・見張り)/ 上書きの間は配属に従わず範囲の中心へ歩く / 来歴の印 × 思想の重みで賛否が出て関係が動く |
| U6 | 発明 | `Sources/RFInvention`・`RFWorld/Slices/Invention.swift` | `invention`・`notebook` | U2 | 試作は手持ちの材料を実際に使い、所見と結果がノートに載る / 出典つきの書き留め / 仲間の関係ランクで出るヒント(HintDef)/ TEST-R1-01 推理ボット(鉱石 8 回分で精鉄板と剛鉄板、総当たり・無作為は 2 割以下) |
| U7 | 生産と物流 | `Sources/RFProduction`・`Sources/RFLogistics`・`RFWorld/Slices/{Placements,Logistics}.swift` | `placements`(モジュール)・`logistics`・`map` の鉱脈の残り | U1・U2・U5(運ぶ人) | 置ける場所の規則(鉱脈の上・水に接する)/ 隣接と向きでつながる / 1 回の処理が RuleBook の 1 工程 / 片付けると材料が全部戻る / 止まった理由 / TEST-R1-02 自動化ボット(3 日目にラインが手作業の最良日の 3 倍) |
| U8 | 探索と拠点 | `Sources/RFExploration`・`Sources/RFBase`・`RFWorld/Slices/{Exploration,Base}.swift` | `exploration`・`placements`(建造物)・`base`・`map` の地形の変化 | U1・U5 | 残骸を漁る(10 回まで・得られる物の表)/ 有限の部品の取り外し・解体・作り直しが来歴に残る / 建造物を建てる(仲間が手伝うと速い)/ 迎えられる人数はシェルターの数 / TEST-R1-04 道筋の複数性 |
| U9 | 脅威と戦闘 | `Sources/RFCombat`・`RFWorld/Slices/Combat.swift` | `combat` | U5・U8(灯り・柵) | 夜、灯りの外から食料を狙う / 範囲 repelEnemies の中に入らない / 1 次元の帯で自動に進み、方針と撤退だけ選べる / 武器の強さ = 素材の純度と硬さ / 勝ち負けが来歴に残る |
| U10 | 研究と力 | `Sources/RFResearch`・`Sources/RFAbilities`・`RFWorld/Slices/{Research,Abilities}.swift` | `research`・`abilities` | U5(研究机に付く) | 研究机に付いた仲間が昼に進める / 完了で解禁と効果 / スキルが道筋を増やす / 力は R1 で比べられる画面を作らない(テストで「ノアだけの数値」が Frame に無いことを見る) |
| U11 | 出来事 | `Sources/RFNarrative`・`RFRules/{Conditions,Effects,Auras}.swift`・`RFContent/Schema/{Condition,Effect}.swift`・`RFWorld/Slices/{Narrative,Auras}.swift` | `narrative`・`auras` | U0 | 未実装の効果を 0 に(担当のシステムへコマンドで渡す)/ 予約・クールダウン・優先度・追跡カウンタ(近くにいた時間・観測の夜)・目標の達成・章・結末 / 仲間の一言の選び方(LineDef の文脈と条件)/ TEST-S5 決定性(出来事の列) |
| U12 | 保存と失敗 | `Sources/RFSave`・`Sources/RFFailure`・`RFWorld/Slices/Run.swift` | `run` | U0 | 夜明けの自動セーブ(直近 3)・手動・続き / 版の移行 / 4 択(最初から・記憶を持って巻き戻す・失って続ける・セーブ地点から)/ TEST-R1-07(巻き戻しの持ち越しと仲間の「前にも」) |
| U13 | 画面 | `Sources/RFPresent`・`ReForge/`(アプリ)・`ReForgeTests/`・`project.yml` | — | U0(Frame)。中身は各単位に追従 | Frame の区画の版が変わった所だけ上がる / 補間の材料 / 工程表(ライン札・試作・記録)/ TEST-R1-09(シミュレータ)/ b7 の旧画面とターゲットを消す |
| U14 | 非公開コンテンツ | 非公開リポジトリ(E §4) | — | U3(形式) | 非公開の層を重ねて検証エラー 0・監査 0 / Era 1 の R1 の範囲が揃う |

## 2. 依存の順(R1-a〜e を参考に。全部を作る前提)
```
今すぐ並行:  U1 地図 ─┐   U2 物質 ─┐   U3 認識とコンテンツ   U4 時間と生存   U11 出来事   U12 保存と失敗   U13 画面(地図と歩く)
              ├─▶ U5 人 ─┬─▶ U7 生産と物流 ◀─ U2
              │          ├─▶ U8 探索と拠点 ─▶ U9 脅威と戦闘
              │          └─▶ U10 研究と力
              └──────────────────────────▶ U6 発明 ◀─ U2
```
R1 の段との対応(どの途中の版でも「マップの上で何かが動く」を崩さない):
- R1-a: U1・U4・U5(歩く・視界)・U13(地図・タップで歩く・ピンチ)・U11(目覚めの出来事が動く)
- R1-b: U2・U6・U7 の手作業
- R1-c: U7(配置・隣接・運搬)・U5(配属・賛否)
- R1-d: U8・U10
- R1-e: U9・U12(巻き戻し)・U11(章の区切り)

## 3. R2〜R4 の仕組みが乗る場所(境界は今のまま。中身を足す)
| 段 | 中身 | 乗る場所 |
|---|---|---|
| R2 | 地下の層 | `MapState.layers` に層を足す(U1)・`WorldPoint.layer` |
| R2 | 電力・溶融金属・自動行動プラン | `logistics.power`(U7)・`Assignment` の case(U5) |
| R2 | 季節・天候 | `survival.environment`・`StatDef`(暦は隠れた値)・認識の表 |
| R2 | 士気・不満・離脱・社交・キーパーソンの合流 | `PersonState`(U5)・`Presence`・`Effect.join/leave` |
| R2 | DesignLab(部品から機械を設計) | `ProcessSheet`・`invention`(U6) |
| R2 | 期限が研究で見える | `StatDisplay` の切り替え(認識の表)・`FailureRuleDef`(値で判定) |
| R3 | 拠点の外の集団との対立と和解 | `people.groups`・`Condition.group`(U5・U11) |
| R3 | 後半の場所・後半の敵とボス | 地図の層・POI・`InteractionDef`・`EnemyDef`(U1・U8・U9) |
| R3 | 特別な力の体系・後半の物質 | `RFAbilities`・`abilities`・RFMatter の物質の表・認識の表 |
| R3 | 有限の部品の修理・記録を工程表で開く | 有限の部品(`parts`)・`SheetDef`・`ProcessSheet` |
| R4 | 意味の反転・最後の場面に自分の記録を並べる | 来歴の問い合わせ(`ProvenanceQueries`)・`tagRecords`・認識の表 |
| R4 | 4 つのエンディング | `EndingDef`・`Effect.ending`・`run.outcome` |

## 4. 進め方の約束(全単位)
- A §3 の約束(持ちディレクトリの外を触らない・他の切れ端はコマンドか出来事で・共通操作は StepContext・自分の乱数の流れ・文章を作らない・定義の項目は省略可能)。
- 自分のテストターゲットで受け入れテストを先に書く。複数システムにまたがるボット走行は `Tests/AcceptanceTests` に置く(統合担当に知らせる)。
- テストのコンテンツは `content/public`(ネタバレの無い試験用)に足す。本物のコンテンツが要るテストは `XCTSkipUnless(TestContent.hasPrivateLayer)`。
- コミットの前に `docker run --rm -v "$PWD":/w -w /w swift:6.1-noble swift test --package-path ReForgeCore` が緑。
- 世界状態の形を変えたら D §4 の手順(版を上げて移行を 1 つ足す)。ただし最初のリリースまでは版 1 のまま形を変えてよい(セーブの互換は R1 のリリースから守る)。

## 5. 物語と工業の結合設計からの要求への対応
| 要求 | 境界での対応 |
|---|---|
| REQ-S6 来歴 | `ProvenanceLedger`(誰が・いつ・何を・どこで・何から・印・回数)。工業の初めての索引 `firsts`・条件 `firstTime`。有限の部品の状態(`parts`: 無傷・取り外し・解体・作り直し)。人の生死と死因(`Presence.dead(record:)`)と「誰の判断で」(記録の inputs が決断の来歴)。観測の夜・近くで働いた時間は追跡カウンタ(`TrackerDef`)。巻き戻しで残す部分と戻す部分は B §1 の表と `MemoryCarry` |
| REQ-S7 遡る認識の層 | `Perceiver`(真実の ID × 知っている事実)。名前を保存しないので、過去の記録・在庫・配置・図鑑・ノートの出典(`NoteEntry.source`)・地図のラベルも同じ層で描き直される。事実が変わると全区画を描き直す印(`ChangeSet.perception`)。開示の本体は効果で世界を変える側(層は支える側) |
| REQ-S8 工程表の再利用 | `ProcessSheet`(出所 = ライン札 / 試作 / コンテンツの記録 `SheetDef`)。設計画面と同じ部品で描く |
| REQ-S9 宣言的な引き金と効果 | `EventDef.trigger`(hook = 工業の出来事 + `Condition`: 世界の状態・前の出来事・カウンタ・来歴・初めて)。`Effect` は世界を変える(配属の上書き・範囲の付け外し・地形・合流と離脱・解禁・過去の記録への印)。場面だけの出来事は検証で警告 |
| REQ-S10 範囲の効果 | `AuraState`(中心 = 点・人・置いた物、半径、強さ、期限、来歴)+ `AuraDef.modifiers`(作業の速さ・配属に従わず中心へ・敵が寄らない・体や数値の時間あたりの増減)。出来事で半分(`scaleAura`)・消す(`removeAura`)。モジュール・建造物・人の定義に `auras` |
| REQ-S11 隠れた値 | `survival.stats` に内部の値(内訳と合計 `StatDef.sumOf`・暦)。見せ方は認識の表の `StatDisplay`(hidden → 段階 → 数)。人の総数は `unmet` で内部に。期限・失敗は `FailureRuleDef`(値の条件)で、日数で判定しない |
| MECH-07 決定的な乱数 | `RandomStreams`(seed + 流れの名前)。出来事の確率は `Condition.chance` が物語の流れで引く。テスト `testSameSeedSameCommandsSameWorld`・`AcceptanceTests.testDeterminismWithFullContent` |
| MECH-05 仲間の R1 の範囲 | `Assignment`(運搬・モジュールに付く・見張り・建造・採取)・`Activity`(歩く・運ぶ・話す・戦う)・`LineDef.context`(焚き火)・賛否(`IdeologyAxisDef.weights` × 来歴の印 → `DomainEvent.opinion`)。士気・離脱(R2)・特別な力と集団(R3)は同じ型に足す |
| REQ-S12 公開と非公開 | 仕組み(来歴・認識の層・条件と効果の評価・範囲)は公開のコード。事実の表・見え方の切り替え・本文・名簿・禁止語は非公開の層(E) |
