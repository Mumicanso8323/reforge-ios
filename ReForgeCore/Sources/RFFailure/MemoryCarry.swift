import RFContent
import RFKernel
import RFRules
import RFWorld

/// 記憶を持って巻き戻す(D-save.md §3)。
///
/// 戻す: 在庫・ライン・配置・建造物・仲間の生死と位置と体・時計・数値・出来事の進み・研究(= 夜明けの保存のまま)。
/// 残す(失敗した世界から写す): 知った事実(scope = memory のもの)・地図の既知・発見・図鑑の影・実験ノート・
///       関係(点とランク)・巻き戻しをまたぐ記憶・前の周回の覚えておく記録(pastLives)。
/// ID の発行(ids)と来歴の番号は失敗した世界の続きから振る(前の周回の記録と番号を重ねない)。
///
/// 物語の引き金は変えない: 出来事の進み(発火済み・予約・カウンタ)は夜明けのまま戻り、巻き戻し自体は出来事を
/// 発火させない(次のステップに `runResumed` を 1 つ出すだけ)。巻き戻しで増えるのは、仲間の記憶
/// (RewindDef.dejaVuMemory)1 つと、来歴の .rewound 1 件だけ。
public enum MemoryCarry {
    public static func rewind(failed: WorldState, dawn: WorldState, content: ContentDB) -> WorldState {
        var w = dawn
        // 夜明けの来歴に無い(= 巻き戻しで消える)記録か
        let lost: (ProvenanceID) -> Bool = { $0.raw >= dawn.ledger.nextID }
        var referenced: [ProvenanceID] = []

        // 知った事実(記憶のもの)
        for (f, r) in failed.knowledge.facts.sorted(by: { $0.key < $1.key })
        where (content.facts[f]?.scope ?? .memory) == .memory && w.knowledge.facts[f] == nil {
            w.knowledge.facts[f] = r
            if let v = r.via { referenced.append(v) }
        }
        for (layer, known) in failed.knowledge.mapKnown {
            if var k = w.knowledge.mapKnown[layer], k.size == known.size {
                k.formUnion(known)
                w.knowledge.mapKnown[layer] = k
            } else {
                w.knowledge.mapKnown[layer] = known
            }
        }
        w.knowledge.discovered.formUnion(failed.knowledge.discovered)
        w.knowledge.seen.formUnion(failed.knowledge.seen)
        w.knowledge.heldItems.formUnion(failed.knowledge.heldItems)
        w.knowledge.inspected.formUnion(failed.knowledge.inspected)
        // 開示(INV-O4): 知識で開いたものだけを運ぶ。世界の状態で開いたものは夜明けの世界のまま
        for (id, kind) in failed.knowledge.disclosed where kind == .knowledge { w.knowledge.disclosed[id] = kind }
        // 手でやった行為は知識の側(INV-O4・INV-O8)
        w.knowledge.handDone.formUnion(failed.knowledge.handDone)

        // 実験ノート(丸ごと: 失敗した周回の方が新しく、夜明けの分を含む)
        w.notebook = failed.notebook
        referenced += failed.notebook.trials.map(\.record)
        referenced += failed.notebook.notes.compactMap(\.record)
        referenced += failed.notebook.codex.compactMap(\.firstSeen)

        // 関係と、巻き戻しをまたぐ記憶
        let permille = content.rewind.relationPermille ?? 1000
        for id in failed.people.order {
            guard let f = failed.people[id], var p = w.people[id] else { continue }
            p.relation.points = f.relation.points * permille / 1000
            p.relation.rank = f.relation.rank
            let carried = f.memories.filter { $0.persistsAcrossRewind && !p.memories.contains($0) }
            p.memories += carried
            referenced += carried.compactMap(\.about)
            w.people[id] = p
        }

        // 前の周回の覚えておく記録(印の付いたもの + 失敗の記録)と、持ち越した物が指す記録の写し
        let tags = Set(content.rewind.memorableTags)
        var cause: TextID = "cause.unknown"
        var failRecord: ProvenanceID?
        if case .failed(let c, let r) = failed.run.outcome {
            cause = c
            failRecord = r
        }
        let memorable = failed.ledger.records.filter {
            lost($0.id) && (!$0.tags.isDisjoint(with: tags) || $0.id == failRecord)
        }
        let memorableIDs = Set(memorable.map(\.id))
        let refIDs = Set(referenced.filter { lost($0) && !memorableIDs.contains($0) })
        let references = failed.ledger.records.filter { refIDs.contains($0.id) }
        w.run.pastLives = failed.run.pastLives + [
            PastLife(run: failed.run.index, endedDay: failed.clock.day, endedAt: failed.clock.now,
                     rewoundToDay: dawn.clock.day, cause: cause, memorable: memorable, references: references),
        ]
        w.run.index = failed.run.index + 1
        w.run.rewinds = failed.run.rewinds + 1
        w.run.losses = failed.run.losses
        w.run.outcome = .ongoing
        w.ids = failed.ids
        w.ledger.continueNumbering(after: failed.ledger)

        // 巻き戻しの来歴(回数は来歴に残る)と、仲間の「前にも」の記憶
        var ctx = StepContext(world: w, content: content)
        var detail: [String: Value] = [
            "fromRun": .int(Int64(failed.run.index)), "failedDay": .int(Int64(failed.clock.day)),
            "cause": .string(cause.rawValue),
        ]
        if let r = failRecord { detail["failure"] = .int(Int64(r.raw)) }
        let rec = ctx.record(.rewound, .none, inputs: failRecord.map { [$0] } ?? [], detail: detail)
        if let kind = content.rewind.dejaVuMemory {
            let persists = content.memoryKinds[kind]?.persistsAcrossRewind ?? true
            for id in ctx.world.people.members where id != .noah {
                ctx.world.people[id]?.memories.append(
                    MemoryRecord(kind: kind, at: ctx.world.clock.now, run: ctx.world.run.index, about: rec,
                                 persistsAcrossRewind: persists))
            }
        }
        ctx.world.run.resumeNotice = rec
        return ctx.world
    }
}
