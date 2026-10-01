import RFKernel

/// 形(原作 `ShapeType`)。原作は列挙の値に基準質量(g)を入れていたが、保存の互換のため
/// 生の値は名前の文字列にし、質量は `baseMassGrams` で引く。生の値はケース名を変えても変えない。
public enum Shape: String, Codable, Hashable, Sendable, CaseIterable {
    // 大型
    case beam = "beam", panel = "panel", block = "block", thickPlate = "thick_plate"
    // 中型
    case plate = "plate", pipe = "pipe", thinPlate = "thin_plate", ingot = "ingot", rod = "rod"
    case brick = "brick", mesh = "mesh", wire = "wire", tile = "tile"
    // 小型
    case dust = "dust", film = "film", bolt = "bolt", pellet = "pellet"
    /// 不定形の塊(R1 で足した形)。掘ったままの鉱石と、炉から出たばかりの鉄の塊。
    /// 原作では鉱石に形がなく、鉄の塊は ingot(鋳塊)だった。R1 は鋳型がないので別にした。
    case lump = "lump"

    /// 基準質量 (g)。原作 `ShapeType` の値。
    public var baseMassGrams: Int {
        switch self {
        case .beam: 500_000
        case .panel: 200_000
        case .block: 100_000
        case .thickPlate: 80_000
        case .plate: 50_000
        case .pipe: 10_000
        case .thinPlate: 8_000
        case .ingot: 5_000
        case .rod: 4_000
        case .brick: 3_000
        case .mesh: 2_000
        case .wire: 1_000
        case .tile: 800
        case .dust: 100
        case .film: 50
        case .bolt: 30
        case .pellet: 10
        case .lump: 5_000
        }
    }
}

/// 物の段階。R1 は鉱石と金属。後の段階(液体・化合物など)は ID を足すだけで増やせる。
public struct MatterStage: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let ore: MatterStage = "ore"
    public static let metal: MatterStage = "metal"
}

/// 熱の状態。
public struct ThermalState: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// 熱していない(常温)。
    public static let ambient: ThermalState = "ambient"
    /// 炉から出て熱い(叩ける)。
    public static let hot: ThermalState = "hot"
    /// 叩いた後で冷めかけている(もう一度叩くには熱し直しが要る。急冷はできる)。
    public static let warm: ThermalState = "warm"
    /// 熱いうちに水で急に冷やした。
    public static let quenched: ThermalState = "quenched"
    /// 熱いまま空気でゆっくり冷えた。
    public static let airCooled: ThermalState = "air_cooled"
}

/// 硬さと粘りの性質(名前の剛・柔と、割れ)。
public struct Temper: StringIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// 特になし。
    public static let none: Temper = "none"
    /// 剛: 叩いた後に急冷した(硬い)。
    public static let hard: Temper = "hard"
    /// 柔: 叩いた後に急冷しなかった(粘る)。
    public static let soft: Temper = "soft"
    /// 割れ: 急冷の後に叩いた。
    public static let cracked: Temper = "cracked"
}

/// 物質のインスタンス(原作 `MatterInstance` の R1 版)。値型で、工程の 1 単位を表す。
///
/// 原作は組成の配列(全物質)から純度と主成分を計算していた。R1 は鉄の系統だけなので、
/// 主成分と純度を直接持ち、残りの組成は `components` に任意で持てる(合金・炭素量は R2)。
/// 加工で変わる特性は `traits` に上書き・加減として持つ。
public struct Matter: Codable, Hashable, Sendable {
    /// 主成分(鉱石なら Fe2O3、鉄なら Fe)。
    public var substance: SubstanceID
    /// 主成分の割合(純度)。
    public var purity: Purity
    public var stage: MatterStage
    public var shape: Shape
    public var thermal: ThermalState
    /// 叩き台で叩いた回数(1 = 板にした、2 以上 = 叩き重ねた)。
    public var worked: Int
    public var temper: Temper
    /// 混ぜてあるが、まだ効いていない混ぜ物(石灰石など)。並びは ID 順で重複なし。
    public var additives: [ItemID]
    /// 主成分以外の組成(任意。炭素量の名前分けや合金で使う)。
    public var components: [Component]
    /// 合金・物質の定義(任意)。
    public var alloy: AlloyID?
    /// 加工で変わった特性の値(上書き・加減。無ければ 0)。
    public var traits: [TraitID: Int]

    public init(
        substance: SubstanceID, purity: Purity, stage: MatterStage, shape: Shape,
        thermal: ThermalState = .ambient, worked: Int = 0, temper: Temper = .none,
        additives: [ItemID] = [], components: [Component] = [], alloy: AlloyID? = nil, traits: [TraitID: Int] = [:]
    ) {
        self.substance = substance
        self.purity = purity
        self.stage = stage
        self.shape = shape
        self.thermal = thermal
        self.worked = worked
        self.temper = temper
        self.additives = Array(Set(additives)).sorted()
        self.components = components
        self.alloy = alloy
        self.traits = traits
    }

    enum CodingKeys: String, CodingKey {
        case substance = "substance", purity = "purity", stage = "stage", shape = "shape"
        case thermal = "thermal", worked = "worked", temper = "temper", additives = "additives"
        case components = "components", alloy = "alloy", traits = "traits"
    }

    /// 読むときも混ぜ物の並びを正規化する(ID 順・重複なし)。純度が 0...10000 の外なら黙って丸めずに throw する。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let bp = try c.decode(Int.self, forKey: .purity)
        guard (0...10000).contains(bp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .purity, in: c, debugDescription: "純度が 0...10000 の外: \(bp)")
        }
        self.init(
            substance: try c.decode(SubstanceID.self, forKey: .substance),
            purity: Purity(basisPoints: bp),
            stage: try c.decode(MatterStage.self, forKey: .stage),
            shape: try c.decode(Shape.self, forKey: .shape),
            thermal: try c.decode(ThermalState.self, forKey: .thermal),
            worked: try c.decode(Int.self, forKey: .worked),
            temper: try c.decode(Temper.self, forKey: .temper),
            additives: try c.decode([ItemID].self, forKey: .additives),
            components: try c.decode([Component].self, forKey: .components),
            alloy: try c.decodeIfPresent(AlloyID.self, forKey: .alloy),
            traits: try c.decode([TraitID: Int].self, forKey: .traits))
    }

    /// 掘ったままの鉄鉱石(塊)。
    public static func ironOre(purity: Purity) -> Matter {
        Matter(substance: .hematite, purity: purity, stage: .ore, shape: .lump)
    }

    /// ある物質の割合(主成分なら純度、それ以外は `components` から)。
    public func share(of id: SubstanceID) -> Purity {
        if id == substance { return purity }
        return components.first { $0.substance == id }?.share ?? .zero
    }

    /// 特性の値(無ければ 0)。
    public func trait(_ id: TraitID) -> Int { traits[id] ?? 0 }

    mutating func addAdditive(_ item: ItemID) {
        if !additives.contains(item) { additives = (additives + [item]).sorted() }
    }
}
