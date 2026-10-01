import RFKernel

/// 名前の部品。命名は文字列を返さず、語の ID の並びを返す。
/// 最終の文字列化は `NameRendering` を差し替えて行う(認識の層: プレイヤーが知っている事実で見え方が変わる)。
public enum NamePart: Codable, Hashable, Sendable {
    /// 異常時の修飾(原作 Layer 3。純度 20% 未満の「粗悪な〜」)。
    case extreme(ExtremeModifier)
    /// 純度の段(原作 Layer 2 の接頭辞)。語はカテゴリで変わる(金属の「精」、粒状の「細」など)。
    /// 無修飾の段(45〜85%)と 20% 未満は部品を出さない。
    case grade(PurityGrade, MaterialCategory)
    /// 剛・柔・割れ。
    case temper(Temper)
    /// 固有名・慣用名(原作 Layer 0・1)。
    case proper(ProperNameID)
    /// 物質の名(原作 Layer 2 の基の名)。
    case substance(SubstanceID)
    /// 形の接尾辞。
    case shape(Shape)
}

/// 異常時の修飾。
public enum ExtremeModifier: String, Codable, Hashable, Sendable, CaseIterable {
    /// 粗悪な(純度 20% 未満。原作は 10% 未満も同じ語)。
    case poor
}

/// 純度の段。境目は原作 `NameGenerator.GetCategoryPrefix`(以上で上の段)。
public enum PurityGrade: String, Codable, Hashable, Sendable, CaseIterable {
    /// 20% 未満(接頭辞なし。異常時の修飾が付く)。
    case belowCrude
    /// 金属なら「粗」(20〜45%)。
    case crude
    /// 無修飾(45〜85%)。
    case standard
    /// 金属なら「精」(85〜98%)。
    case fine
    /// 金属なら「純」(98% 以上)。
    case pure

    /// 純度とカテゴリから段を決める。
    public static func of(_ p: Purity, category: MaterialCategory = .metal) -> PurityGrade {
        let bp = p.basisPoints
        switch category {
        case .chemical:
            // 希 / (なし) / 濃。原作は 20% 未満の段を持たない。
            if bp >= 9000 { return .fine }
            if bp >= 4500 { return .standard }
            return .crude
        case .organic:
            if bp >= 9500 { return .pure }
            if bp >= 8500 { return .fine }
        case .granular:
            if bp >= 9000 { return .pure }
            if bp >= 8500 { return .fine }
        case .metal, .liquid, .other:
            if bp >= 9800 { return .pure }
            if bp >= 8500 { return .fine }
        }
        if bp >= 4500 { return .standard }
        if bp >= 2000 { return .crude }
        return .belowCrude
    }
}

/// 接頭辞の語を分けるカテゴリ(原作 `MaterialCategory` のうち判定のあるもの)。
public enum MaterialCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case metal, organic, granular, liquid, chemical, other

    /// 原作 `GetMaterialCategory` の判定(物質 ID と、粒状は密度 < 3・硬度 < 3)。
    public static func of(_ id: SubstanceID, substances: SubstanceTable = .r1) -> MaterialCategory {
        if metals.contains(id) { return .metal }
        if liquids.contains(id) { return .liquid }
        if organics.contains(id) { return .organic }
        if let p = substances[id]?.properties, p.density < 3, p.hardness < 3 { return .granular }
        return .other
    }

    static let metals: Set<SubstanceID> = [
        "Fe", "Cu", "Sn", "Zn", "Ni", "Cr", "Ti", "Al", "Mn", "W", "Pb", "Ag", "Au", "Pt", "Co", "Mo", "U",
    ]
    static let liquids: Set<SubstanceID> = ["H2O", "H2SO4", "HNO3", "HCl_aq", "NaOH"]
    static let organics: Set<SubstanceID> = [
        "Cellulose", "Starch", "Protein", "DenatureProtein", "Lipid", "Glucose", "Ethanol", "AceticAcid",
    ]
}

/// 名前(部品の並び)。
public struct MatterName: Codable, Hashable, Sendable {
    public var parts: [NamePart]

    public init(_ parts: [NamePart]) { self.parts = parts }

    /// 文字列にする(語の表は差し替える側が持つ)。
    public func rendered(by renderer: some NameRendering) -> String { renderer.render(self) }

    /// 純度の段(部品に無ければ無修飾または 20% 未満)。
    public var grade: PurityGrade? {
        for case .grade(let g, _) in parts { return g }
        return nil
    }

    public var temper: Temper? {
        for case .temper(let t) in parts { return t }
        return nil
    }
}

/// 名前の部品を文字列にする役。認識の層・図鑑・テストがそれぞれ実装する。
public protocol NameRendering {
    func render(_ name: MatterName) -> String
}

/// 動的命名(原作 `NameGenerator` の 4 層)。文字列ではなく部品を返す。
///
/// - Layer 0: 固有名(鉄の炭素量・金・銀・素材×形・状態で変わる物質・鉱石)
/// - Layer 1: 条件付きの慣用名(粗銅・電気銅など)
/// - Layer 2: カテゴリ別の接頭辞(20〜45 粗 / 45〜85 無印 / 85〜98 精 / 98+ 純)と形の接尾辞
/// - Layer 3: 異常時の修飾(20% 未満の「粗悪な」)
/// 剛・柔・割れは原作の命名に無く、game-design.md §2 の名前(剛鉄板・柔鉄板)から R1 で足した。
public enum NameGenerator {
    /// 物質のインスタンスから名前の部品を作る。
    public static func name(for m: Matter, substances: SubstanceTable = .r1) -> MatterName {
        name(
            substance: m.substance, purity: m.purity, shape: m.shape,
            temper: m.stage == .metal ? m.temper : .none,
            carbon: m.share(of: .carbon), substances: substances)
    }

    /// 部品ごとの入口。`carbon` は鉄の炭素量(Layer 0 の鋼・純鉄の分け)。
    public static func name(
        substance id: SubstanceID, purity: Purity, shape: Shape?, temper: Temper = .none,
        carbon: Purity = .zero, substances: SubstanceTable = .r1
    ) -> MatterName {
        let temperPart: [NamePart] = temper == .none ? [] : [.temper(temper)]
        let shapePart: [NamePart] = shape.map { [.shape($0)] } ?? []

        // Layer 0
        switch properName(id, purity: purity, shape: shape, carbon: carbon, substances: substances) {
        case .some((let proper, let keepsShape)):
            return MatterName(temperPart + [.proper(proper)] + (keepsShape ? shapePart : []))
        case .none:
            break
        }

        // Layer 1
        if let conventional = conventionalName(id, purity: purity) {
            return MatterName(temperPart + [.proper(conventional)] + shapePart)
        }

        // Layer 2・3
        let category = MaterialCategory.of(id, substances: substances)
        let grade = PurityGrade.of(purity, category: category)
        var parts: [NamePart] = []
        if purity.basisPoints < 2000 { parts.append(.extreme(.poor)) }
        if grade == .crude || grade == .fine || grade == .pure { parts.append(.grade(grade, category)) }
        parts += temperPart
        parts.append(.substance(id))
        parts += shapePart
        return MatterName(parts)
    }

    // MARK: Layer 0

    /// 固有名と、形の接尾辞を残すか。
    static func properName(
        _ id: SubstanceID, purity: Purity, shape: Shape?, carbon: Purity, substances: SubstanceTable
    ) -> (ProperNameID, Bool)? {
        let p = purity.basisPoints
        // 鉄: 炭素量で名前が変わる。判定の順は原作のまま(銑鉄は鋼・硬鋼に先に取られて出ない)。
        if id == .iron {
            let c = carbon.basisPoints
            if c >= 200 && c < 214 { return (.steel, true) }
            if c >= 214 && c < 400 { return (.hardSteel, true) }
            if c < 25 && c >= 2 { return (.mildSteel, true) }
            if c >= 200 && c < 450 { return (.pigIron, true) }
            if c < 2 && p >= 9990 { return (.pureIron, true) }
        }
        if id == "Au" {
            if p >= 9999 { return (.pureGold, true) }
            if p >= 9100 && p < 9250 { return (.gold22k, true) }
            if p >= 7400 && p < 7600 { return (.gold18k, true) }
        }
        if id == "Ag" {
            if p >= 9990 { return (.pureSilver, true) }
            if p >= 9200 && p < 9300 { return (.sterlingSilver, true) }
        }
        // 素材 × 形の固有名(接尾辞は付けない)
        if let shape, let n = shapeProperNames[ShapeKey(substance: id, shape: shape)] { return (n, false) }
        // 純度・形で名前が変わる物質(原作の溶融・氷・蒸気の分岐は温度が要るので R2)
        if id == .silica {
            if p >= 9990 { return (.quartzGlass, false) }
            if shape == .dust { return (.silicaSand, false) }
        }
        if id == .carbon, substances[id]?.crystal == .diamond { return (.diamond, false) }
        if id == .water {
            if p >= 9999 { return (.pureWater, false) }
            if p >= 9900 { return (.distilledWater, false) }
        }
        // 鉱石。原作は接尾辞なしで返すが、R1 は塊と粉の違いが工程の鍵なので形を残す。
        if let ore = oreNames[id] { return (ore, true) }
        return nil
    }

    struct ShapeKey: Hashable { var substance: SubstanceID; var shape: Shape }

    static let shapeProperNames: [ShapeKey: ProperNameID] = [
        ShapeKey(substance: .iron, shape: .beam): .ironFrame,
        ShapeKey(substance: .iron, shape: .rod): .ironRod,
        ShapeKey(substance: .iron, shape: .wire): .ironWire,
        ShapeKey(substance: .iron, shape: .mesh): .wireMesh,
        ShapeKey(substance: "Au", shape: .film): .goldLeaf,
        ShapeKey(substance: "Cu", shape: .film): .copperFoil,
        ShapeKey(substance: "Ag", shape: .film): .silverLeaf,
        ShapeKey(substance: "Al", shape: .film): .aluminiumFoil,
    ]

    /// 鉱石の固有名(原作 `LookupOreName` のうち R1 の物質表にあるもの)。
    static let oreNames: [SubstanceID: ProperNameID] = [
        .hematite: .hematite,
        .magnetite: .magnetite,
        .calciumCarbonate: .limestone,
    ]

    // MARK: Layer 1

    /// 原作 `LookupConventionalName`。万分率では 99.999% を表せないので、
    /// 超高純度アルミの段は 100.00%(99.995% 以上が丸まる値)とする。
    static func conventionalName(_ id: SubstanceID, purity: Purity) -> ProperNameID? {
        let p = purity.basisPoints
        switch id {
        case "Cu":
            if p < 9900 { return .crudeCopper }
            if p >= 9996 { return .oxygenFreeCopper }
            if p >= 9990 { return .electrolyticCopper }
        case "Sn":
            if p < 9900 { return .crudeTin }
            if p >= 9999 { return .highPurityTin }
        case "Pb":
            if p < 9900 { return .crudeLead }
            if p >= 9999 { return .electrolyticLead }
        case "Al":
            if p >= 10000 { return .ultraPureAluminium }
            if p >= 9999 { return .highPurityAluminium }
        case "W":
            if p >= 9995 { return .sinteredTungsten }
        default:
            break
        }
        return nil
    }
}
