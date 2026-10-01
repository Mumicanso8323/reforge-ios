import RFContent
import RFKernel
import RFMap
import RFMatter
import RFRules
import RFWorld

/// 運搬(CORE-04)。離れたモジュールの間・離れたモジュールと拠点の蓄えの間を、仲間が運ぶ
/// (1 人 1 日 10 個。距離 8 マスを超えると 5 マスごとに 2 割落ちる。R1 の仮値 `HaulRules`)。
///
/// - 経路は置き場所から自動で引く(`HaulRoutes.rebuild`): 札の次の段が離れていれば その段へ、行き先の無い離れた
///   モジュールからは拠点へ、燃料・混ぜ物の要る離れたモジュールへは拠点から。プレイヤーが結んだ経路(manual)は残す。
/// - 運び手: 経路に配属された仲間(Assignment.haul)と、配属の無い一員(運搬が既定の役割)の共同の手。
///   共同の手は、いま運ぶ物がある経路に等分する。作業の速さ(空腹など)が掛かる。
/// - 原作の TransportSystem は骨組みだけ(空ループ)だった。ここで初めて動かす。
///
/// 書いてよい切れ端: logistics・モジュールの入口と出口の待ち(生産と同じ担当)。乱数は使わない。
public struct LogisticsSystem: SimSystem {
    public let name = "logistics"
    public init() {}

    public func handle(_ command: Command, _ ctx: inout StepContext) -> CommandResult {
        guard case .logistics(let c) = command else { return .notMine }
        switch c {
        case .link(let from, let to): return HaulRoutes.link(from, to, &ctx)
        case .connect(let from, let to): return HaulRoutes.link(.placement(from), .placement(to), &ctx)
        case .disconnect(let route): return HaulRoutes.unlink(route, &ctx)
        }
    }

    public func step(_ ctx: inout StepContext) {
        if ctx.world.logistics.builtForTopology != ctx.world.placements.topologyVersion {
            HaulRoutes.rebuild(&ctx)
        }
        Hauling.step(&ctx)
    }

    public func react(to event: DomainEvent, _ ctx: inout StepContext) {
        if case .dawn = event {
            for id in ctx.world.logistics.sortedRouteIDs {
                guard var r = ctx.world.logistics.routes[id] else { continue }
                r.movedYesterday = r.movedToday
                r.movedToday = 0
                ctx.world.logistics.routes[id] = r
            }
        }
    }
}

/// 運搬の数(order.md §5.6)。コンテンツの "hauling"(HaulingDef)があればその値、無ければ R1 の仮の値。
public enum HaulRules {
    /// 1 人 1 日に運べる数の既定(TransportSystem.cs:13)。
    public static let perPersonPerDay: Int64 = 10
    /// ここまでは落ちない距離(マス)の既定。
    public static let freeDistance = 8
    /// この距離ごとに落ちる(マス)の既定。
    public static let stepDistance = 5
    /// 1 段で残る割合(千分率。2 割落ちる = 800。掛け算で重ねる)の既定。
    public static let keepPermille = 800

    public static func perPersonPerDay(_ def: HaulingDef?) -> Int64 { Int64(max(0, def?.perPersonPerDay ?? Int(perPersonPerDay))) }

    /// 距離による落ち(千分率)。
    public static func factor(distance d: Int, _ def: HaulingDef? = nil) -> Int {
        let free = def?.freeDistance ?? freeDistance
        let step = max(1, def?.stepDistance ?? stepDistance)
        let keep = def?.keepPermille ?? keepPermille
        guard d > free else { return 1000 }
        let steps = (d - free + step - 1) / step
        var f = 1000
        for _ in 0..<steps { f = f * keep / 1000 }
        return f
    }

    /// n 人(作業の速さの千分率の合計 crewMilli)が、距離 d の経路で 1 日に運べる数。
    public static func perDay(crewMilli: Int, distance d: Int, _ def: HaulingDef? = nil) -> Int {
        Int(Int64(crewMilli) * perPersonPerDay(def) * Int64(factor(distance: d, def)) / 1_000_000)
    }

    public static let unreachable: TextID = "reason.haul.unreachable"
    public static let noHaulers: TextID = "reason.haul.no_haulers"
    public static let sameEnds: TextID = "reason.haul.same_ends"
    public static let unknownEnd: TextID = "reason.haul.unknown_end"
    public static let unknownRoute: TextID = "reason.haul.unknown_route"
    public static let autoRoute: TextID = "reason.haul.auto_route"
}
