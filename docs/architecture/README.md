# Re:Forge iPhone 版 — 境界の設計(architecture)

この下の文書は、実装担当がシステムごとに並行して作るための「境界」を決める。公開リポジトリに置くので、物語の中身(事実の名前・品名・台詞・出来事の本文)は書かない。事実や出来事は抽象 ID(`fact.x` など)でだけ指す。

| 文書 | 中身 |
|---|---|
| [A-modules.md](A-modules.md) | ReForgeCore のターゲット分割と依存の向き。誰がどのディレクトリを持つか |
| [B-data-model.md](B-data-model.md) | 世界状態(WorldState)の全体像。地図・人・配置・在庫・来歴・知っている事実・時計・乱数 |
| [C-engine-ui.md](C-engine-ui.md) | 本体と画面の境界。コマンド → 固定ステップ → 結果と出来事。リアルタイムの昼・夜の一括・一時停止・60fps の描画 |
| [D-save.md](D-save.md) | 保存の形式・版と移行・セーブ地点・記憶を持って巻き戻す |
| [E-content.md](E-content.md) | コンテンツの形式・公開と非公開の分け方・CI での取り込み・禁止語の検査 |
| [F-work-units.md](F-work-units.md) | 実装担当への割り当て・依存順・受け入れテスト |

## 前提(変えない)
- Swift / SwiftUI ネイティブ。完全オフライン。アプリを閉じている間は進まない。
- 時間は混合型: 短い昼はリアルタイム、長い夜は夜作業か「寝る」で飛ばす。
- ゲームオーバーで 4 択: はじめから / 記憶を持って巻き戻す / 失って続ける / セーブ地点からロード。
- 主人公はノア固定。4 レンズ(クリッカー・サンドボックス・ストーリー・緊張)。主画面はマップ。決断が要るとき以外は止めない。
- 物語はプレイヤーが遊びの中で体験するもの(起きる出来事・自分の行動の結果・仲間が実際に動いて変わる・世界の状態が変わる)。会話や日誌は「資料」。
- コードは公開、物語とイベントの本文は非公開のコンテンツリポジトリ(ビルドのときに取り込む)。

## 物語を支える 5 つの仕組みがどこにあるか
| 仕組み | 置き場所 | 文書 |
|---|---|---|
| 認識の層(真実の ID × 知っている事実 → 見え方。遡って書き換わる。禁止語の機械チェック) | `RFPerception`・`RFContent/Schema/Perception.swift`・`WorldState.knowledge` | B §5・E §5 |
| 来歴(作った・置いた・選んだ・倒した・失った・初めて、を構造化データで) | `WorldState.ledger`(`RFWorld/Slices/Provenance.swift`)・`StepContext.record` | B §6 |
| 出来事は行動と世界の状態が引き金・効果は世界を変える | `RFContent/Schema/{Condition,Effect,Defs}.swift`・`RFRules`・`RFNarrative` | B §9・E §2 |
| 仲間はマップ上の実体(位置・歩く・運ぶ・付く・戦う・関係・思想・記憶) | `WorldState.people`(`RFWorld/Slices/People.swift`)・`RFCrew` | B §4 |
| コンテンツとコードの分離(公開版だけでビルドとテストが通る) | `content/public`・`content/private`(gitignore)・`RFContent.ContentLoader` | E §3〜4 |

結合設計(物語と工業)からの要求 REQ-S6〜S12 への対応は [F-work-units.md §5](F-work-units.md#5-物語と工業の結合設計からの要求への対応) にまとめた。
