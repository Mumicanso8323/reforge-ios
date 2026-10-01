/// 配置物の ID(層の中で一意)。
public struct PlacementID: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }

    /// 自分たちの残骸(拠点の中央)。
    public static let homeWreck = PlacementID("wreck.home")
    /// 先に来た誰かの残骸(遠回りの先)。
    public static let farWreck = PlacementID("wreck.far")

    public static func < (a: PlacementID, b: PlacementID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

/// 配置物の種類(原作 `PlacementKind` + 残骸)。建造モジュールも POI も同じ形で持つ。
public enum PlacementKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    /// プレイヤーが建てたモジュール
    case module
    /// 遺跡(漁れる)
    case ruins
    /// 獣の巣(脅威の元)
    case nest
    /// 集落跡
    case settlement
    /// 地熱孔
    case geothermal
    /// 肥沃地
    case fertileLand
    /// 水源
    case aquifer
    /// 汚れた区域
    case contamination
    /// 残骸(自分たちのもの・先に来た誰かのもの)
    case wreck
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

    public init(id: PlacementID, kind: PlacementKind, templateID: String, anchor: GridPoint,
                footprint: TileFootprint = .single, isDiscovered: Bool = true, remainingUses: Int? = nil) {
        self.id = id
        self.kind = kind
        self.templateID = templateID
        self.anchor = anchor
        self.footprint = footprint
        self.isDiscovered = isDiscovered
        self.remainingUses = remainingUses
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
