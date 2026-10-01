import RFContent
import RFKernel
import RFRules
import RFWorld

/// 推理の手がかりをノートに載せる(order.md §5.4 の導線のうち、端末の断片・仲間の知識・手が知っていた手順・
/// 図鑑の空欄の命名の手がかり)。失敗知見は試作の所見がそのまま載る(Trials)、ノアの手の見当は HandSense。
///
/// - どれも `HintDef`(コンテンツ)。条件が成り立った時点で 1 回だけ載る。出典は中立の見出し(R1)。
/// - 条件は乱数を引かない評価(evaluatePure)で見る。chance は成り立たない扱い(物語の乱数の流れを乱さない)。
/// - 調べる時: 出来事への反応(試作した・関係が動いた・事実を知った…)と、1 時間ごとの見回り。
enum Hints {
    /// 反応しない出来事(数が多く、手がかりの条件に関わらないもの)。
    static func ignores(_ e: DomainEvent) -> Bool {
        switch e {
        case .hintHeard, .itemGained, .itemSpent, .produced, .tilesRevealed, .arrived, .bodyChanged, .statCrossed:
            true
        default: false
        }
    }

    static func deliver(_ ctx: inout StepContext, trigger: ProvenanceID?) {
        let pending = ctx.content.hints.filter { ctx.world.notebook.hints[$0.key] == nil }
        guard !pending.isEmpty else { return }
        for (id, def) in pending.sorted(by: { $0.key < $1.key }) {
            guard ConditionEvaluator.evaluatePure(def.when, world: ctx.world, content: ctx.content, trigger: trigger)
                == true
            else { continue }
            let subject: SubjectRef = def.from.map { .person($0) } ?? .none
            let rec = ctx.record(.heardHint, subject, actor: def.from, inputs: trigger.map { [$0] } ?? [],
                                 detail: ["hint": .string(id.rawValue)])
            let now = ctx.world.clock.now
            ctx.world.notebook.hints[id] = now
            ctx.world.notebook.notes.append(NoteEntry(
                about: def.about, text: def.text, source: def.source, record: rec, at: now,
                run: ctx.world.run.index, hint: id))
            ctx.changes.mark(.notebook)
            ctx.emit(.hintHeard(hint: id, from: def.from, record: rec))
        }
    }
}
