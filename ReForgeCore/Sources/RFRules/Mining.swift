import RFContent
import RFKernel
import RFMap
import RFWorld

/// 掘る規則(刃の段と鉱脈の硬さ。ContentDB.mining)。行為の掘る(RFExploration)と手で掘る(RFProduction)が使う。
public enum MiningRules {
    /// いまの刃の段(拠点全体)。blades の条件が成り立った段の最大。無ければ 0。
    public static func bladeTier(world w: WorldState, content: ContentDB) -> Int {
        (content.mining.blades ?? []).filter {
            ConditionEvaluator.evaluatePure($0.when, world: w, content: content) == true
        }.map(\.tier).max() ?? 0
    }

    /// その鉱脈を掘れるか。掘れなければ断りの理由(detail: need・have = 刃の段)。
    /// extra = 行為の側で足す段(InteractionDef.bladeTier)。
    public static func check(_ deposit: Deposit, extra: Int? = nil, world w: WorldState, content: ContentDB) -> Rejection? {
        let byKind = content.mining.required(for: deposit.category)
        let need = max(byKind, extra ?? 0)
        guard need > 0 else { return nil }
        let have = bladeTier(world: w, content: content)
        guard have < need else { return nil }
        let reason = byKind >= need ? content.mining.reason(for: deposit.category)
            : (content.mining.tooHard ?? MiningDef.tooHardDefault)
        return Rejection(reason, detail: ["need": .int(Int64(need)), "have": .int(Int64(have))])
    }
}
