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
- 他の担当のブランチを取り込んだ後(enum の case が増えた後など)に、増分ビルドのテストが signal 11 で落ちることがある。`swift package clean --package-path ReForgeCore` してから回し直す(clean build で通れば、コードの問題ではない)。
- テストの置き場(リーダー。2026-10-02 オーナー許可): swift test は **note** で回すのが第一。`~/.local/bin/rf-note-test [-p 非公開の層] [-e KEY=VAL]... <リポジトリ> [swift test の引数]`(例 `rf-note-test -p content/private . --filter HearthTests`)。作業場を rsync で note に送り、swift:6.1-noble を `--cpus=6 -j 6` で回す。note は全員で同時 4 本まで(空きを待つ)。重いビルドとテストは全部 note で。docker に `--gpus` は付けない(note の GPU は画像生成が使う)。終了コードは swift test のもの。`.build` は作業場ごとに note に残る。**土台を替えた(統合を取り込んだ・別の枝に移った)ときは `rf-note-test -c …` で note の `.build` を消してから回す**(古い `.build` のままだと `ContentDB.init` などで signal 11 が出る)。1 人 1 本の決まりは無い(統合担当は公開と非公開の層を並べて回してよい)。
- 非公開の層の書き出し(統合担当が置く。読むだけ。中身を公開に出さない): `/home/ashwell/src/reforge-ios/.claude/private-layers/<名前>`。`main`(reforge-content の main = 古い形)と、U14 の枝ごと(`u21-hearth`・`u20-opening`・`prologue` = 新しい形)。`rf-note-test -p /home/ashwell/src/reforge-ios/.claude/private-layers/main . --filter …` のように使う。枝が進んだら統合担当が置き直す。
- hub の rf-swift-slot は予備(note が落ちているときなど)。hub での Swift のビルドとテストは**全員で同時に 3 本まで**。
  - docker は必ず `~/.local/bin/rf-swift-slot` を通す。`--cpus=3` と `swift … -j 3` を付ける。`--parallel` と `docker run -d` は使わない。枠が空くまで待つのが正しい動き(回避しない)。
  - 手元では変えた所に関わるテストだけを `--filter` で回す。全体は統合担当が統合のときに回す。
  - 重いテスト(多くの種のボット走行など)は、手元では環境変数で数を減らし、全部の数は CI で回す。20 分を超えるテストは止まっていないかを疑い、作りを直す。
- コミットの前に、関わるテストが緑: `~/.local/bin/rf-note-test -p content/private . --filter <自分のテスト>`(非公開の層が無ければ `-p` を外し「非公開未確認」)。予備は `~/.local/bin/rf-swift-slot docker run --rm --cpus=3 -v "$PWD":/w -w /w swift:6.1-noble swift test -j 3 --package-path ReForgeCore --filter <自分のテスト>`。
- 本体の公開の enum に case を足したら `python3 tools/check-app-switches.py` も、public な型を足したら `python3 tools/check-app-names.py`(アプリの型・本体の別モジュール・SwiftUI/Foundation の型との名前の重なり。93867cf の FileSaveStorage)も通す。アプリ(`ReForge/`)は Linux でコンパイルされないので、アプリの switch が網羅でなくなっても swift test では気づけない(b821798 で iOS のジョブが `SaveSlot.screen` で落ちた)。CI では `app-switches` のジョブが iOS の前に回る。統合担当はマージのたびに回す。
- 公開リポジトリに物語の語を書かない(コード・コメント・テスト・文書・コミットのメッセージ)。`python3 tools/check-public-spoilers.py`(ファイル)と `--commits origin/main..HEAD`(メッセージ)で確かめる。語の一覧は非公開の層の perception/forbidden.json から読み、当たった語は表示しない。CI の `app-switches` ジョブでも回る。統合担当はマージのたびと、リーダーに先頭を渡す前に回す。
- 効果から来るコマンド(U11 が各枝の末尾に `…FromEffect` などを足す。cause = 引き金の来歴で、自分の来歴の inputs に入れる)は持ち主が処理する: U5 = meet・join・leave・die・injure / U8 = revealMap・setTerrain・setPart / U9 = spawnEnemy / U7 = convertPlacements。処理を入れるまでは「どのシステムも受けないコマンド」の警告が出る。
- アプリの画面のファイルの持ち主(ぶつからないように 1 ファイル 1 担当): `Game/GameScreen.swift`(タブの並べ方)= 統合担当 / `Game/PrologueLayer.swift` = W-16 / `Game/Tabs/DesignTab.swift`・`NotesTab.swift` = U17 / `Game/Tabs/BaseTab.swift`・`CrewTab.swift`・`Game/GameOverView.swift`・`Game/TabBarView.swift` = U18 / `Theme/`・`Screens/TitleView.swift` = art-director / 地図・足元の札(`MapCanvasView`・`MapScene`・`FootCardView`・`StatusBandView`)= U13。他の担当のファイルを直すときは持ち主に知らせる。タブを足すときは統合担当に頼む(GameTab と PanelView に 1 行)。
- 保存される型に Data・Double・Date を持たせない(正準 JSON で読み戻せない。17f8133)。要るときは明示的に文字列か整数で書く。`AcceptanceTests/ResumeRoundTripTests` が見張る。
- 保存の見本は 2 種類。`Fixtures/save-v1-dev-<hash>.json` は dev ビルドで配った保存の形を凍らせたもので、**作り直さない・飛ばさない**(`testFrozenDevSavesStillRead` で読めなければ失敗。オーナーの端末の保存を守る)。新しい項目は decodeIfPresent と既定値か、版の移行(D §4)で受ける。作り直してよいのは最新の形を写す `save-v1.json` だけ(`REFORGE_UPDATE_SAVE_FIXTURES=1`、コミットに書く)。
- 世界状態の形を変えたら D §4 の手順(版を上げて移行を 1 つ足す)。dev ビルドで配った保存はすでに守る(上の凍らせた見本)。版の移行は統合担当がまとめて作る(W-10)ので、各単位は版を上げず decodeIfPresent と既定値で受ける。
- 多言語(日本語・英語・中国語の簡体字と繁体字・韓国語。オーナーの決め。設計は game-designer)に備え、これから足す文字列はすべてキーを通す:
  - アプリ: 画面の固定文言は `Text("…")`(リテラルが文字列カタログのキー)。固定文言を `Text(verbatim:)` や連結で組まない。数や名前の入る文は SwiftUI の補間をそのままキーにする(`Text("建造中 \\(p)%")` → `建造中 %lld%%`)。補間に入れてよいのは整数と、本体がその言語で組んだ名前だけ。名前を入れる行は行末に `// xcstrings: @`(複数なら順に `@,lld`)。カタログは各単位のコミットに入れず、統合担当が `python3 tools/gen-xcstrings.py` で作り直す(CI は `--check`)。
  - 本体: プレイヤーに見える文は、コンテンツの文言の ID(`text.*`・`reason.*` など)と引数で表し、`ReForgeCore/Sources` にプレイヤー向けの日本語のリテラルを書かない(開発者向けのエラー・検証の文は可)。
  - 保存: 表示の文字列を保存しない。ID と引数で持ち、読むときにその時の言語で組み立てる。
- 「マージ可」の条件(リーダー): 関わるテストを、公開の層と非公開の層の**両方**で回し終えていること。非公開の層を回せなかったとき(土台が古い・読めない・手元に無い)は「マージ可」ではなく「**非公開未確認**」と書いて送る。統合担当はマージの前に非公開の層を回す。Codex の作業場には非公開の層が無いので、Codex の分はいつも「非公開未確認」として扱う。
- 本体の型と非公開の層のデータが組で変わる単位(例: 火床の hearth、開示、人の自動化)の順番:
  1. 本体は、いまの非公開の層(古い形)を読んでも落ちない・振る舞いが変わらないように書く(例: 焚き火に hearth が無ければ今までどおりの固定の灯り)。統合担当はマージの前にこれを確かめ、非公開の層は**古い形と新しい形の両方**で全体を回す。
  2. U14 は統合を待たずに、その単位の枝の上で新しい形のデータを作る(reforge-content には push しない)。
  3. 本体を main に入れ、main の CI が緑になってから、リーダーが新しいデータを reforge-content の main に push する(main の CI は push した時点の reforge-content の main を取り込むため)。
- dev のリリースの固定 URL(`releases/download/dev/ReForge.ipa`。オーナーのショートカットが取る)を変えない。CI の release の名前・タグ(`dev`)・ファイル名(`ReForge.ipa`)を変える変更は、入れる前にリーダーに止める。
- ストアの原稿は `store/metadata/<地域>/`・`store/iap/<品>/<地域>.json`。書くのはリーダー。物語の語を書かない。`tools/check-store-metadata.py` を通す(出す版は `--release`)。

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
