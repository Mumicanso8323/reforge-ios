import RFKernel
import RFMatter

/// 在庫の中身 1 種。純度・形・熱の状態を持つ物(鉱石・鉄)は RFMatter の Matter、
/// それ以外(薪・木炭・石灰石・食料・水…)は ItemID だけで表す。
public enum Stuff: Codable, Hashable, Sendable {
    case item(ItemID)
    case matter(Matter)
}

/// 物の山 1 つ。中身と数と来歴を持つ。
public struct StockEntry: Codable, Equatable, Sendable {
    public var stuff: Stuff
    public var quantity: Int
    /// この山がどこから来たか(来歴 → 数)。山を合わせたら足し合わせる。上限を超えたら少ない方から
    /// ProvenanceLedger.unknownOrigin にまとめる。
    public var origins: [ProvenanceID: Int]
    /// 唯一品(遺品・旧文明の刃・最初の鉄など)の実体 ID。唯一品は数 1 で、他の山と合わせない。
    public var unique: EntityID?
    /// 減ったら戻らない品の残り(千分率)。
    public var durability: Milli?
    /// 品そのものが持つ属性(例 "owner": 遺品の持ち主の PersonID)。属性のある山は他の山と合わせない。
    public var attributes: [String: String]?

    public init(stuff: Stuff, quantity: Int, origins: [ProvenanceID: Int] = [:], unique: EntityID? = nil,
                durability: Milli? = nil, attributes: [String: String]? = nil) {
        self.stuff = stuff
        self.quantity = quantity
        self.origins = origins
        self.unique = unique
        self.durability = durability
        self.attributes = attributes
    }

    /// 他の山と合わせられる(唯一品でも、減る品でも、属性つきでもない)。
    public var isPlain: Bool { unique == nil && durability == nil && attributes == nil }

    /// 来歴を何種類まで覚えておくか。
    public static let originLimit = 16
}

/// 物の在り処の名前。
public struct HolderID: Hashable, Comparable, Codable, Sendable, CodingKeyRepresentable, CustomStringConvertible {
    public let raw: String
    public init(raw: String) { self.raw = raw }

    /// 拠点の蓄え(保管の建造物の容量の合計を上限とする)。
    public static let base = HolderID(raw: "base")
    /// 人の持ち物。
    public static func person(_ p: PersonID) -> HolderID { HolderID(raw: "person:\(p.rawValue)") }
    /// 保管庫など置いた物の中。
    public static func placement(_ e: EntityID) -> HolderID { HolderID(raw: "placement:\(e.raw)") }

    public var description: String { raw }
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public var codingKey: CodingKey { Key(stringValue: raw) }
    public init?<T: CodingKey>(codingKey: T) { raw = codingKey.stringValue }
}

/// 在庫の 1 山を指す(画面からのコマンド用)。
public struct StockSelector: Codable, Hashable, Sendable {
    public var holder: HolderID
    public var stuff: Stuff
    /// 唯一品を指すとき。
    public var unique: EntityID?

    public init(holder: HolderID, stuff: Stuff, unique: EntityID? = nil) {
        self.holder = holder
        self.stuff = stuff
        self.unique = unique
    }
}

/// 物の在り処の全部。持ち主: 共通(出し入れは StepContext の在庫操作を使う。直接いじらない)。
public struct InventoryState: Codable, Equatable, Sendable {
    public var holders: [HolderID: [StockEntry]] = [:]

    public init() {}

    public func entries(_ h: HolderID) -> [StockEntry] { holders[h] ?? [] }

    public func quantity(_ item: ItemID, in h: HolderID = .base) -> Int {
        entries(h).filter { $0.stuff == .item(item) }.reduce(0) { $0 + $1.quantity }
    }

    public func quantity(where match: (Stuff) -> Bool, in h: HolderID = .base) -> Int {
        entries(h).filter { match($0.stuff) }.reduce(0) { $0 + $1.quantity }
    }
}
