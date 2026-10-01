# A. モジュール構成と依存の向き

## 1. 結論
ReForgeCore パッケージ(Linux の `swift test` で全部確かめられる純 Swift)を、**システムごとの SwiftPM ターゲット**に分ける。上の層は下の層だけを import する(コンパイラが依存の向きを守らせる)。システム(L4)どうしは互いに import しない。システムの連携は、世界状態(RFWorld)・コマンド・出来事(DomainEvent)を通す。

- 採用理由: 実装担当が別々の worktree で同時に作っても、触るディレクトリが重ならない。依存の向きが崩れる変更はビルドが通らないので、レビューに頼らず止まる。テストもターゲットごとに分かれ、担当は自分のテストだけを足す。
- 再検討条件: ターゲットが細かすぎてビルド時間・`public` の付け忘れが負担になったら、L4 のいくつかを 1 ターゲットにまとめる(依存の向きはそのまま)。

```
L0  RFKernel                 型付き ID・座標・乱数(流れ別)・数(Purity/Milli)・時間・事実の式・Value
L1  RFMap   RFMatter         葉: 地図(生成・視界・経路) / 物質(純度・形・命名の部品・工程の計算)
L2  RFWorld  RFContent       世界状態(値型)・コマンド・出来事 / コンテンツのスキーマ・読み込み・検証
L3  RFRules  RFPerception    システムの約束(SimSystem・StepContext)・条件と効果の評価・範囲の効果 / 認識の層・禁止語の監査
L4  RFTime RFSurvival RFInvention RFProduction RFLogistics RFCrew RFExploration
    RFBase RFCombat RFResearch RFAbilities RFNarrative        ← システム。互いに import しない
    RFSave RFFailure                                          ← 保存 / 失敗と 4 択と巻き戻し
L5  RFSim                    本体: 固定ステップ・コマンドの配り先・システムの順番・新しい世界
L6  RFPresent                画面向けの射影(Frame・区画・工程表)と GameHost(actor)
    ReForgeEngine            傘(全部を @_exported)。新しい UI は `import ReForgeEngine` だけ
    RFTestSupport            テストの道具(公開の試験用コンテンツ・平らな地図・TestRig)
```

依存の表(`ReForgeCore/Package.swift` が正本):

| ターゲット | import してよいもの |
|---|---|
| RFKernel | なし |
| RFMap / RFMatter | RFKernel |
| RFWorld | RFKernel・RFMap・RFMatter |
| RFContent | RFKernel・RFMap・RFMatter(RFWorld は見ない: コンテンツは世界の形に依存しない) |
| RFRules | L0〜L2 |
| RFPerception | RFKernel・RFMatter・RFWorld・RFContent |
| L4 のシステム | RFKernel・RFMap・RFMatter・RFWorld・RFContent・RFRules |
| RFSave | RFKernel・RFWorld |
| RFFailure | RFKernel・RFWorld・RFContent・RFRules・RFSave |
| RFSim | L0〜L4 全部 |
| RFPresent | RFSim・RFPerception と下 |

## 2. ディレクトリと持ち主
| ディレクトリ(`ReForgeCore/Sources/…`) | 持ち主(F の作業単位) | 中身 |
|---|---|---|
| `RFKernel/` | 統合担当 | 共有の小さな型。足すときは統合担当に連絡 |
| `RFMap/` | U1 地図 | 生成・バイオーム・POI・鉱脈・視界・経路。`Boundary.swift` は骨組み(担当の型が正) |
| `RFMatter/` | U2 物質(完了) | Matter・命名の部品・RuleBook・ProcessChain・Recipe |
| `RFWorld/WorldState.swift` | 統合担当 | 切れ端の並び。**項目の追加・削除は統合担当だけ** |
| `RFWorld/Slices/<名前>.swift` | その切れ端の持ち主(B §1 の表) | 切れ端の中身。持ち主が自由に足す |
| `RFWorld/Commands/Command.swift` | 枝ごとに持ち主(`TimeCommand` は U4…) | 枝の enum の case は持ち主が足す |
| `RFWorld/Events/DomainEvent.swift` | 統合担当(case の追加は誰でも。hook も同時に足す) | 出来事 |
| `RFContent/Schema/*.swift` | 定義ごとに持ち主(E §2 の表) | 定義の項目は省略可能にして足す |
| `RFContent/ContentLoader.swift`・`ContentValidator.swift` | U3 認識とコンテンツ | 層の重ね方・検証の規則 |
| `RFRules/` | U11 出来事(条件・効果・範囲) / 統合担当(SimSystem・StepContext) | |
| `RFPerception/` | U3 | |
| `RF<システム>/` | 各システムの担当 | `<名前>System.swift` から始める。ファイルは自由に増やす |
| `RFSave/`・`RFFailure/` | U12 保存と失敗 | |
| `RFSim/` | 統合担当 | システムの順番を変えるときは F §3 の順番の表も直す |
| `RFPresent/` | U13 画面 | |
| `Tests/<ターゲット>Tests/` | そのターゲットの持ち主 | |
| `Tests/AcceptanceTests/` | 統合担当(各担当が受け入れテストを足す) | TEST-R1-xx のボット走行 |
| `content/public/` | U3(仕組みのテストに要る分だけ各担当が足す) | ネタバレの無い試験用コンテンツ |

## 3. 並行実装で衝突しない約束
1. 自分の持ちディレクトリとテストの外は触らない。触る必要が出たら(他人の切れ端に項目が要る等)、持ち主かリーダーに頼む。`WorldState.swift`・`Package.swift`・`Simulation.swift` は統合担当だけが触る。
2. 他のシステムの状態を変えたいときは、自分で書き換えずに `ctx.queue(コマンド)` か `ctx.emit(出来事)`。読むのは自由。
3. 共通の操作(来歴を残す・事実を知る・在庫の出し入れ・乱数)は `StepContext` のものだけを使う。
4. 乱数は自分の流れ(`RandomStreamID.<自分>`)だけ。流れを分けてあるので、自分が引く回数を変えても他の担当のテストの期待値は変わらない。
5. 文章を作らない。名前・文はすべて `RFPerception` が ID から引く(英語の ID を画面に出さない検査がある)。
6. 定義(`RFContent/Schema`)の項目を足すときは省略可能(`?`)にする。既存のコンテンツと試験用コンテンツが読めなくならないように。

## 4. 葉の 2 人の型との合わせ方
- **物質(RFMatter)**: 担当の型を正とした。担当の `Purity`(万分率)を RFKernel に移し、`ItemID`・`RecipeID`・`ModuleKind`・`FindingID` を RFKernel の型付き ID(`TypedID`)の別名にした(`rawValue` / `init(rawValue:)` / 文字列リテラルの使い方はそのまま)。定数(`.ironOre`・`.minehead` …)は `extension TypedID where Tag == …` に移した。担当のテストは `import RFKernel` を 1 行足しただけで全部通る。在庫・ライン札・試作・ノートは担当の `Matter`・`ProcessStep`・`ChainResult`・`MatterName` をそのまま持つ。
- **地図(RFMap)**: 担当の型がまだ無いので `RFMap/Boundary.swift` に他の層が当てにする最小の形(`MapState`・`MapLayer`・`DepositState`・`POIState`・`TerrainDef`・`MapGenConfig`・生成/経路/視界の protocol)を置いた。担当の型が来たら、担当の型を正としてこのファイルを消し、`WorldState.map` と `FrameBuilder.tile` と `WorldFactory` の呼び出しを合わせる(統合担当)。

## 5. 旧版(b7)の扱い
- b7 の `ReForgeCore`・`ReForgeContent` ターゲットとテスト(T08 を含む)、製品 `ReForgeCore` は、U13 の新しい画面に切り替えたときに消した(統合 8020db2)。アプリは製品 `ReForgeEngine` だけを使う。
- b7 の T08 は禁止語の語そのものを公開リポジトリに書いていた。消したのは今の版からだけで、過去のコミットの履歴には残る。新しい仕組みでは禁止語は非公開の層に置く(E §5)。
