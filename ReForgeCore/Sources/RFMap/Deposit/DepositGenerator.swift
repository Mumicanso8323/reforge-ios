/// 鉱脈の生成(原作 `DepositGenerator`)。組成の幅と採掘回数の幅は原作のまま、乱数だけを渡されたものにする。
public enum DepositGenerator {
    /// 種類ごとの見た目の候補の数(原作の見た目の名前の並びの長さ)。
    public static func appearanceCount(_ c: DepositCategory) -> Int {
        c == .quarry ? 4 : 3
    }

    /// 種類ごとの採掘回数の幅。
    public static func extractionRange(_ c: DepositCategory) -> ClosedRange<Int> {
        switch c {
        case .iron: return 30...70
        case .copper: return 20...50
        case .coal: return 40...80
        case .mixed: return 25...50
        case .rare: return 15...35
        case .quarry: return 50...100
        }
    }

    /// 鉱脈を 1 つ作る。
    /// - Parameters:
    ///   - primaryPercent: 主な鉱物の割合(%)を幅で指定し直す(岩山の露頭の 20〜35% など)。nil なら原作の幅。
    ///   - appearanceVariant: 見た目を固定したいとき(川岸の粘土 = 土石の 3 番など)。
    public static func make(id: DepositID, at position: GridPoint, category: DepositCategory,
                            rng: inout SeededRandom, primaryPercent: ClosedRange<Int>? = nil,
                            appearanceVariant: Int? = nil) -> Deposit {
        func pct(_ r: ClosedRange<Int>) -> Int { rng.int(in: r) * 100 }
        var parts: [(SubstanceID, Int)]
        switch category {
        case .iron:
            parts = [(.fe2o3, pct(primaryPercent ?? 35...60)), (.sio2, pct(20...35)), (.feS, pct(0...5)), (.cu, pct(0...3))]
        case .copper:
            parts = [(.cuS, pct(primaryPercent ?? 25...45)), (.cu2o, pct(5...20)), (.sio2, pct(20...35)), (.fe, pct(0...5))]
        case .coal:
            parts = [(.carbon, pct(primaryPercent ?? 55...85)), (.sio2, pct(5...15)), (.feS, pct(0...5))]
        case .mixed:
            parts = [(.fe2o3, pct(primaryPercent ?? 15...30)), (.cuS, pct(10...25)), (.sno2, pct(5...15)),
                     (.znS, pct(5...15)), (.sio2, pct(15...25))]
        case .rare:
            parts = [(.fe2o3, pct(primaryPercent ?? 20...35)), (.cuS, pct(10...20)), (.sio2, pct(20...35)),
                     (.ag, pct(1...4)), (.au, pct(1...2)), (.pt, pct(0...1))]
        case .quarry:
            parts = [(.sio2, 8000)]
        }
        // 合計が 100% を超えたら比で縮める(原作の Normalize)
        let total = parts.reduce(0) { $0 + $1.1 }
        if total > 10000 {
            parts = parts.map { ($0.0, $0.1 * 10000 / total) }
        }
        let composition = parts.filter { $0.1 > 0 }.map { DepositComponent($0.0, Purity(basisPoints: $0.1)) }
        let extractions = rng.int(in: extractionRange(category))
        let variant = appearanceVariant ?? rng.int(below: appearanceCount(category))
        return Deposit(id: id, position: position, category: category, appearanceVariant: variant,
                       composition: composition, extractions: extractions)
    }

    /// ランダムな種類の鉱脈(原作 `RollCategory` の確率: 鉄 40・銅 15・石炭 15・土石 15・混合 10・希少 5)。
    public static func rollCategory(rng: inout SeededRandom) -> DepositCategory {
        switch rng.int(below: 100) {
        case ..<25: return .iron
        case ..<40: return .copper
        case ..<55: return .coal
        case ..<70: return .quarry
        case ..<80: return .mixed
        case ..<95: return .iron
        default: return .rare
        }
    }
}

/// 層の鉱脈の集まり。1 マスに 1 つまで。
public struct DepositLayer: Codable, Equatable, Sendable {
    public private(set) var deposits: [DepositID: Deposit] = [:]
    private var byPosition: [GridPoint: DepositID] = [:]

    public init() {}

    public var all: [Deposit] { deposits.keys.sorted().map { deposits[$0]! } }
    public var count: Int { deposits.count }

    public subscript(id: DepositID) -> Deposit? { deposits[id] }

    public func deposit(at p: GridPoint) -> Deposit? { byPosition[p].flatMap { deposits[$0] } }

    public func hasDeposit(at p: GridPoint) -> Bool { byPosition[p] != nil }

    /// 加える。同じマスか同じ ID が既にあれば加えずに false。
    @discardableResult
    public mutating func add(_ d: Deposit) -> Bool {
        guard deposits[d.id] == nil, byPosition[d.position] == nil else { return false }
        deposits[d.id] = d
        byPosition[d.position] = d.id
        return true
    }

    /// 1 回掘る。鉱脈が無いか枯れていれば nil。
    public mutating func extract(_ id: DepositID, rng: inout SeededRandom) -> [OreYield]? {
        guard var d = deposits[id], !d.isDepleted else { return nil }
        let y = d.extract(rng: &rng)
        deposits[id] = d
        return y
    }

    /// 発見・分析などの状態を書き換える(位置と組成は変えない)。
    public mutating func update(_ id: DepositID, _ body: (inout Deposit) -> Void) {
        guard var d = deposits[id] else { return }
        body(&d)
        precondition(d.position == deposits[id]!.position, "鉱脈の位置は変えない")
        deposits[id] = d
    }

    private enum CodingKeys: String, CodingKey { case deposits }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for d in try c.decode([Deposit].self, forKey: .deposits) {
            guard add(d) else {
                throw DecodingError.dataCorruptedError(forKey: .deposits, in: c, debugDescription: "鉱脈が重なっている: \(d.id)")
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(all, forKey: .deposits)
    }

    public static func == (a: DepositLayer, b: DepositLayer) -> Bool { a.deposits == b.deposits }
}
