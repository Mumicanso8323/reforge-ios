/// 物質の 18 特性(原作 `Matter/Property.cs` の Property レコード)。
/// 物理定数なので浮動小数で持つ。工程の判定(純度・名前・硬さ)には使わない(R2 の装備反映で使う)。
public struct MatterProperties: Codable, Hashable, Sendable {
    /// 原作 `PropertyMath.INF`(1×10⁻⁸)。値がないことを 0 と区別するための微小値。
    public static let infinitesimal = 0.000_000_01

    /// 1 密度 (g/cm³)
    public var density: Double
    /// 2 融点 (K)
    public var meltingPoint: Double?
    /// 3 沸点 (K)
    public var boilingPoint: Double?
    /// 4 プラズマ化温度 (K)
    public var plasmaPoint: Double?
    /// 5 原子量 (u)
    public var atomicMass: Double
    /// 6 イオン化エネルギー (kJ/mol)
    public var ionizationEnergy: Double?
    /// 7 電子親和力 (kJ/mol)
    public var electronAffinity: Double?
    /// 8 電気陰性度 (Pauling)
    public var electronegativity: Double?
    /// 9 原子半径 (pm)
    public var atomicRadius: Double?
    /// 10 熱伝導率 (W/m·K)
    public var thermalConductivity: Double
    /// 11 電気伝導率 (S/m)
    public var electricalConductivity: Double
    /// 12 比熱容量 (J/g·K)
    public var specificHeatCapacity: Double
    /// 13 耐食性 (0〜10)
    public var corrosionResistance: Double
    /// 14 反応性 (0〜10)
    public var reactivityLevel: Double
    /// 15 硬度(モース相当)
    public var hardness: Double
    /// 16 放射能レベル
    public var radioactivityLevel: Double
    /// 17 幻覚効果レベル(R1 では使わない)
    public var illusionEffectLevel: Double
    /// 18 次元シフトの度合い(R1 では使わない)
    public var dimensionalShiftPotential: Double

    public init(
        density: Double, meltingPoint: Double?, boilingPoint: Double?, plasmaPoint: Double?, atomicMass: Double,
        ionizationEnergy: Double?, electronAffinity: Double?, electronegativity: Double?, atomicRadius: Double?,
        thermalConductivity: Double, electricalConductivity: Double, specificHeatCapacity: Double,
        corrosionResistance: Double, reactivityLevel: Double, hardness: Double,
        radioactivityLevel: Double = MatterProperties.infinitesimal,
        illusionEffectLevel: Double = MatterProperties.infinitesimal,
        dimensionalShiftPotential: Double = MatterProperties.infinitesimal
    ) {
        self.density = density
        self.meltingPoint = meltingPoint
        self.boilingPoint = boilingPoint
        self.plasmaPoint = plasmaPoint
        self.atomicMass = atomicMass
        self.ionizationEnergy = ionizationEnergy
        self.electronAffinity = electronAffinity
        self.electronegativity = electronegativity
        self.atomicRadius = atomicRadius
        self.thermalConductivity = thermalConductivity
        self.electricalConductivity = electricalConductivity
        self.specificHeatCapacity = specificHeatCapacity
        self.corrosionResistance = corrosionResistance
        self.reactivityLevel = reactivityLevel
        self.hardness = hardness
        self.radioactivityLevel = radioactivityLevel
        self.illusionEffectLevel = illusionEffectLevel
        self.dimensionalShiftPotential = dimensionalShiftPotential
    }
}

/// 結晶構造(原作 `Crystals`。R1 で使う実在のものだけ)。
public enum CrystalStructure: String, Codable, Hashable, Sendable, CaseIterable {
    case fcc, bcc, cubic, hexagonal, hcp, tetragonal, orthorhombic, oblique, rhombohedral
    case monoclinic, triclinic, diamond, covalent, inverseSpinel, liquid
}

/// 磁気秩序(原作 `Magnetics`)。
public enum MagneticOrdering: String, Codable, Hashable, Sendable, CaseIterable {
    case para, dia, ferro, antiferro, ferri, nonMagnetic, unknown
}

/// 物理的な状態(原作 `States`)。
public enum PhysicalState: String, Codable, Hashable, Sendable, CaseIterable {
    case solid, liquid, gas, plasma
}

/// 物質の定義(原作 `Substance`)。表示名は持たない(認識の層が ID から引く)。
public struct Substance: Codable, Hashable, Sendable, Identifiable {
    public var id: SubstanceID
    public var properties: MatterProperties
    public var crystal: CrystalStructure
    public var magnetic: MagneticOrdering

    public init(id: SubstanceID, properties: MatterProperties, crystal: CrystalStructure, magnetic: MagneticOrdering) {
        self.id = id
        self.properties = properties
        self.crystal = crystal
        self.magnetic = magnetic
    }

    /// 状態(原作 `MatterInstance.State`。温度 K から判定)。
    public func state(atKelvin t: Double) -> PhysicalState {
        if let p = properties.plasmaPoint, t >= p { return .plasma }
        if let b = properties.boilingPoint, t >= b { return .gas }
        if let m = properties.meltingPoint, t >= m { return .liquid }
        return .solid
    }
}

/// 物質の表。R1 は鉄の系統と、工程に出てくる物質だけ。値は原作 `SubstanceDatabase.cs`
/// (炭酸カルシウムだけは原作に無いので R1 で足した実在の値)。
public struct SubstanceTable: Codable, Hashable, Sendable {
    public var substances: [SubstanceID: Substance]

    public init(_ list: [Substance]) {
        substances = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    public subscript(_ id: SubstanceID) -> Substance? { substances[id] }

    public static let r1 = SubstanceTable([
        Substance(
            id: .iron,
            properties: .init(
                density: 7.874, meltingPoint: 1811, boilingPoint: 3134, plasmaPoint: 8500, atomicMass: 55.845,
                ionizationEnergy: 762.5, electronAffinity: 15.7, electronegativity: 1.83, atomicRadius: 126,
                thermalConductivity: 80.4, electricalConductivity: 1.0e7, specificHeatCapacity: 0.449,
                corrosionResistance: 3.0, reactivityLevel: 7.0, hardness: 6.0),
            crystal: .bcc, magnetic: .ferro),
        Substance(
            id: .carbon,
            properties: .init(
                density: 2.267, meltingPoint: 3823, boilingPoint: 4098, plasmaPoint: 10800, atomicMass: 12.011,
                ionizationEnergy: 1086.5, electronAffinity: 153.9, electronegativity: 2.55, atomicRadius: 70,
                thermalConductivity: 140.0, electricalConductivity: MatterProperties.infinitesimal,
                specificHeatCapacity: 0.709, corrosionResistance: 7.0, reactivityLevel: 4.0, hardness: 10.0),
            crystal: .hexagonal, magnetic: .dia),
        Substance(
            id: .graphite,
            properties: .init(
                density: 2.267, meltingPoint: 3823, boilingPoint: 4098, plasmaPoint: 10800, atomicMass: 12.011,
                ionizationEnergy: 1086.5, electronAffinity: 153.9, electronegativity: 2.55, atomicRadius: 70,
                thermalConductivity: 140.0, electricalConductivity: 2.5e5, specificHeatCapacity: 0.709,
                corrosionResistance: 7.0, reactivityLevel: 4.0, hardness: 1.0),
            crystal: .hexagonal, magnetic: .dia),
        Substance(
            id: .hematite,
            properties: .init(
                density: 5.24, meltingPoint: 1816, boilingPoint: nil, plasmaPoint: 8500, atomicMass: 159.69,
                ionizationEnergy: 1562, electronAffinity: 15.7, electronegativity: 1.83, atomicRadius: 126,
                thermalConductivity: 2.5, electricalConductivity: MatterProperties.infinitesimal,
                specificHeatCapacity: 0.63, corrosionResistance: 7.0, reactivityLevel: 4.0, hardness: 6.5),
            crystal: .rhombohedral, magnetic: .antiferro),
        Substance(
            id: .magnetite,
            properties: .init(
                density: 5.17, meltingPoint: 1597, boilingPoint: 2623, plasmaPoint: 8500, atomicMass: 231.533,
                ionizationEnergy: 1562, electronAffinity: 15.7, electronegativity: 1.83, atomicRadius: 126,
                thermalConductivity: 5.0, electricalConductivity: MatterProperties.infinitesimal,
                specificHeatCapacity: 0.63, corrosionResistance: 6.0, reactivityLevel: 5.0, hardness: 5.5),
            crystal: .inverseSpinel, magnetic: .ferri),
        Substance(
            id: .silica,
            properties: .init(
                density: 2.65, meltingPoint: 1713, boilingPoint: 2230, plasmaPoint: nil, atomicMass: 60.08,
                ionizationEnergy: nil, electronAffinity: nil, electronegativity: nil, atomicRadius: nil,
                thermalConductivity: 1.4, electricalConductivity: 1.0e-13, specificHeatCapacity: 0.703,
                corrosionResistance: 9.0, reactivityLevel: 2.0, hardness: 7.0),
            crystal: .covalent, magnetic: .nonMagnetic),
        Substance(
            id: .calciumCarbonate,
            properties: .init(
                density: 2.71, meltingPoint: 1612, boilingPoint: nil, plasmaPoint: nil, atomicMass: 100.09,
                ionizationEnergy: nil, electronAffinity: nil, electronegativity: nil, atomicRadius: nil,
                thermalConductivity: 2.7, electricalConductivity: 1.0e-12, specificHeatCapacity: 0.834,
                corrosionResistance: 4.0, reactivityLevel: 4.0, hardness: 3.0),
            crystal: .rhombohedral, magnetic: .dia),
    ])
}

/// 組成の 1 成分(物質と割合)。
public struct Component: Codable, Hashable, Sendable {
    public var substance: SubstanceID
    public var share: Purity

    public init(_ substance: SubstanceID, _ share: Purity) {
        self.substance = substance
        self.share = share
    }
}

/// 合金・物質の定義(原作 `Alloy`)。組成のパターンを複数持てる。R1 は鉄の系統だけを入れる。
public struct AlloyDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: AlloyID
    /// 単一物質でない混合物か。
    public var isAlloy: Bool
    /// 組成のパターン(各パターンの割合の合計は 100%)。
    public var compositions: [[Component]]

    public init(id: AlloyID, isAlloy: Bool, compositions: [[Component]]) {
        self.id = id
        self.isAlloy = isAlloy
        self.compositions = compositions
    }

    /// 原作 `AlloyDatabase.cs` の鉄の系統。
    public static let r1: [AlloyDefinition] = [
        .init(id: .iron, isAlloy: false, compositions: [[Component(.iron, .full)]]),
        .init(id: .hematite, isAlloy: false, compositions: [[Component(.hematite, .full)]]),
        .init(id: .castIron, isAlloy: true,
              compositions: [[Component(.iron, Purity(percent: 95)), Component(.carbon, Purity(percent: 5))]]),
        .init(id: .carbonSteel, isAlloy: true,
              compositions: [[Component(.iron, Purity(percent: 98)), Component(.carbon, Purity(percent: 2))]]),
    ]
}
