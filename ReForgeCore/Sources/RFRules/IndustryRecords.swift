import RFKernel
import RFWorld

/// 工業の「初めて」の記録の札(W-24)。名前は内容の側がこの綴りで指す(RFInvention の InventionTags も同じ値を公開する)。
///
/// 炉(RFProduction)・電気を出す建造物(RFBase)・電気を出すモジュール(RFProduction)は互いに import しないので、
/// 札と「毎回の札 + 初めての 1 回だけの札」を付ける手順は、みんなが引く RFRules に置く。
public enum IndustryRecords {
    public static let furnaceHot: ProvenanceTag = "tag.invention.furnace_hot"
    public static let firstHotFurnace: ProvenanceTag = "tag.invention.first_hot_furnace"
    public static let powered: ProvenanceTag = "tag.invention.powered"
    public static let firstPower: ProvenanceTag = "tag.invention.first_power"

    /// ledger にまだ毎回の札の記録が無いか(あれば 2 回目以降)。
    static func isFirst(_ every: ProvenanceTag, _ w: WorldState) -> Bool {
        !w.ledger.records.contains { $0.tags.contains(every) }
    }
}

extension StepContext {
    /// 毎回の札を付けて記録する。ledger にまだ毎回の札の記録が無かった時は、初めての札も付ける(first_smelt と同じ決め方)。
    @discardableResult
    public mutating func recordIndustry(_ act: ActKind, _ subject: SubjectRef, place: WorldPoint?, every: ProvenanceTag,
                                 first: ProvenanceTag) -> ProvenanceID {
        var tags: Set<ProvenanceTag> = [every]
        if IndustryRecords.isFirst(every, world) { tags.insert(first) }
        return record(act, subject, place: place, tags: tags)
    }
}
