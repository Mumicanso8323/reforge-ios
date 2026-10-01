import RFKernel

public enum PlacementTag {}
/// 配置物の ID(層の中で一意)。
public typealias PlacementID = TypedID<PlacementTag>

extension TypedID where Tag == PlacementTag {
    /// 拠点の中央の残骸。
    public static let homeWreck = PlacementID("wreck.home")
    /// 遠くの残骸(川沿いの道の途中)。
    public static let farWreck = PlacementID("wreck.far")
}

public enum PlacementKindTag {}
/// 配置物の種類(原作 `PlacementKind` + 残骸)。建造モジュールも POI も同じ形で持つ。
/// 版をまたいで未知の種類も読めるよう、閉じた enum でなく文字列の ID にする。
public typealias PlacementKind = TypedID<PlacementKindTag>

extension TypedID where Tag == PlacementKindTag {
    /// プレイヤーが建てたモジュール
    public static let module = PlacementKind("module")
    /// 遺跡(漁れる)
    public static let ruins = PlacementKind("ruins")
    /// 獣の巣(脅威の元)
    public static let nest = PlacementKind("nest")
    /// 集落跡
    public static let settlement = PlacementKind("settlement")
    /// 地熱孔
    public static let geothermal = PlacementKind("geothermal")
    /// 肥沃地
    public static let fertileLand = PlacementKind("fertileLand")
    /// 水源
    public static let aquifer = PlacementKind("aquifer")
    /// 汚れた区域
    public static let contamination = PlacementKind("contamination")
    /// 残骸(拠点のもの・遠くのもの)
    public static let wreck = PlacementKind("wreck")

    /// この版が知っている種類。
    public static let known: [PlacementKind] = [.module, .ruins, .nest, .settlement, .geothermal,
                                                .fertileLand, .aquifer, .contamination, .wreck]
}

/// 地図の上の配置物(原作 `MapPlacement`)。テンプレート ID と座標と状態だけを持つ。
public struct MapPlacement: Codable, Equatable, Sendable {
    public let id: PlacementID
    public let kind: PlacementKind
    /// テンプレートの ID(POI なら POITemplateID の raw、モジュールなら設計図の ID)。
    public let templateID: String
    public let anchor: GridPoint
    public let footprint: TileFootprint
    /// 視界に入ったことがあるか(POI は未発見から始まる)。
    public var isDiscovered: Bool
    /// 残りの回数(遺跡のスクラップ・残骸を漁れる回数など)。回数の概念がなければ nil。
    public var remainingUses: Int?
    /// 世界の実体 ID(世界を作るときに振る。探索の進み具合・発見はこの ID で持つ)。
    public var entity: EntityID?

    public init(id: PlacementID, kind: PlacementKind, templateID: String, anchor: GridPoint,
                footprint: TileFootprint = .single, isDiscovered: Bool = true, remainingUses: Int? = nil,
                entity: EntityID? = nil) {
        self.id = id
        self.kind = kind
        self.templateID = templateID
        self.anchor = anchor
        self.footprint = footprint
        self.isDiscovered = isDiscovered
        self.remainingUses = remainingUses
        self.entity = entity
    }

    /// 占めているマス。
    public var cells: [GridPoint] { footprint.cells(at: anchor) }
}

/// 配置物レイヤー(原作 `PlacementLayer`)。建造物と POI をまとめて持ち、マスの重なりを判定する。
public struct PlacementLayer: Codable, Equatable, Sendable {
    public private(set) var placements: [PlacementID: MapPlacement] = [:]
    private var occupied: [GridPoint: PlacementID] = [:]

    public init() {}

    /// 置いてあるものを ID 順で。
    public var all: [MapPlacement] { placements.keys.sorted().map { placements[$0]! } }

    public var count: Int { placements.count }

    /// その形をその位置に置けるか(他の配置物と重ならないか)。地形の制約は呼び出し側が見る。
    public func canPlace(_ footprint: TileFootprint, at anchor: GridPoint) -> Bool {
        footprint.cells(at: anchor).allSatisfy { occupied[$0] == nil }
    }

    /// 置く。重なる、または同じ ID があるときは置かずに false。
    @discardableResult
    public mutating func place(_ p: MapPlacement) -> Bool {
        guard placements[p.id] == nil, canPlace(p.footprint, at: p.anchor) else { return false }
        placements[p.id] = p
        for c in p.cells { occupied[c] = p.id }
        return true
    }

    /// 取り除く。取り除いたものを返す。
    @discardableResult
    public mutating func remove(_ id: PlacementID) -> MapPlacement? {
        guard let p = placements.removeValue(forKey: id) else { return nil }
        for c in p.cells where occupied[c] == id { occupied[c] = nil }
        return p
    }

    /// マスの上の配置物。
    public func placement(at p: GridPoint) -> MapPlacement? {
        occupied[p].flatMap { placements[$0] }
    }

    public func isOccupied(_ p: GridPoint) -> Bool { occupied[p] != nil }

    public subscript(id: PlacementID) -> MapPlacement? {
        get { placements[id] }
    }

    /// 状態だけを書き換える(形と位置は変えられない)。
    public mutating func update(_ id: PlacementID, _ body: (inout MapPlacement) -> Void) {
        guard var p = placements[id] else { return }
        let before = (p.anchor, p.footprint)
        body(&p)
        precondition(before == (p.anchor, p.footprint), "位置と形は update で変えない")
        placements[id] = p
    }

    // MARK: Codable(配列にして ID 順に並べる。占有表は復元時に作り直す)

    private enum CodingKeys: String, CodingKey { case placements }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for p in try c.decode([MapPlacement].self, forKey: .placements) {
            guard place(p) else {
                throw DecodingError.dataCorruptedError(forKey: .placements, in: c, debugDescription: "配置物が重なっている: \(p.id)")
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(all, forKey: .placements)
    }

    public static func == (a: PlacementLayer, b: PlacementLayer) -> Bool { a.placements == b.placements }
}
