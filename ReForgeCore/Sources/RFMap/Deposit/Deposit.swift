/// 鉱脈の ID(層の中で一意)。
public struct DepositID: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }
    public static func < (a: DepositID, b: DepositID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }

    /// 岩山の手前の露頭(最初に触れる鉄の鉱脈)。
    public static let outcrop = DepositID("deposit.outcrop")
}

/// 鉱脈の種類(原作 `Deposit.Category`)。R1 の地図に出るのは表層〜混合・希少まで。
public enum DepositCategory: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case iron, copper, coal, mixed, rare
    /// 土石(石材・砂・石灰石・粘土)
    case quarry
}

/// 物質の ID(化学式。例 "Fe2O3")。
public struct SubstanceID: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ raw: String) { self.rawValue = raw }
    public static func < (a: SubstanceID, b: SubstanceID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }

    public static let fe2o3 = SubstanceID("Fe2O3")
    public static let feS = SubstanceID("FeS")
    public static let fe = SubstanceID("Fe")
    public static let cu = SubstanceID("Cu")
    public static let cuS = SubstanceID("CuS")
    public static let cu2o = SubstanceID("Cu2O")
    public static let sio2 = SubstanceID("SiO2")
    public static let carbon = SubstanceID("C")
    public static let sno2 = SubstanceID("SnO2")
    public static let znS = SubstanceID("ZnS")
    public static let ag = SubstanceID("Ag")
    public static let au = SubstanceID("Au")
    public static let pt = SubstanceID("Pt")
}

/// 元素(採掘の産出を決めるのに使うものだけ)。
public enum Element: String, Codable, CaseIterable, Sendable {
    case fe, cu, c, si, sn, zn, ag, au, pt

    /// 物質の中の元素の質量比(万分率。原作 `EstimateElementFraction`)。
    static func share(of element: Element, in substance: SubstanceID) -> Int {
        switch (element, substance.rawValue) {
        case (.fe, "Fe2O3"): return 7000
        case (.fe, "FeS"): return 6400
        case (.fe, "Fe"): return 10000
        case (.cu, "Cu"): return 10000
        case (.cu, "CuS"): return 6700
        case (.cu, "Cu2O"): return 8900
        case (.si, "SiO2"): return 4700
        case (.c, "C"): return 10000
        case (.sn, "SnO2"): return 7900
        case (.zn, "ZnS"): return 6700
        case (.ag, "Ag"): return 10000
        case (.au, "Au"): return 10000
        case (.pt, "Pt"): return 10000
        default: return 0
        }
    }
}

/// 鉱脈の組成の 1 成分。
public struct DepositComponent: Codable, Equatable, Hashable, Sendable {
    public var substance: SubstanceID
    public var share: Purity

    public init(_ substance: SubstanceID, _ share: Purity) {
        self.substance = substance
        self.share = share
    }
}

/// 1 回の採掘で出るもの。item は内部の品目 ID(原作と同じ。例 "iron_ore")。
public struct OreYield: Codable, Equatable, Hashable, Sendable {
    public var item: String
    public var quantity: Int
    public var purity: Purity

    public init(item: String, quantity: Int, purity: Purity) {
        self.item = item
        self.quantity = quantity
        self.purity = purity
    }
}

/// 有限の鉱脈(原作 `Deposit`)。地図のマスに 1 つ。掘るたびに残り回数が減り、0 で枯れる。
/// 表示名(見た目の仮名・正式名)は持たない。見た目の候補の番号 `appearanceVariant` だけを持つ。
public struct Deposit: Codable, Equatable, Sendable {
    public let id: DepositID
    public let position: GridPoint
    public let category: DepositCategory
    /// 見た目の候補の番号(原作の種類ごとの見た目の名前の並びの何番目か)。名前は Perception 層が引く。
    public let appearanceVariant: Int
    public let composition: [DepositComponent]
    /// 生成したときの採掘可能回数。
    public let initialExtractions: Int
    /// 残りの採掘回数。
    public internal(set) var remainingExtractions: Int
    /// いまの採掘の深さ [m]。1 回掘るごとに +1。
    public internal(set) var depth: Int
    /// 視界に入ったことがあるか。
    public var isDiscovered: Bool
    /// 分析済みか。
    public var isAnalyzed: Bool

    public init(id: DepositID, position: GridPoint, category: DepositCategory, appearanceVariant: Int,
                composition: [DepositComponent], extractions: Int, depth: Int = 0,
                isDiscovered: Bool = false, isAnalyzed: Bool = false) {
        self.id = id
        self.position = position
        self.category = category
        self.appearanceVariant = appearanceVariant
        self.composition = composition
        self.initialExtractions = extractions
        self.remainingExtractions = extractions
        self.depth = depth
        self.isDiscovered = isDiscovered
        self.isAnalyzed = isAnalyzed
    }

    public var isDepleted: Bool { remainingExtractions <= 0 }

    /// 鉱脈の純度 = 主な鉱物の割合(鉄なら Fe2O3、銅なら CuS + Cu2O、石炭なら C、土石なら SiO2)。
    public var purity: Purity {
        let primary: Set<SubstanceID>
        switch category {
        case .iron, .mixed, .rare: primary = [.fe2o3]
        case .copper: primary = [.cuS, .cu2o]
        case .coal: primary = [.carbon]
        case .quarry: primary = [.sio2]
        }
        return Purity(basisPoints: composition.filter { primary.contains($0.substance) }.reduce(0) { $0 + $1.share.basisPoints })
    }

    /// 物質の割合。
    public func share(of substance: SubstanceID) -> Purity {
        Purity(basisPoints: composition.filter { $0.substance == substance }.reduce(0) { $0 + $1.share.basisPoints })
    }

    /// 元素の含有率(組成と質量比から)。
    public func content(of element: Element) -> Purity {
        var total = 0
        for c in composition {
            total += c.share.basisPoints * Element.share(of: element, in: c.substance) / 10000
        }
        return Purity(basisPoints: total)
    }

    /// 深さによる補正(原作 DT5 の 4 層。金属・脈石への万分率の加減)。
    public static func depthModifiers(depth: Int) -> (metal: Int, gangue: Int) {
        switch depth {
        case ...10: return (-1000, 500)
        case ...50: return (0, 0)
        case ...100: return (1500, -500)
        default: return (2500, -1000)
        }
    }

    private static func modified(_ p: Purity, _ mod: Int) -> Purity {
        Purity(basisPoints: min(10000, max(0, p.basisPoints * (10000 + mod) / 10000)))
    }

    /// 1 回掘る(原作 `ExtractOre`)。枯れていれば何も出ず、状態も変わらない。
    /// 確率の判定はすべて渡された乱数で行う(原作は呼ぶたびに新しい Random を作っていた)。
    public mutating func extract(rng: inout SeededRandom) -> [OreYield] {
        guard remainingExtractions > 0 else { return [] }
        remainingExtractions -= 1
        depth += 1

        var out: [OreYield] = []
        func add(_ item: String, _ q: Int, _ p: Purity) { out.append(OreYield(item: item, quantity: q, purity: p)) }

        if category == .quarry {
            add("stone", 2 + rng.int(below: 2), .full)
            if rng.chance(percent: 50) { add("sand", 1 + rng.int(below: 2), .full) }
            if rng.chance(percent: 30) { add("limestone", 1, .full) }
            if rng.chance(percent: 25) { add("clay", 1 + rng.int(below: 2), .full) }
            return out
        }

        let mod = Self.depthModifiers(depth: depth)
        let fe = Self.modified(content(of: .fe), mod.metal)
        if fe.basisPoints > 500 { add("iron_ore", 2 + (fe.basisPoints > 3000 ? 1 : 0), fe) }
        let cu = Self.modified(content(of: .cu), mod.metal)
        if cu.basisPoints > 300 { add("copper_ore", 1 + (cu.basisPoints > 2000 ? 1 : 0), cu) }
        let c = content(of: .c)
        if c.basisPoints > 3000 { add("coal", 2 + (c.basisPoints > 7000 ? 1 : 0), c) }
        let si = Self.modified(content(of: .si), mod.gangue)
        if si.basisPoints > 1000 {
            add("stone", 1, .full)
            if depth >= 10 && rng.chance(percent: 20) { add("quartz", 1, si) }
        }
        let sn = content(of: .sn)
        if sn.basisPoints > 300 { add("tin_ore", 1 + (sn.basisPoints > 2000 ? 1 : 0), sn) }
        let ag = content(of: .ag)
        if ag.basisPoints > 100 { add("trace_silver", 1, ag) }

        if depth >= 8 && rng.chance(percent: 25) {
            add("titanium_ore", 1, Purity(basisPoints: 3500 + depth * 20))
        }
        if depth >= 20 && rng.chance(percent: 12) {
            let table: [(String, Int)] = [("lead_ore", 5000), ("manganese_ore", 4500), ("zinc_ore", 5500), ("bauxite", 4000)]
            let t = table[rng.int(below: table.count)]
            add(t.0, 1, Purity(basisPoints: t.1))
        }
        if depth >= 50 && depth < 100 && rng.chance(percent: 15) {
            let table: [(String, Int)] = [("silver_ore", 4000), ("gold_ore", 3000), ("chromium_ore", 4500),
                                          ("titanium_ore", 3500), ("aluminum_ore", 5000), ("tungsten_ore", 3000)]
            let t = table[rng.int(below: table.count)]
            add(t.0, 1, Purity(basisPoints: t.1))
        }
        if depth >= 100 && rng.chance(percent: 20) {
            let table: [(String, Int)] = [("platinum_ore", 5000), ("gold_ore", 6000), ("uranium_ore", 4000),
                                          ("cobalt_ore", 5500), ("nickel_ore", 5000)]
            let t = table[rng.int(below: table.count)]
            add(t.0, 1, Purity(basisPoints: t.1))
        }
        if out.isEmpty { add("stone", 2, .full) }
        return out
    }
}
