# N-01b 巻き戻しの定義の持ち越しを、データで決める形にする(公開の短い版)

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭。
- 中身: 巻き戻しの定義(`RewindDef`)と走りの状態(`RunState`)と記憶の定義の欄の名前を中立に替え、持ち越す物と割合に本体の既定を持たせず、データが書く形にする。保存と内容の古い名前は `LegacyNames` で当面読む。
- **詳しい説明書は非公開**(reforge-plan の `docs/briefs/N-01b-carries-over.md`)。実装の担当には、統合担当がその道筋を渡す。公開のリポには、替える前の名前・どこに何が残るかを書かない。
- 受け入れ: `swift test --package-path ReForgeCore` が公開の層で全部通る・統合担当が非公開の層を重ねて回す・凍った見本 `save-v1-dev-*.json` を作り直さない・`check-public-spoilers.py`。
