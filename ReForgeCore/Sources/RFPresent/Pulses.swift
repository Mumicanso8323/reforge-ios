import RFKernel
import RFPerception
import RFRules
import RFSim
import RFWorld

/// 1 回の組み立ての間に起きた、手応え(音・触覚・浮かぶ文字)を返すべきこと(PT-B3)。
/// 来歴と出来事から作るだけで、世界は変えない(音・触覚を切っても世界は同じ)。次のフレームには残らない。
public enum Pulse: Equatable, Sendable {
    /// 手作業・採集の 1 単位(認識の層を通した名前)。
    case unitDone(name: String, count: Int)
    /// 置いた・建て始めた。
    case placed
    /// 建て終わった・作り終わった。
    case finished(name: String)
    /// 初めての物・初めて動いたライン。
    case firstTime(name: String)
    /// 断られた(理由の文)。
    case rejected(reason: String)
    /// くべた。
    case fed
    /// 火が点いた・弱まった・消えた。
    case fire(FirePulse)
    case nightBegan
    /// 決断の帯が出た。
    case decisionShown
}

public enum FirePulse: String, Equatable, Sendable { case lit, weakened, out }

extension FrameBuilder {
    /// 来歴の札の名前が first_ で始まる新しい記録(first_hot_furnace・tag.invention.first_smelt など。名前は決め打ちしない)、
    /// または同じ行為・同じ対象の最初の記録(作った・建てた)なら、その対象の名前。
    func firstName(_ id: ProvenanceID, _ w: WorldState, _ p: Perceiver) -> String? {
        guard let r = w.ledger.record(id) else { return nil }
        let tagged = r.tags.contains { ($0.rawValue.split(separator: ".").last ?? "").hasPrefix("first_") }
        let firstOfKind = (r.act == .crafted || r.act == .built) && w.ledger.first(r.act, r.subject) == id
        guard tagged || firstOfKind else { return nil }
        let name = p.name(of: r.subject)
        return name.isEmpty ? nil : name
    }

    /// 進行の結果(report)と前のフレームとの差から手応えを作る。report が無ければ(ロード・言語の切替)空。
    func pulses(_ w: WorldState, _ p: Perceiver, frame: Frame, previous: Frame?, report: StepReport?) -> [Pulse] {
        guard let report else { return [] }
        var out: [Pulse] = []
        var level = previous?.fireGauge?.level ?? .out
        // 同じ札・同じ名前は 1 回だけ(同じフレームの中でも、前のフレームの分とも重ねない)
        var seen = Set<ProvenanceID>()
        var firstNames = Set<String>()
        for case .firstTime(let n) in previous?.pulses ?? [] { firstNames.insert(n) }
        let interacted = report.events.contains { if case .interacted = $0 { true } else { false } }
        for event in report.events {
            if let id = event.record, seen.insert(id).inserted, let name = firstName(id, w, p), firstNames.insert(name).inserted {
                out.append(.firstTime(name: name))
            }
            switch event {
            case .itemGained(let holder, let stuff, let quantity, let record):
                // 手作業・採取の 1 単位だけ(作った物・報酬・交換では出さない)
                let act = record.flatMap { w.ledger.record($0)?.act }
                if holder.raw.hasPrefix("person:"), interacted || act == .gathered || act == .mined {
                    out.append(.unitDone(name: p.name(of: stuff), count: quantity))
                }
            case .placed:
                out.append(.placed)
            case .built(let placement, _):
                if let kind = w.placements.items[placement]?.kind { out.append(.finished(name: p.name(of: kind))) }
            case .crafted(_, let record):
                // 手作業の製作の完了(.built と同じく、できた帯・音・成功の触覚)
                if let r = w.ledger.record(record) {
                    let name = p.name(of: r.subject)
                    if !name.isEmpty { out.append(.finished(name: name)) }
                }
            case .hearthStoked:
                out.append(.fed)
            case .hearthLevelChanged(_, let now):
                if level == .out, now != .out { out.append(.fire(.lit)) }
                else if now == .out, level != .out { out.append(.fire(.out)) }
                else if now < level { out.append(.fire(.weakened)) }
                level = now
            case .phaseChanged(.dusk, _):
                out.append(.nightBegan)
            default:
                break
            }
        }
        if let r = report.rejection { out.append(.rejected(reason: p.rejectionText(r.reason, detail: r.detail))) }
        if frame.decision != nil, previous?.decision == nil { out.append(.decisionShown) }
        return out
    }
}
