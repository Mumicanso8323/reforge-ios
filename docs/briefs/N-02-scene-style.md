# N-02 場面の型を 1 つ足す(公開の短い版)

**N-03(`SceneStyle.stage`)に含めた。この単位では作らない。**

書いた人: architect(統合担当)。実装: Codex(relay:codex-impl)。土台: 統合の枝 `integration-c` の先頭(PT-B6 の後)。
- 中身: 画面全体で読む場面の型(`SceneStyle`)を、序とは別に 1 つ足す。行に条件を置けて、ふつうの場面の続き・効果から始められ、タップで送る。序の確かめは緩めない。画面は PT-B6 の `PrologueScene` を使い回す。
- **詳しい説明書は非公開**(reforge-plan の `docs/briefs/N-02-scene-style.md`)。型の名前もそちらで決める。
- 受け入れ: 公開の層の試験の場面(中立の文)で、始まり・行の条件・送り・終わりを確かめる。静的の検査一式。
