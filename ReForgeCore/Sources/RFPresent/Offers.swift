import RFContent
import RFKernel
import RFPerception
import RFRules
import RFSim
import RFWorld

/// 日没の帯に出る申し出 1 つ(BEAT-19・UI-09)。状態は持たない(毎回世界から導く)。
/// 出すのは、押せば必ず受け付けられる物だけ(INV-D2。見せて断らない)。
public struct PendingOffer: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case tendFire }

    public var kind: Kind
    public var person: PersonID
    /// 認識の層を通した人の名前。
    public var name: String
    /// tendOffer.lines の一言(文字列表から)。
    public var line: String?
    /// 押すと送る。
    public var command: Command

    public init(kind: Kind, person: PersonID, name: String, line: String? = nil, command: Command) {
        self.kind = kind
        self.person = person
        self.name = name
        self.line = line
        self.command = command
    }
}

extension FrameBuilder {
    /// 火の番の申し出(日没・夜作業の間、点いている拠点の焚き火に番がいないとき、順の先頭の出せる 1 人)。
    /// 出す条件は CrewSystem.assign の受け付け(一員で地図にいる・手が先)と、Simulation.apply の入口の断り
    /// (走りが終わった後・場面・始まりの保留)と同じ判定。
    func offers(_ w: WorldState, _ p: Perceiver) -> [PendingOffer] {
        guard let def = content.crewWork?.tendOffer, w.clock.phase != .day, w.run.isActive, !w.clock.held,
              !blocksCommands(w), let fire = primaryHearth(w), let state = Hearths.state(fire, content),
              let hearth = Hearths.def(fire, content), HearthRule.level(state, hearth) != .out,
              !Hearths.isTended(fire.id, in: w) else { return [] }
        let assignment = Assignment.tendHearth(placement: fire.id)
        let candidates = def.order ?? w.people.order
        for id in candidates where id != .noah {
            guard let ps = w.people[id], ps.presence.isMember, ps.presence.isAlive, ps.position != nil,
                  w.people.effectiveAssignment(id) != assignment,
                  CrewWork.refusal(assignment, for: id, w, content) == nil else { continue }
            let line = def.lines?[id].flatMap { content.texts[$0] != nil ? p.text($0) : nil }
            return [PendingOffer(kind: .tendFire, person: id, name: p.name(Subject.person(id)), line: line,
                                 command: .crew(.assign(person: id, assignment: assignment)))]
        }
        return []
    }

    /// 本体が命令の入口で断る場面(序の場面・読む場面)が出ているか。
    private func blocksCommands(_ w: WorldState) -> Bool {
        guard let scene = w.narrative.scene, let style = content.scenes[scene.scene]?.style else { return false }
        return style == .prologue || style == .stage
    }
}
