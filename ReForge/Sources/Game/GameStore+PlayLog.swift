import Foundation
import QuartzCore
import ReForgeEngine
import UIKit
import RFContent
import RFPresent
import RFSim
import RFWorld

/// 操作記録に残す内容の組み立て(PT-B4)。記録は端末の中だけ。世界にも保存にも入れず、ID だけを書く。
/// GameStore 本体からは 1 行ずつ呼ぶ。
@MainActor
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
    var metrics = PlayMetrics()
    let ticker = FrameTicker()
    var thermalObserver: NSObjectProtocol?
    var marksLoaded = false
    var marksSeed: UInt64?
    /// いまの画面(idle の行に入れる)。
    var screen = "map"
}

/// 節目の追跡の置き場(playlog/marks.json。遊び〈seed〉ごと。保存には入れない)。
private struct MarksFile: Codable {
    var seed: UInt64
    var tracker: PlaytestMarkTracker
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

    /// 命令の中の ID・数・向きだけを取り出す(文字列は物語の文になりうるので入れない)。
    nonisolated static func commandIDs(_ command: Command) -> String {
        var out: [String] = []
        func walk(_ value: Any, label: String?, depth: Int) {
            guard depth < 5, out.count < 12 else { return }
            let type = String(describing: Swift.type(of: value))
            switch value {
            case is String, is Substring: return
            case let v as Int: out.append("\(label ?? "n")=\(v)")
            case let v as Int64: out.append("\(label ?? "n")=\(v)")
            case let v as Bool: out.append("\(label ?? "b")=\(v)")
            default:
                if type.hasPrefix("TypedID") || type.hasSuffix("ID") {
                    out.append("\(label ?? "id")=\(value)")
                    return
                }
                let m = Mirror(reflecting: value)
                if m.displayStyle == .enum {
                    if m.children.isEmpty { out.append("\(label ?? "case")=\(value)"); return }
                    for c in m.children { walk(c.value, label: c.label, depth: depth + 1) }
                } else if m.displayStyle == .struct || m.displayStyle == .tuple || m.displayStyle == .collection
                            || m.displayStyle == .optional {
                    for c in m.children.prefix(6) {
                        walk(c.value, label: m.displayStyle == .optional ? label : (c.label ?? label), depth: depth + 1)
                    }
                }
            }
        }
        // 先頭の case 名は kind に入っているので、中身だけを見る
        for c in Mirror(reflecting: command).children { walk(c.value, label: c.label, depth: 0) }
        return out.joined(separator: ",")
    }

    /// データで「分かれ道」の印が付いた建てる物を置く命令か(StructureDef.branchChoice)。
    nonisolated static func placesBranchChoice(_ command: Command, _ content: ContentDB) -> Bool {
        func find(_ value: Any) -> StructureKindID? {
            if let k = value as? StructureKindID { return k }
            for child in Mirror(reflecting: value).children { if let k = find(child.value) { return k } }
            return nil
        }
        guard let kind = find(command) else { return false }
        return content.structures[kind]?.branchChoice == true
    }

    /// 出した命令と、受け付けたか・断られたか(理由の ID)。
    func recordCommand(_ command: Command, rejection: TextRef?, accepted: Bool) {
        guard playLog?.isRecording == true else { return }
        let kind = Self.commandKind(command)
        var fields = ["command": kind, "result": accepted ? "accepted" : "rejected"]
        let ids = Self.commandIDs(command)
        if !ids.isEmpty { fields["ids"] = ids }
        if let rejection { fields["reason"] = rejection.id.rawValue }
        logPlay(kind: "command", fields: fields)
        let r = playRecorder
        r.dayCommands += 1
        if accepted, Self.isDecision(command) || Self.placesBranchChoice(command, content) { r.dayDecisions += 1 }
        if r.runKind == kind { r.runLength += 1 } else { r.runKind = kind; r.runLength = 1 }
        r.dayLongestRun = max(r.dayLongestRun, r.runLength)
    }

    /// 命令を出した時刻を覚え、10 秒以上あいていたら `idle` を書く。
    func recordTouch() {
        guard playLog?.isRecording == true else { return }
        let screen = playRecorder.screen
        playRecorder.metrics.touch(at: CACurrentMediaTime())
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
        let r = playRecorder
        let url = playLog?.directory.appendingPathComponent("marks.json")
        if !r.marksLoaded || r.marksSeed != world.seed {
            r.marksLoaded = true
            r.marksSeed = world.seed
            r.tracker = PlaytestMarkTracker()
            if let url, let data = try? Data(contentsOf: url),
               let file = try? JSONDecoder().decode(MarksFile.self, from: data), file.seed == world.seed {
                r.tracker = file.tracker
            }
        }
        let fresh = r.tracker.update(world, content)
        for id in fresh { logPlay(kind: "mark", fields: ["mark": id]) }
        if !fresh.isEmpty, let url, let data = try? JSONEncoder().encode(MarksFile(seed: world.seed, tracker: r.tracker)) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 新しい Frame から、選ぶ物が出たこと(offer)と夜明け(day)を拾う。
    func recordFrame(_ f: Frame) {
        recordFrame(decision: f.decision.map { "\($0.id)" }, offers: f.offers.map { "\($0.kind.rawValue):\($0.person)" },
                    day: f.clock.day)
    }

    func recordFrame(decision decisionID: String?, offers offerIDs: [String], day: Int) {
        guard playLog?.isRecording == true else { return }
        let r = playRecorder
        if decisionID != r.lastDecision {
            if let decisionID { logPlay(kind: "offer", fields: ["decision": decisionID]) }
            r.lastDecision = decisionID
        }
        for o in offerIDs where !r.lastOffers.contains(o) { logPlay(kind: "offer", fields: ["offer": o]) }
        r.lastOffers = offerIDs
        if let last = r.lastDay, day != last {
            logPlay(kind: "day", fields: ["commands": "\(r.dayCommands)", "decisions": "\(r.dayDecisions)",
                                          "longestRun": "\(r.dayLongestRun)"])
            r.dayCommands = 0; r.dayDecisions = 0; r.dayLongestRun = 0; r.runKind = nil; r.runLength = 0
            Task { await recordMarks() }
        }
        r.lastDay = day
    }
}

// MARK: - 操作性の印(latency・hitch・power・confirm・session・build)

extension GameStore {
    /// 画面が出ている間、描画の合図で latency・hitch を数える。熱の段が変わったら power を 1 件。
    func startFrameMeter() {
        guard playLog?.isRecording == true else { return }
        let r = playRecorder
        r.ticker.onFrame = { [weak self] t in
            guard let self, self.playLog?.isRecording == true, self.isActive else { return }
            for e in self.playRecorder.metrics.frame(at: t) { self.logPlay(kind: e.kind, fields: e.fields) }
        }
        r.ticker.start()
        if r.thermalObserver == nil {
            r.thermalObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.logPower(event: "thermal") }
            }
        }
    }

    func stopFrameMeter() {
        playRecorder.ticker.stop()
        playRecorder.metrics.suspend()
    }

    /// 後ろに下がるとき、止まったままだった時間が 10 秒以上なら idle を 1 件書く。
    func flushIdle() {
        let r = playRecorder
        guard let last = r.lastTouch else { return }
        let gap = now().timeIntervalSince(last)
        if gap >= PlayRecorder.idleSeconds { logPlay(kind: "idle", fields: ["seconds": "\(Int(gap))", "screen": r.screen]) }
        r.lastTouch = nil
    }

    /// 画面(タブ)を開いた。いまの画面を覚える。
    func logPanel(_ name: String) {
        playRecorder.screen = name
        logPlay(kind: "panel", fields: ["tab": name])
    }

    func logPower(event: String) {
        guard playLog?.isRecording == true else { return }
        var fields = DeviceSnapshot.power()
        fields["event"] = event
        logPlay(kind: "power", fields: fields)
    }

    /// 前に出た・後ろに下がった(画面の向きと操作棒の左右つき)と、その時の電池・熱。
    func logSession(active: Bool) {
        guard playLog?.isRecording == true else { return }
        if !active {
            playRecorder.metrics.suspend()
            flushIdle()
        }
        logPlay(kind: "session", fields: ["state": active ? "front" : "back", "orientation": DeviceSnapshot.orientation(),
                                          "hand": MapTouchSettings.hand(defaults).rawValue])
        logPower(event: active ? "front" : "back")
    }

    /// 確認(長押しで決める)の出た・決めた・取りやめた。
    func logConfirm(id: String, phase: String) {
        logPlay(kind: "confirm", fields: ["id": id, "phase": phase])
    }
}
