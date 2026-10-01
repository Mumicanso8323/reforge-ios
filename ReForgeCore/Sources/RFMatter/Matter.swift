/// 形(原作 `ShapeType`)。原作は列挙の値に基準質量(g)を入れていたが、保存の互換のため
/// 生の値は名前の文字列にし、質量は `baseMassGrams` で引く。
public enum Shape: String, Codable, Hashable, Sendable, CaseIterable {
    // 大型
    case beam, panel, block, thickPlate
    // 中型
    case plate, pipe, thinPlate, ingot, rod, brick, mesh, wire, tile
    // 小型
    case dust, film, bolt, pellet
    /// 不定形の塊(R1 で足した形)。掘ったままの鉱石と、炉から出たばかりの鉄の塊。
    /// 原作では鉱石に形がなく、鉄の塊は ingot(鋳塊)だった。R1 は鋳型がないので別にした。
    case lump

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

/// 物の段階。鉱石は炉で溶けて初めて鉄(金属)になる。
public enum MatterStage: String, Codable, Hashable, Sendable, CaseIterable {
    case ore
    case metal
}

/// 熱の状態。
public enum ThermalState: String, Codable, Hashable, Sendable, CaseIterable {
    /// 熱していない(常温)。
    case ambient
    /// 炉から出て熱い。
    case hot
    /// 熱いうちに水で急に冷やした。
    case quenched
    /// 熱いまま空気でゆっくり冷えた。
    case airCooled
}

/// 硬さと粘りの性質(名前の剛・柔と、割れ)。
public enum Temper: String, Codable, Hashable, Sendable, CaseIterable {
    /// 特になし。
    case none
    /// 剛: 叩いた後に急冷した(硬い)。
    case hard
    /// 柔: 叩いた後に急冷しなかった(粘る)。
    case soft
    /// 割れ: 急冷の後に叩いた。
    case cracked
}

/// 物質のインスタンス(原作 `MatterInstance` の R1 版)。値型で、工程の 1 単位を表す。
///
/// 原作は組成の配列(全物質)から純度と主成分を計算していた。R1 は鉄の系統だけなので、
/// 主成分と純度を直接持ち、残りの組成は `components` に任意で持てる(合金・炭素量は R2)。
public struct Matter: Codable, Hashable, Sendable {
    /// 主成分(鉱石なら Fe2O3、鉄なら Fe)。
    public var substance: SubstanceID
    /// 主成分の割合(純度)。
    public var purity: Purity
    public var stage: MatterStage
    public var shape: Shape
    public var thermal: ThermalState
    /// 叩き台で叩かれたか。
    public var worked: Bool
    public var temper: Temper
    /// 混ぜてあるが、まだ効いていない混ぜ物(石灰石など)。並びは ID 順。
    public var additives: [ItemID]
    /// 主成分以外の組成(任意。炭素量の名前分けや合金で使う)。
    public var components: [Component]
    /// 合金・物質の定義(任意)。
    public var alloy: AlloyID?

    public init(
        substance: SubstanceID, purity: Purity, stage: MatterStage, shape: Shape,
        thermal: ThermalState = .ambient, worked: Bool = false, temper: Temper = .none,
        additives: [ItemID] = [], components: [Component] = [], alloy: AlloyID? = nil
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

    mutating func addAdditive(_ item: ItemID) {
        if !additives.contains(item) { additives = (additives + [item]).sorted() }
    }
}
