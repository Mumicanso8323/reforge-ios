import RFKernel

/// 運搬と(R2 の)電力。持ち主: RFLogistics。
/// 隣接で向きが合うモジュールのつながりは置き場所から毎回計算する(保存しない。`ModuleTopology`)。
/// 離れたモジュールの間・離れたモジュールと拠点の蓄えの間は運搬の経路で結び、仲間が運ぶ
/// (1 人 1 日の量 × 距離の落ち。経路と流量はここに持ち、仲間が歩く絵は RFCrew が経路の path を使って描く)。
public struct LogisticsState: Codable, Equatable, Sendable {
    public var routes: [EntityID: HaulRoute] = [:]
    /// 電力網(R2)。形は担当が決める。
    public var power: [String: Int] = [:]
    /// 自動の経路を作ったときの置き場所の番号(PlacementsState.topologyVersion。違えば作り直す)。
    public var builtForTopology: Int = -1

    public init() {}

    private enum CodingKeys: String, CodingKey { case routes, power, builtForTopology }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routes = try c.decodeIfPresent([EntityID: HaulRoute].self, forKey: .routes) ?? [:]
        power = try c.decodeIfPresent([String: Int].self, forKey: .power) ?? [:]
        builtForTopology = try c.decodeIfPresent(Int.self, forKey: .builtForTopology) ?? -1
    }

    /// ID 順の経路。
    public var sortedRouteIDs: [EntityID] { routes.keys.sorted() }

    /// 端から出る経路(ID 順)。
    public func routes(from e: HaulEndpoint) -> [HaulRoute] {
        sortedRouteIDs.compactMap { routes[$0] }.filter { $0.from == e }
    }

    /// 端に入る経路(ID 順)。
    public func routes(to e: HaulEndpoint) -> [HaulRoute] {
        sortedRouteIDs.compactMap { routes[$0] }.filter { $0.to == e }
    }
}

/// 運搬の経路の端。置いたモジュールか、拠点の蓄え。
public enum HaulEndpoint: Codable, Hashable, Sendable, Comparable {
    case placement(EntityID)
    case base

    public static func < (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.base, .placement): true
        case (.placement(let x), .placement(let y)): x < y
        default: false
        }
    }

    public var placement: EntityID? {
        if case .placement(let e) = self { e } else { nil }
    }
}

public struct HaulRoute: Codable, Equatable, Sendable {
    public enum Origin: String, Codable, Sendable {
        /// 置き場所から自動で引いた(札の隣の段が離れている・離れた所への燃料・離れた所からの運び出し)。
        case auto
        /// プレイヤーがつないだ。
        case manual
    }

    public var id: EntityID
    public var from: HaulEndpoint
    public var to: HaulEndpoint
    public var origin: Origin
    /// 専任の運び手(Assignment.haul と対になる。配属から毎ステップ写す。表示用)。
    public var haulers: [PersonID]
    /// 道のりのマス数(経路探索の長さ。届かなければ nil)。
    public var distance: Int?
    /// 道のり(表示の点線・仲間が歩く道)。端のマスを含む。
    public var path: [GridPoint]
    /// 距離による落ち(千分率。8 マスまで 1000)。
    public var factorPermille: Int
    /// 運びかけの量(100 万分の 1 個)。
    public var carryMicro: Int64 = 0
    /// 昨日運んだ数(流量の表示)。
    public var movedYesterday: Int = 0
    public var movedToday: Int = 0
    /// 運べない理由(届かない・運び手がいない)。運べていれば nil。
    public var blocked: TextID?

    public init(id: EntityID, from: HaulEndpoint, to: HaulEndpoint, origin: Origin = .manual, haulers: [PersonID] = [],
                distance: Int? = nil, path: [GridPoint] = [], factorPermille: Int = 1000) {
        self.id = id
        self.from = from
        self.to = to
        self.origin = origin
        self.haulers = haulers
        self.distance = distance
        self.path = path
        self.factorPermille = factorPermille
    }

    private enum CodingKeys: String, CodingKey {
        case id, from, to, origin, haulers, distance, path, factorPermille, carryMicro, movedYesterday, movedToday, blocked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(EntityID.self, forKey: .id)
        from = try c.decode(HaulEndpoint.self, forKey: .from)
        to = try c.decode(HaulEndpoint.self, forKey: .to)
        origin = try c.decodeIfPresent(Origin.self, forKey: .origin) ?? .manual
        haulers = try c.decodeIfPresent([PersonID].self, forKey: .haulers) ?? []
        distance = try c.decodeIfPresent(Int.self, forKey: .distance)
        path = try c.decodeIfPresent([GridPoint].self, forKey: .path) ?? []
        factorPermille = try c.decodeIfPresent(Int.self, forKey: .factorPermille) ?? 1000
        carryMicro = try c.decodeIfPresent(Int64.self, forKey: .carryMicro) ?? 0
        movedYesterday = try c.decodeIfPresent(Int.self, forKey: .movedYesterday) ?? 0
        movedToday = try c.decodeIfPresent(Int.self, forKey: .movedToday) ?? 0
        blocked = try c.decodeIfPresent(TextID.self, forKey: .blocked)
    }
}

/// 置いたモジュールのつながり(置き場所から毎回計算する。保存しない)。生産と運搬の両方が使う。
///
/// - 隣接の直結: 自分の出口の辺の隣のマスにモジュールがあり、その入口の辺がこちらを向いていればつながる(運び手は要らない)。
/// - 拠点の中: 拠点の範囲(BaseState.area)の中のモジュールは、蓄えと直に物をやりとりする(燃料を取る・できた物を入れる)。
/// - それ以外の離れた所は運搬の経路(LogisticsState.routes)。
public enum ModuleTopology {
    /// 出口の辺の隣で、入口がこちらを向いているモジュール(辺の順に最初の 1 つ)。
    public static func directDownstream(of id: EntityID, in w: WorldState) -> EntityID? {
        guard let p = w.placements.items[id], let m = p.module else { return nil }
        for side in m.ports.outputs {
            let q = WorldPoint(p.at.layer, p.at.point.moved(side))
            for other in w.placements.at(q) where other != id {
                if let om = w.placements.items[other]?.module, om.ports.inputs.contains(side.opposite) { return other }
            }
        }
        return nil
    }

    /// 全モジュールの直結(上流 → 下流)を一度に引く(マスの索引を 1 回だけ作る。毎ステップ回す側が使う)。
    /// directDownstream(of:) を全モジュールに当てたのと同じ結果。
    public static func directLinks(in w: WorldState) -> [EntityID: EntityID] {
        var cells: [WorldPoint: [EntityID]] = [:]
        let ids = w.placements.sortedIDs
        for id in ids {
            guard let p = w.placements.items[id] else { continue }
            for off in p.footprint {
                cells[WorldPoint(p.at.layer, GridPoint(p.at.point.x + off.x, p.at.point.y + off.y)), default: []].append(id)
            }
        }
        var out: [EntityID: EntityID] = [:]
        for id in ids {
            guard let p = w.placements.items[id], let m = p.module else { continue }
            search: for side in m.ports.outputs {
                for other in cells[WorldPoint(p.at.layer, p.at.point.moved(side))] ?? [] where other != id {
                    if let om = w.placements.items[other]?.module, om.ports.inputs.contains(side.opposite) {
                        out[id] = other
                        break search
                    }
                }
            }
        }
        return out
    }

    /// 自分に直結している上流のモジュール(ID 順)。
    public static func directUpstreams(of id: EntityID, in w: WorldState) -> [EntityID] {
        w.placements.moduleIDs.filter { $0 != id && directDownstream(of: $0, in: w) == id }
    }

    /// 拠点の範囲の中か。
    public static func isInBase(_ id: EntityID, in w: WorldState) -> Bool {
        guard let p = w.placements.items[id] else { return false }
        return isInBase(p.at, in: w)
    }

    public static func isInBase(_ at: WorldPoint, in w: WorldState) -> Bool {
        guard at.layer == .surface, let area = w.base.area else { return false }
        return area.contains(at.point)
    }

    /// 同じ札の次の段を受け持つモジュール(ID 順)。
    public static func nextSteps(of id: EntityID, in w: WorldState) -> [EntityID] {
        guard let m = w.placements.items[id]?.module, let d = m.design, let i = m.stepIndex else { return [] }
        return w.placements.moduleIDs.filter {
            let o = w.placements.items[$0]?.module
            return o?.design == d && o?.stepIndex == i + 1
        }
    }

    /// 拠点の蓄えの場所(運搬の距離の基準)。拠点の範囲で、from に一番近いマス。範囲が無ければ地図の出発点。
    public static func basePoint(near from: GridPoint, in w: WorldState) -> WorldPoint {
        guard let a = w.base.area else { return w.map.spawn }
        let x = min(max(from.x, a.origin.x), a.origin.x + a.size.width - 1)
        let y = min(max(from.y, a.origin.y), a.origin.y + a.size.height - 1)
        return WorldPoint(.surface, GridPoint(x, y))
    }

    /// 経路の端の場所(拠点なら相手の端に一番近い拠点のマス)。
    public static func point(of e: HaulEndpoint, near other: GridPoint?, in w: WorldState) -> WorldPoint? {
        switch e {
        case .placement(let id): return w.placements.items[id]?.at
        case .base: return basePoint(near: other ?? w.map.spawn.point, in: w)
        }
    }
}
