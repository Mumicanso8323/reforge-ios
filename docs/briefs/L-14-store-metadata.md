# 説明書 L-14: ストアの原稿の置き場

作業の単位: 多言語 L-14(設計: reforge-plan `docs/plans/2026-10-02-localization.md` v0.2 の §12.1・§12.2・BRK-22)。
実装: relay:codex-impl。受け取り: 統合担当(architect)。依存: なし。土台: integration-c の先頭。原稿の中身はリーダーが書く。

## 1. 目的
App Store に出す文(説明文・副題など)と、課金の品の表示名の**置き場と検査**だけを作る。中身は空の枠のまま。アプリ(`ReForge/`)と本体(`ReForgeCore/`)には触らない。

## 2. 作るもの

### 2.1 `store/metadata/<地域コード>/`(fastlane deliver の並び)
- 地域コードは 5 つ: `ja`・`en-US`・`zh-Hans`・`zh-Hant`・`ko`。
- 各フォルダに次のファイルを置く。中身は**空**(0 バイト。改行も無し)。
  `name.txt`・`subtitle.txt`・`description.txt`・`keywords.txt`・`promotional_text.txt`・`release_notes.txt`
- 例外: `name.txt` だけは 5 言語とも `Re:Forge`(改行無し。OPEN-L3 の決定)。
- URL の類(`support_url.txt` など)は作らない(リーダーが後で決める)。

### 2.2 `store/iap/reforge.remove_ads/<地域コード>.json`
- 品の ID は、アプリの `ProductID.removeAds`(`ReForge/Sources/Monetization/StoreService.swift`)と同じ `reforge.remove_ads`。
- 5 つの地域コードごとに `{"name": "", "description": ""}`(キーはこの 2 つだけ。整形は 2 字下げ・末尾に改行)。

### 2.3 `tools/check-store-metadata.py`(新規。python3 の標準だけ。`check-app-names.py` と同じ書き方)
確かめること(どれか外れたら終了コード 1。何がどこで外れたかを 1 行ずつ出す):
1. 5 つの地域コードのフォルダがそろっていて、2.1 の 6 ファイルが全部ある。知らないファイルが無い。
2. 文字数(Python の `len`、末尾の改行 1 つは数えない)の上限: name 30・subtitle 30・keywords 100・promotional_text 170・description 4000・release_notes 4000。
3. `keywords.txt` は、空でなければ `,` 区切りで、各語の前後に空白が無く、空の語が無い。
4. `store/iap/` の下の品ごとに 5 つの地域コードの JSON がそろい、キーが `name`・`description` だけ。上限は name 30・description 45。
5. `--release` を付けたときだけ: 2.1 の `name`・`subtitle`・`description`・`keywords` と 2.2 の両方のキーが、5 言語とも空でない(ストアに出す版の確かめ)。付けないときは空でよい。
6. 英語(`en-US`)と韓国語(`ko`)の文に、カナ・漢字(U+3040〜U+30FF・U+4E00〜U+9FFF)が無い。中国語(両方)の文にカナが無い(TEST-L1 の (5) と同じ考え)。

最後に、通ったときは「ストアの原稿の置き場は形どおり(地域 5・品 N)」の 1 行を出す。

### 2.4 CI(`.github/workflows/ci.yml`)
- `app-switches` のジョブの、`check-app-names.py` の次に `python3 tools/check-store-metadata.py` を 1 行足す(`--release` は付けない)。ほかのジョブとステップは変えない。
- `store/` は `check-public-spoilers.py` の対象に自動で入る(git の管理下の全ファイルを見るので、変更は要らない)。

### 2.5 文書
- `docs/architecture/F-work-units.md` §4 の末尾に 1 行: 「ストアの原稿は `store/metadata/<地域>/`・`store/iap/<品>/<地域>.json`。書くのはリーダー。物語の語を書かない。`tools/check-store-metadata.py` を通す(出す版は `--release`)。」

## 3. 確かめ
- `python3 tools/check-store-metadata.py` が通る(空の枠のまま)。
- `python3 tools/check-store-metadata.py --release` が、空の枠で**落ちる**(落ちることを確かめるだけ。コミットしない)。
- 一時的に `store/metadata/en-US/subtitle.txt` に 31 字を書くと落ち、`ko/description.txt` に「鉄」を書くと落ちることを確かめ、戻す。
- `python3 tools/check-public-spoilers.py`・`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` が通る。
- Swift のビルドとテストは要らない(Swift に触らない)。

## 4. 触ってよいファイル / 触らないファイル
- 触ってよい: `store/`(新規)、`tools/check-store-metadata.py`(新規)、`.github/workflows/ci.yml`(1 行)、`docs/architecture/F-work-units.md`(1 行)。
- 触らない: ほかの全部。とくに `ReForge/`・`ReForgeCore/`・`content/`・`project.yml`・release の名前とタグと ipa の名前(dev の URL は変えない)。

## 5. 約束
- 公開リポジトリに物語の語を書かない(この単位は空の枠なので、書く文は `Re:Forge` だけ)。
- コミットのメッセージの末尾は、渡された 2 行の trailer。

## 7. 終わりの報告(architect へ)
- 冒頭に「非公開未確認」と書く(この作業場には非公開の層が無い。統合担当がマージの前に回す。F §4)。
- 枝の名前・先頭のハッシュ・3 の確かめの結果(落ちることを確かめた分も)・決めかねたこと。
