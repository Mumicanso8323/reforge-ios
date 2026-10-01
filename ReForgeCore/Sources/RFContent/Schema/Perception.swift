import RFKernel
import RFMatter

// 認識の表(D: Perception-Truth)。真実の ID(SubjectID)ごとに、知っている事実に応じた見え方を並べる。
// 上から順に when を調べ、最初に成り立った見え方を使う。最後の行は when = true(既定の見え方)にする(検証で確かめる)。
//
// 見出しの名前の付け方(コンテンツ全体の約束): 「名前空間:ID」。作るときは Subject の関数を使う。
//   item:iron_ore / module:furnace / structure:shelter / terrain:grass / poi:wreck / person:<id> / finding:<id>
//   名前の部品: substance:Fe / shape:plate / grade:fine.metal / temper:hard / proper:steel / extreme:poor
//   ノートの出典・地図のラベル・数値の見せ方(stat:<id>)・工程表(sheet:<id>)も見出しを持つ。

/// 見出しの作り方(名前空間の約束を 1 か所に)。
public enum Subject {
    public static func item(_ id: ItemID) -> SubjectID { SubjectID("item:\(id.rawValue)") }
    public static func module(_ id: ModuleKindID) -> SubjectID { SubjectID("module:\(id.rawValue)") }
    public static func structure(_ id: StructureKindID) -> SubjectID { SubjectID("structure:\(id.rawValue)") }
    public static func terrain(_ id: TerrainID) -> SubjectID { SubjectID("terrain:\(id.rawValue)") }
    public static func poi(_ id: POIKindID) -> SubjectID { SubjectID("poi:\(id.rawValue)") }
    public static func person(_ id: PersonID) -> SubjectID { SubjectID("person:\(id.rawValue)") }
    public static func finding(_ id: FindingID) -> SubjectID { SubjectID("finding:\(id.rawValue)") }
    public static func stat(_ id: StatID) -> SubjectID { SubjectID("stat:\(id.rawValue)") }
    public static func enemy(_ id: EnemyKindID) -> SubjectID { SubjectID("enemy:\(id.rawValue)") }
    public static func sheet(_ id: SheetID) -> SubjectID { SubjectID("sheet:\(id.rawValue)") }
    public static func research(_ id: ResearchID) -> SubjectID { SubjectID("research:\(id.rawValue)") }
    public static func ability(_ id: AbilityID) -> SubjectID { SubjectID("ability:\(id.rawValue)") }

    /// 物質の名前の部品 1 つの見出し。
    public static func namePart(_ p: NamePart) -> SubjectID {
        switch p {
        case .extreme(let e): SubjectID("extreme:\(e.rawValue)")
        case .grade(let g, let c): SubjectID("grade:\(g.rawValue).\(c.rawValue)")
        case .temper(let t): SubjectID("temper:\(t.rawValue)")
        case .proper(let id): SubjectID("proper:\(id.rawValue)")
        case .substance(let id): SubjectID("substance:\(id.rawValue)")
        case .shape(let s): SubjectID("shape:\(s.rawValue)")
        }
    }
}

public struct SubjectDef: Codable, Equatable, Sendable {
    public var subject: SubjectID
    public var variants: [Variant]

    public init(subject: SubjectID, variants: [Variant]) {
        self.subject = subject
        self.variants = variants
    }
}

extension SubjectDef: ContentDef {
    public var id: SubjectID { subject }
}

public struct Variant: Codable, Equatable, Sendable {
    public var when: FactExpr
    public var name: TextID?
    public var description: TextID?
    /// 数値の見せ方(数値の見出しのときだけ)。
    public var display: StatDisplay?
    /// 地図の文字(地形・POI の見え方が変わるときだけ)。
    public var glyph: String?
    /// この見え方に切り替わったとき、画面で「書き換わった」と知らせるか。
    public var announce: Bool?

    public init(when: FactExpr, name: TextID? = nil, description: TextID? = nil, display: StatDisplay? = nil,
                glyph: String? = nil, announce: Bool? = nil) {
        self.when = when
        self.name = name
        self.description = description
        self.display = display
        self.glyph = glyph
        self.announce = announce
    }
}

/// 数値の見せ方。
public enum StatDisplay: Codable, Equatable, Sendable {
    /// 見せない(隠れた値)。
    case hidden
    /// 段階の言葉で(しきい値の昇順。値がしきい値以上なら、その言葉)。
    case bands(thresholds: [Int], labels: [TextID])
    /// 数で(千分率の値を割る数と、単位の言葉)。
    case number(divisor: Int, unit: TextID?)
}

/// 禁止語の規則: until が成り立つまで、プレイヤーに見える文字列に words を含めてはいけない。
/// 本物の規則は非公開のコンテンツにある(語そのものがネタバレなので)。公開版は試験用の語だけ。
public struct ForbiddenRule: Codable, Equatable, Sendable {
    public var words: [String]
    public var until: FactExpr

    public init(words: [String], until: FactExpr) {
        self.words = words
        self.until = until
    }
}

/// 禁止語の監査で試す「知っている事実の集合」の段(進み方の代表)。
public struct AuditStage: Codable, Equatable, Sendable {
    public var id: String
    public var facts: [FactID]

    public init(id: String, facts: [FactID]) {
        self.id = id
        self.facts = facts
    }
}

/// 文字列の門: この文字列が画面に出うるのは gate が成り立つときだけ(監査の範囲を絞る)。
/// 書いていない文字列は「いつでも出うる」とみなして全段で調べる(安全側)。
public struct TextGate: Codable, Equatable, Sendable {
    public var text: TextID
    public var gate: FactExpr
}

/// 巻き戻しの規則(何を持ち越すか)。
public struct RewindDef: Codable, Equatable, Sendable {
    /// 前の周回の記録のうち、仲間が覚えておく印。
    public var memorableTags: [ProvenanceTag]
    /// 関係の点を持ち越す割合(千分率。既定 1000 = 全部)。
    public var relationPermille: Int?

    public init(memorableTags: [ProvenanceTag] = [], relationPermille: Int? = nil) {
        self.memorableTags = memorableTags
        self.relationPermille = relationPermille
    }
}
