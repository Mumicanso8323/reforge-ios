# E. コンテンツの形式・公開と非公開・取り込み・禁止語の検査

正本のコード: `RFContent/`(スキーマ・読み込み・検証)・`RFPerception/ForbiddenAudit.swift`。

## 1. 考え方
- コードは公開(この reforge-ios)。物語・出来事の本文・後半の品名・事実の表・認識の切り替え・禁止語・名簿は**非公開のコンテンツリポジトリ**に置き、ビルドのときに取り込む(オーナー決定)。
- アプリはコンテンツの束(ディレクトリ + JSON)を読む。公開の層だけでもビルドとテストが通る(公開の層 = ネタバレの無い試験用の最小の集まり)。
- 定義の中に名前や文を書かない。名前は認識の表(見出し → 見え方)、文は文字列表(TextID → 本文)にだけ書く。だから本文を差し替えても定義は変わらず、検査は文字列表と認識の表を見れば足りる。

## 2. スキーマ(集まり)
1 つの JSON ファイルは、次の集まりのどれかを持つオブジェクト(どのファイルに何を書いてもよい。`"//"` は注記)。各集まりは ID を持つ定義の配列。定義の形は `RFContent/Schema/Defs.swift`・`Perception.swift`・`Condition.swift`・`Effect.swift`。

| 集まり | 定義 | 持ち主 |
|---|---|---|
| `bundle` | 層の名札(id・公開/非公開・版) | U3 |
| `clock` | 昼の実秒・昼と夜のゲーム時間 | U4 |
| `mapGen`・`terrains`・`biomes`・`pois` | 地図の生成の設定・地形の性質・バイオーム・POI(有限の部品の名前を含む) | U1 |
| `ruleBook` | 発明の規則の表(RFMatter。無ければ R1 の表) | U2 |
| `modules`・`structures` | 置くモジュール(費用・置ける場所・入出口・処理の時間・専門・範囲の効果)・建造物(費用・建てる時間・提供するもの・範囲の効果) | U7・U8 |
| `handwork` | 手作業(工程 1 つを手で。押す回数) | U7 |
| `interactions` | マス・POI・置いた物に対する行為(時間・押し続けるか・条件・昼夜・回数・得られる物・効果・来歴の印) | U8 |
| `people`・`ideologyAxes`・`memoryKinds`・`lines`・`hints` | 人(名前の見出し・専門・思想・範囲)・思想の軸(来歴の印 → 賛否の重み)・記憶の種類・一言(文脈と条件)・ヒント(出典つき) | U5・U6 |
| `research`・`skills`・`abilities` | 研究(点・前提・机・解禁・効果)・スキル・力 | U10 |
| `enemies` | 敵 | U9 |
| `auras` | 範囲の効果の中身 | U11 |
| `stats`・`failureRules`・`trackers` | 拠点全体の数値(内訳と合計・隠れた値)・失敗の規則(値で)・追跡カウンタ | U4・U12・U11 |
| `facts`・`events`・`scenes`・`sheets`・`objectives`・`chapters`・`endings`・`findings` | 事実(scope・含意)・出来事(引き金・効果・選択肢・止めるか・印)・場面(3 行まで)・工程表の記録・目標・章・結末・所見の文 | U11・U6 |
| `start`・`rewind` | 始まりの世界・巻き戻しと失って続けるの規則 | U12 |
| `perception`・`forbidden`・`auditStages`・`textGates`・`glyphs`・`texts` | 認識の表・禁止語の規則・監査の段・文字列の門・地図の文字・文字列表 | U3 |
| `remove` | 前の層の定義を消す(集まりの名前 → ID の並び) | — |

条件と効果は Swift の列挙の既定の JSON の形で書く(case 名がキー、ラベルが中のキー。値の無い case は `{"always": {}}`)。
```json
{"all": {"of": [ {"known": {"expr": "fact.x"}},
                 {"ledger": {"query": {"act": "placed", "module": "furnace"}, "atLeast": 1}} ]}}
{"addAura": {"kind": "aura.x", "at": {"person": {"id": "person.y"}}, "radius": 5, "hours": null}}
```
`FactExpr`(認識の表・禁止語の until)だけは短く書ける: `"fact.x"` / `{"all": [...]}` / `{"not": ...}` / `true`。

## 3. 層の重ね方
- 層 = ディレクトリ 1 つ。中の `*.json` を相対パスの昇順に全部読む(**層の中に JSON をコンテンツ以外の用途で置かない**)。
- 重ねる順: 公開(`content/public`)→ 非公開。同じ ID の定義は後の層が丸ごと置き換える。`clock`・`mapGen`・`start`・`rewind`・`ruleBook` は後の層が勝つ。`texts`・`glyphs` はキーごとに上書き。`forbidden` は足し合わせ。`remove` で前の層の定義を消せる。
- 知らない最上位のキーはエラー(誤記を黙って読み飛ばさない)。読み込み後に `ContentValidator.validate`(エラーは出荷しない。警告は理由を書いて残せる)。

## 4. 公開と非公開の分け方・取り込み
### 4.1 分け方
| 公開(reforge-ios の `content/public`) | 非公開(コンテンツリポジトリ) |
|---|---|
| 仕組みのテストに要る最小の集まり。試験用の ID(`fact.test.*` など)と、ネタバレの無い一般語(草地・薪・炉など)だけ | 事実の表(Era を含む)・出来事・場面・一言・ヒント・工程表の記録・名簿・品名の切り替え・後半の品名・禁止語の本物・監査の段・本文の全部 |
| アプリが起動して地図を歩ける程度の地形・モジュールの性質 | 原作から写した数値の表で、名前が後半のネタバレになるもの |

迷ったら非公開に置く。公開の層の文字列も、非公開の禁止語の規則で毎回検査する(4.3)。

### 4.2 非公開リポジトリの構成(既定値)
- 名前: `Mumicanso8323/reforge-content`(private)。
- リポジトリの根 = 層の根。CI と手元では `content/private/` に置く(reforge-ios の `.gitignore` 済み)。
```
reforge-content/
  bundle.json              {"bundle": {"id": "private", "visibility": "private", "version": "<CI が書く>"}}
  world/                   terrains・biomes・pois・mapGen・modules・structures・interactions・handwork
  matter/                  ruleBook の上書き・findings
  people/                  people・ideologyAxes・memoryKinds・lines・hints
  narrative/               facts・events・scenes・sheets・objectives・chapters・endings・trackers・failureRules・stats・auras・start・rewind
  research/                research・skills・abilities
  combat/                  enemies
  perception/              perception・forbidden・auditStages・textGates・glyphs
  text/ja/                 texts(画面ごと・場面ごとに分けてよい)
  materials/               資料(原作の長い本文・設計の写し)。*.md だけ置く(JSON を置かない: 読み込まれてしまう)
  tools/                   原作の JSON からの変換スクリプト(*.py。出力先は上の各ディレクトリ)
```
### 4.3 CI での取り込み(既定値)
- secret の名前: **`REFORGE_CONTENT_TOKEN`**(非公開リポジトリの contents を読むだけの fine-grained PAT)。
- `core` ジョブ: (1) 公開の層だけで `swift test`(公開版だけで通ることを毎回確かめる)→ (2) secret があれば `actions/checkout` で `Mumicanso8323/reforge-content` を `content/private` に取り込み、もう一度 `swift test`(非公開の層を重ねた検証・監査・受け入れテスト)。
- secret はジョブの環境変数 `HAS_CONTENT_TOKEN` で有無を見る(`if:` に secrets を直接書けないため)。`core` ジョブの (1)(2) は `ci.yml` に入れてある。
- **公開リポジトリの Actions のログとアーティファクトは誰でも読める。** 非公開の層を重ねたテストは出力をファイルに伏せ、失敗したテストの名前(公開のコード)だけを出す。ログをアーティファクトに上げない。テストの失敗の文面に本文を入れない(`XCTAssertEqual(文字列, …)` で本文を比べるテストは非公開の層では書かない。件数や ID で比べる)。
- `ios` ジョブ(U13 でアプリがコンテンツの束を読むようになってから): secret があれば非公開の層を取り込み、**封をした束(4.5)にしてから** ipa に入れる。平文の非公開の層は ipa にもアーティファクトにも入れない。ipa はこれまでどおり公開の `dev` リリースに上げる(オーナーの更新ショートカットは変えない)。
### 4.4 手元での開発(非公開リポジトリが無い間も)
- `content/private/` にディレクトリを置けば、テストもアプリも自動で重ねる(gitignore 済み)。
- 別の場所に置くなら環境変数 `REFORGE_PRIVATE_CONTENT=/path/to/dir`(`ContentLoader.privateLayerEnv`)。docker では `-e REFORGE_PRIVATE_CONTENT=/w/…` か、`content/private` へのコピー。
- 非公開リポジトリができたら、`git clone … content/private` するだけ。

### 4.5 ipa の中の物語の本文の封(暗号化)
公開の `dev` リリースの ipa は誰でも落とせる。本文を平文で入れると、ipa を展開するだけで読めてしまう。そこで非公開の層は、CI がビルドごとに作る使い捨ての鍵で暗号化して入れ、鍵はアプリ本体のバイナリにだけ埋め込む(リーダー決定。オーナーに確認中)。

**守れるもの・守れないもの(オーナーに伝えておくこと)**
- 守れる: ipa を展開しただけ・ファイルを grep しただけで本文が読める状態。検索エンジンや一覧サイトに本文の断片が拾われること。
- 守れない: アプリのバイナリを解析して鍵を取り出す人。鍵は同じ ipa の中にあるので、これは「見えにくくする」までで、秘密の保護ではない。公開リポジトリの CI の手順(この文書と `tools/content/`)も公開なので、方式は知られている前提。

**封をした束の形式(`content/private.sealed`。ファイル 1 つ)**
| 位置 | 長さ | 中身 |
|---|---|---|
| 0 | 8 | 合図 `RFSEAL01`(ASCII) |
| 8 | 12 | nonce(ビルドごとに乱数) |
| 20 | n | 暗号文(AES-256-GCM。追加認証データ = 合図の 8 バイト) |
| 20+n | 16 | 認証タグ |

- 平文 = 非公開の層の全 JSON を 1 つにまとめた「束」(JSON。`{"format": "reforge.pack", "version": 1, "files": {"<層の中の相対パス>": "<ファイルの中身の文字列>", …}}`、キーは昇順)。`materials/`・`tools/` と JSON 以外のファイルは入れない。
- 束を読むのは RFContent(U3): `ContentLoader` の層の出所に「ディレクトリ」と並べて「メモリ上の束(相対パス → Data)」を足す。読み方(相対パスの昇順・upsert・remove・知らないキーはエラー)はディレクトリと同じ。
- 暗号は RFContent に入れない(ReForgeCore は外部パッケージに依存せず、Linux の `swift test` に CryptoKit が無いため)。開封はアプリ側(CryptoKit の `AES.GCM`)で、開いた束を RFContent に渡す。
- 封をするのは CI の macOS ランナー上のスクリプト `tools/content/seal.swift`(CryptoKit。U3 が作る)。Linux で同じことをする必要は無い。

**鍵の作り方と埋め込み方**
1. `ios` ジョブで、ビルドの直前に 32 バイトの乱数の鍵を作る(`openssl rand 32`)。鍵はファイルにもログにも出さない(`::add-mask::` を付け、シェル変数だけで受け渡す)。
2. `seal.swift` が鍵で束を封じ、`content/private.sealed` を書く。平文の `content/private/` はアプリに入れない(project.yml のフォルダ参照は `content/public` と `content/private.sealed` だけにする)。
3. 鍵を Swift のソースに生成する: `ReForge/Generated/SealKey.swift`(gitignore)。鍵をそのまま書かず、別の乱数 32 バイトとの XOR の 2 つの配列に分けて書く(バイナリの文字列検索で 32 バイトの連続が見えないように)。
4. 公開の層だけのビルド(secret が無い・手元)では、鍵の無い `SealKey.swift`(`nil`)を生成し、封をした束も入れない。アプリは公開の層だけで動く。
5. 鍵はビルドごとに変わる。保存データは ID だけなので、鍵が変わっても保存は読める(D §1)。

**読み込み(アプリ)**
- 起動時: `content/private.sealed` があり、鍵があれば開封 → 束を RFContent の層として公開の層の上に重ねる。開封に失敗(タグの不一致・壊れたファイル)したら、公開の層だけで起動し、画面の帯に 1 行出す(落とさない)。
- 開いた本文はメモリにだけ置く(キャッシュをファイルに書かない)。

**テスト**
- Linux(`swift test`、U3): 束の形式の読み書き(相対パスの順・知らないキー・壊れた束はエラー)と、ディレクトリから読んだ層と同じ束から読んだ層が同じ `ContentDB` になること。
- シミュレータ(アプリのテスト、U3 と U13): 封じて開くと同じ束になる / 1 バイト変えるとタグで弾かれる / 鍵が無いときは公開の層だけで起動する。
- CI の検査(`ios` ジョブ、ipa を作った後): ipa の中に `content/private/` の平文が無いこと。非公開の `bundle.json` に置く見張りの文字列(`"canary"`。本文ではない無意味な文字列)が、展開した ipa のどのファイルにも平文で現れないこと(`grep -r` で 0 件)。失敗したら ipa を上げない。ログには見張りの文字列そのものを出さない。

## 5. 認識の表と禁止語の検査
### 5.1 認識の表
- 見出し(`SubjectID`)は「名前空間:ID」(`item:iron_ore`・`module:furnace`・`person:<id>`・`stat:<id>`・`sheet:<id>`・名前の部品 `substance:Fe`・`shape:plate`・`grade:fine.metal`・`temper:hard`…)。作るときは `Subject.*` の関数を使う。
- 見え方(`Variant`)を上から調べ、`when`(`FactExpr`: 知っている事実の式)が最初に成り立ったものを使う。最後は `when: true`(既定)。項目: 名前・説明・数値の見せ方(hidden / 段階の言葉 / 数)・地図の文字・切り替わったら知らせるか。
- 事実単位で切り替わる(Era は事実の 1 つ)。名前は保存しないので、切り替わった瞬間に、既に作った物・置いた物・図鑑・地図・ノートの出典・過去の日誌の名前がすべて書き換わる。
- 英語の ID を画面に出さない: 見え方が無い見出し・表に無いキーは `text.unknown`(「？」)になる。

### 5.2 禁止語の機械チェック(2 段)
1. **静的な監査**(`ForbiddenAudit.audit`): コンテンツの監査の段(`auditStages`: 知っている事実の集合。進み方の代表)ごとに、その段で選ばれる見え方の名前・説明と、門(`textGates`)の開いた文字列(門が無い文字列は全段)を作り、禁止語の規則(`forbidden`: 語の並び + `until` = いつまで禁止か)に当てる。英語の内部 ID らしき文字列も捕まえる。CI のテストで 0 件を確かめる。
2. **走行中の監査**(`ForbiddenAudit.check`): ボット走行で画面に出す文字列(Frame の全部)を、その時点の知っている事実で検査する。受け入れテストで 0 件を確かめる。
- アプリの画面の固定文言(`Localizable.xcstrings`)も、非公開の規則で検査する(U3。b7 の T08 の形を新しい規則に置き換える)。
- 本物の規則(語そのもの)は非公開の層。公開の層には試験用の語(「禁句A」)だけを置き、仕組みが働くことを公開のテストで確かめる。

## 6. 公開用の仮コンテンツ(非公開が無いとき)
- `content/public` がそれにあたる: 試験用の 4 人(ノア + 試験の仲間)・地形 3 種・炉 1 種・試験用の事実と出来事(連鎖・決断)・試験用の認識の切り替え・範囲の効果・失敗の規則・工程表の記録・文字列表。
- これで: 公開の CI でビルドとテストが通る / アプリが起動し、地図を歩ける / 仕組み(遡る書き換え・禁止語・出来事の連鎖・決断・巻き戻し)が公開のテストで確かめられる。物語は無い。
- 各担当は、自分の受け入れテストに要る最小の定義を `content/public` に足してよい(ネタバレの無い一般語と試験用の ID だけ)。
