import Foundation
import RFContent
import RFPresent
import RFSim
import RFWorld

/// 操作記録に残す内容の組み立て(PT-B4)。記録は端末の中だけ。世界にも保存にも入れず、ID だけを書く。
/// GameStore 本体からは 1 行ずつ呼ぶ。
final class PlayRecorder {
    /// 何も押さない時間がこれ以上なら `idle` を 1 件書く(秒)。
    static let idleSeconds: TimeInterval = 10
    var tracker = PlaytestMarkTracker()
    var lastTouch: Date?
    var lastDecision: String?
    var lastOffers: [String] = []
    var lastDay: Int?
    var dayCommands = 0
    var dayDecisions = 0
    var dayLongestRun = 0
    var runKind: String?
    var runLength = 0
}

extension GameStore {
    /// 命令の種類(case 名の並び)。中身の ID は args に別に入れる。
    nonisolated static func commandKind(_ command: Command) -> String {
        var names: [String] = []
        var value: Any = command
        while let child = Mirror(reflecting: value).children.first, let label = child.label {
            names.append(label)
            value = child.value
            if Mirror(reflecting: value).displayStyle != .enum { break }
        }
        if names.isEmpty { return String(describing: command) }
        if Mirror(reflecting: value).displayStyle == .enum { names.append(String(describing: value)) }
        return names.joined(separator: ".")
    }

    /// 決定の数に入る命令か(選択肢を選ぶ・ライン札にする・配属を変える)。
    nonisolated static func isDecision(_ command: Command) -> Bool {
        let kind = commandKind(command)
        return kind.hasPrefix("narrative.decide") || kind.hasPrefix("invention.makeDesign") || kind.contains("assign")
    }

    /// 出した命令と、受け付けたか・断られたか(理由の ID)。
    func recordCommand(_ command: Command, rejection: TextRef?, accepted: Bool) {
        guard playLog?.isRecording == true else { return }
        let kind = Self.commandKind(command)
        var fields = ["command": kind, "result": accepted ? "accepted" : "rejected"]
        let args = String(describing: command)
        fields["args"] = String(args.prefix(160))
        if let rejection { fields["reason"] = rejection.id.rawValue }
        logPlay(kind: "command", fields: fields)
        let r = playRecorder
        r.dayCommands += 1
        if accepted, Self.isDecision(command) { r.dayDecisions += 1 }
        if r.runKind == kind { r.runLength += 1 } else { r.runKind = kind; r.runLength = 1 }
        r.dayLongestRun = max(r.dayLongestRun, r.runLength)
    }

    /// 命令を出した時刻を覚え、10 秒以上あいていたら `idle` を書く。
    func recordTouch(screen: String = "map") {
        guard playLog?.isRecording == true else { return }
        let t = now()
        if let last = playRecorder.lastTouch {
            let gap = t.timeIntervalSince(last)
            if gap >= PlayRecorder.idleSeconds {
                logPlay(kind: "idle", fields: ["seconds": "\(Int(gap))", "screen": screen])
            }
        }
        playRecorder.lastTouch = t
    }

    /// 節目を見る(命令の後と夜明け)。初めて成り立った節目ごとに `mark` を 1 件。
    func recordMarks() async {
        guard playLog?.isRecording == true, !content.playtestMarks.isEmpty else { return }
        let world = await host.world
        for id in playRecorder.tracker.update(world, content) { logPlay(kind: "mark", fields: ["mark": id]) }
    }

    /// 新しい Frame から、選ぶ物が出たこと(offer)と夜明け(day)を拾う。
    func recordFrame(_ f: Frame) {
        guard playLog?.isRecording == true else { return }
        let r = playRecorder
        let decisionID = f.decision.map { "\($0.id)" }
        if decisionID != r.lastDecision {
            if let decisionID { logPlay(kind: "offer", fields: ["decision": decisionID]) }
            r.lastDecision = decisionID
        }
        let offerIDs = f.offers.map { "\($0.kind.rawValue):\($0.person)" }
        for o in offerIDs where !r.lastOffers.contains(o) { logPlay(kind: "offer", fields: ["offer": o]) }
        r.lastOffers = offerIDs
        if let day = r.lastDay, f.clock.day != day {
            logPlay(kind: "day", fields: ["commands": "\(r.dayCommands)", "decisions": "\(r.dayDecisions)",
                                          "longestRun": "\(r.dayLongestRun)"])
            r.dayCommands = 0; r.dayDecisions = 0; r.dayLongestRun = 0; r.runKind = nil; r.runLength = 0
            Task { await recordMarks() }
        }
        r.lastDay = f.clock.day
    }
}
