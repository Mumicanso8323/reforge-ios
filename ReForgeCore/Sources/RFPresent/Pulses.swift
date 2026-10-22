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

extension Frame {
    /// このフレームを組み立てた間に起きた手応え。前のフレームから後の分だけ。
    public var pulses: [Pulse] { pulseList }
}

extension FrameBuilder {
    /// 進行の結果(report)と前のフレームとの差から手応えを作る。report が無ければ(ロード・言語の切替)空。
    func pulses(_ w: WorldState, _ p: Perceiver, frame: Frame, previous: Frame?, report: StepReport?) -> [Pulse] {
        guard let report else { return [] }
        var out: [Pulse] = []
        var level = previous?.fireGauge?.level ?? .out
        for event in report.events {
            switch event {
            case .itemGained(let holder, let stuff, let quantity, _):
                if holder.raw.hasPrefix("person:") { out.append(.unitDone(name: p.name(of: stuff), count: quantity)) }
            case .placed:
                out.append(.placed)
            case .built(let placement, _):
                if let kind = w.placements.items[placement]?.kind { out.append(.finished(name: p.name(of: kind))) }
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
