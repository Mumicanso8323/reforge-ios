import RFContent
import RFKernel
import RFRules
import RFSave
import RFWorld

/// 失敗の判定(CORE-12)。コンテンツの失敗の規則(FailureRuleDef)を毎ステップ調べ、成り立ったら周回を失敗にする。
/// 期限も日数でなく値の規則として書く。餓死・脱水も規則(survival の日数の数値)で書く。
/// 骨組みとして規則の評価だけを入れてある。
public struct FailureSystem: SimSystem {
    public let name = "failure"
    public init() {}

    public func step(_ ctx: inout StepContext) {
        guard ctx.world.run.isActive else { return }
        for (_, rule) in ctx.content.failureRules.sorted(by: { $0.key < $1.key })
        where ConditionEvaluator.evaluate(rule.when, &ctx) {
            let rec = ctx.record(.failed, .none, detail: ["cause": .string(rule.cause.rawValue)])
            ctx.world.run.outcome = .failed(cause: rule.cause, record: rec)
            ctx.emit(.runFailed(cause: rule.cause))
            ctx.changes.mark(.run)
            return
        }
    }
}

/// ゲームオーバーの 4 択(オーナー決定。推奨の順位を付けない)。
public enum RecoveryOption: String, Codable, CaseIterable, Sendable {
    /// 最初から。
    case restart
    /// 記憶を持って巻き戻す(最新の夜明けへ。知った事実・ノート・地図の既知・関係・残る記憶は持ち越す)。
    case rewindWithMemory
    /// 失って、その場から続ける。
    case continueWithLoss
    /// セーブ地点からロードする(夜明けの自動セーブか手動セーブ)。
    case loadSavePoint
}

/// 巻き戻しの持ち越し(D-save.md §3)。
///
/// 戻す: 在庫・ライン・配置・建造物・仲間の生死と位置・時計・数値・出来事の進み(= 夜明けの保存のまま)。
/// 残す(失敗した世界から写す): 知った事実(scope = memory のもの)・地図の既知・発見・図鑑の影・実験ノート・
///       関係(点とランク)・巻き戻しをまたぐ記憶・前の周回の覚えておく記録(pastLives)。
/// ID の発行(ids)と来歴の番号は失敗した世界の続きから振る(前の周回の記録と番号を重ねない)。
public enum MemoryCarry {
    public static func rewind(failed: WorldState, dawn: WorldState, content: ContentDB) -> WorldState {
        var w = dawn
        // 知った事実(記憶のもの)
        for (f, r) in failed.knowledge.facts where (content.facts[f]?.scope ?? .memory) == .memory {
            if w.knowledge.facts[f] == nil { w.knowledge.facts[f] = r }
        }
        for (layer, known) in failed.knowledge.mapKnown {
            if var k = w.knowledge.mapKnown[layer], k.size == known.size { k.formUnion(known); w.knowledge.mapKnown[layer] = k } else {
                w.knowledge.mapKnown[layer] = known
            }
        }
        w.knowledge.discovered.formUnion(failed.knowledge.discovered)
        w.knowledge.seen.formUnion(failed.knowledge.seen)
        // 実験ノート(丸ごと: 失敗した周回の方が新しい)
        w.notebook = failed.notebook
        // 関係と、巻き戻しをまたぐ記憶
        let permille = content.rewind.relationPermille ?? 1000
        for id in failed.people.order {
            guard let f = failed.people[id], var p = w.people[id] else { continue }
            p.relation.points = f.relation.points * permille / 1000
            p.relation.rank = f.relation.rank
            let carried = f.memories.filter { $0.persistsAcrossRewind && !p.memories.contains($0) }
            p.memories += carried
            w.people[id] = p
        }
        // 前の周回の覚えておく記録
        let memorable = Set(content.rewind.memorableTags)
        let kept = failed.ledger.records.filter { $0.run == failed.run.index && !$0.tags.isDisjoint(with: memorable) }
        var cause: TextID = "cause.unknown"
        if case .failed(let c, _) = failed.run.outcome { cause = c }
        w.run.pastLives = failed.run.pastLives + [PastLife(run: failed.run.index, endedDay: failed.clock.day, cause: cause,
                                                           memorable: kept)]
        w.run.index = failed.run.index + 1
        w.run.rewinds = failed.run.rewinds + 1
        w.run.outcome = .ongoing
        w.ids = failed.ids
        w.ledger.continueNumbering(after: failed.ledger)
        return w
    }
}
