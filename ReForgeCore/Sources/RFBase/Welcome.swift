import RFContent
import RFKernel
import RFRules
import RFWorld

/// 生存者を迎える(BEAT-20)。人が増える道は救助だけ。
///
/// 条件: 会った人(presence = met)で生きている / ノアがその人のそばにいるか、その人が拠点の範囲の中にいる /
/// 拠点の蓄えに BaseDef.welcomeRequires(食料)がある / 収容(建ち終えた建造物の housing の合計)が一員の数より多い。
/// 迎えると食料を使い(welcomeConsumes)、来歴 rescued を残し、RFCrew に joinFromEffect を渡す。
enum Welcome {
    static func welcome(_ person: PersonID, _ ctx: inout StepContext) -> CommandResult {
        let w = ctx.world
        guard let ps = w.people[person], case .met = ps.presence else {
            return .rejected(Rejection("reason.base.welcome.not_met"))
        }
        let inBase = ps.position.map { $0.layer == .surface && w.base.area?.contains($0.point) == true } ?? false
        let besideNoah: Bool = {
            guard let a = ps.position, let b = w.people[.noah]?.position, a.layer == b.layer else { return false }
            return a.point.chebyshev(to: b.point) <= 1
        }()
        guard inBase || besideNoah else { return .rejected(Rejection("reason.base.welcome.too_far")) }
        guard BaseRules.housing(w, ctx.content) > w.people.members.count else {
            return .rejected(Rejection("reason.base.welcome.no_room"))
        }
        let need = ctx.content.base.welcomeRequires ?? []
        for ing in need where Construction.have(ing, w) < ing.quantity {
            return .rejected(Rejection("reason.base.welcome.no_food"))
        }
        var inputs: [ProvenanceID] = []
        if ctx.content.base.welcomeConsumes ?? true {
            for ing in need {
                if let took = ctx.takeStock(ing.quantity, from: .base, where: { ing.matches($0) && $0.unique == nil }) {
                    inputs += took.keys.filter { $0 != ProvenanceLedger.unknownOrigin }
                }
            }
        }
        let rec = ctx.record(.rescued, .person(person), actor: .noah, place: ps.position,
                             inputs: Array(Set(inputs)).sorted())
        ctx.queue(.crew(.joinFromEffect(person: person, cause: rec)))
        ctx.changes.mark(.people)
        return .done
    }
}
