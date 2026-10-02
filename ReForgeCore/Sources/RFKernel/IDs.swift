/// 型付きの ID。中身は文字列(コンテンツの JSON に書く ID と同じ)。
///
/// - 文字列は「真実の ID」。プレイヤーに見せる名前は持たない(見せ方は RFPerception がコンテンツの表から引く)。
/// - 種類の取り違えを型で防ぐ(FactID を ItemID の所に渡せない)。
/// - 辞書のキーにしても JSON がオブジェクトになる(CodingKeyRepresentable)。セーブの差分が読みやすい。
///
/// RFMatter の StringIdentifier と同じ使い方ができる(rawValue / init(rawValue:) / 文字列リテラル)。
public struct TypedID<Tag>: RawRepresentable, Hashable, Comparable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

extension TypedID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

extension TypedID: CodingKeyRepresentable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public var codingKey: CodingKey { Key(stringValue: rawValue) }
    public init?<T: CodingKey>(codingKey: T) { self.rawValue = codingKey.stringValue }
}

// MARK: - ID の種類(タグ)。コンテンツに定義がある物はすべてここに並ぶ。

public enum FactTag {}
public enum ItemTag {}
public enum ModuleKindTag {}
public enum StructureKindTag {}
public enum TerrainTag {}
public enum BiomeTag {}
public enum POIKindTag {}
public enum InteractionTag {}
public enum PersonTag {}
public enum IdeologyAxisTag {}
public enum MemoryTag {}
public enum EventTag {}
public enum ChoiceTag {}
public enum SceneTag {}
public enum LineTag {}
public enum TextTag {}
public enum FindingTag {}
public enum HintTag {}
public enum ResearchTag {}
public enum SkillTag {}
public enum AbilityTag {}
public enum EnemyKindTag {}
public enum CounterTag {}
public enum ObjectiveTag {}
public enum EndingTag {}
public enum ChapterTag {}
public enum LayerTag {}
public enum StatTag {}
public enum ProvenanceTagTag {}
public enum SubjectTag {}
public enum RecipeTag {}
public enum AuraKindTag {}
public enum HandworkTag {}
public enum GroupTag {}
public enum SheetTag {}
public enum DocumentTag {}
public enum ArtTag {}
public enum FailureRuleTag {}

/// 知っている事実(認識の層の単位)。例: "fact.sky.double_moon_seen"。
public typealias FactID = TypedID<FactTag>
/// 手が先(INV-O8)で数える行為の種類(序盤の設計 v0.4 の W-04)。本体の決める種類は下の static。
public enum HandFamilyTag {}
public typealias HandFamilyID = TypedID<HandFamilyTag>

extension TypedID where Tag == HandFamilyTag {
    /// 運ぶ(手で運ぶ・経路の運搬)。本体が決める。
    public static let haul = HandFamilyID("family.haul")
    /// 建てる(建造物とモジュール)。本体が決める。
    public static let build = HandFamilyID("family.build")
}
/// 持ち物・投入物(燃料・混ぜ物・水・食料…)の種類。原作の item_id と同じ綴り(例: "iron_ore")。
/// 純度・形・熱の状態を持つ物(鉱石・鉄)は RFMatter の Matter で表し、在庫では Matter を持つ。
public typealias ItemID = TypedID<ItemTag>
/// 生産モジュール(= 発明の工程)の種類。RFMatter の RuleBook のキーと同じ(RFMatter では ModuleKind)。
/// 例: "minehead", "millstone", "sluice", "furnace"。
public typealias ModuleKindID = TypedID<ModuleKindTag>
/// 地図に置ける建造物(シェルター・柵・焚き火台…)の種類。
public typealias StructureKindID = TypedID<StructureKindTag>
public typealias TerrainID = TypedID<TerrainTag>
public typealias BiomeID = TypedID<BiomeTag>
public typealias POIKindID = TypedID<POIKindTag>
/// マス・POI・置いた物に対してできる行為(漁る・掘る・汲む…)。
public typealias InteractionID = TypedID<InteractionTag>
/// 人(ノア・仲間・まだ会っていない人)。
public typealias PersonID = TypedID<PersonTag>
public typealias IdeologyAxisID = TypedID<IdeologyAxisTag>
/// 仲間が持つ記憶の種類。
public typealias MemoryKindID = TypedID<MemoryTag>
public typealias EventID = TypedID<EventTag>
public typealias ChoiceID = TypedID<ChoiceTag>
public typealias SceneID = TypedID<SceneTag>
public typealias LineID = TypedID<LineTag>
/// 文字列表のキー。本文はコンテンツ(非公開)側にある。
public typealias TextID = TypedID<TextTag>
/// 試作の所見(実験ノートに自動で載る事実)の種類。RFMatter の FindingID と同じ。
public typealias FindingID = TypedID<FindingTag>
public typealias HintID = TypedID<HintTag>
public typealias ResearchID = TypedID<ResearchTag>
public typealias SkillID = TypedID<SkillTag>
/// ノアや仲間の人ごとの能力(名前は認識の層で引く)。
public typealias AbilityID = TypedID<AbilityTag>
public typealias EnemyKindID = TypedID<EnemyKindTag>
public typealias CounterID = TypedID<CounterTag>
public typealias ObjectiveID = TypedID<ObjectiveTag>
public typealias EndingID = TypedID<EndingTag>
public typealias ChapterID = TypedID<ChapterTag>
/// 地図の層(地表・地下…)。
public typealias LayerID = TypedID<LayerTag>
/// 数値の種類(精神力・拠点全体の数値…)。認識の層で「見せ方」を切り替える単位にもなる。
public typealias StatID = TypedID<StatTag>
/// 来歴に付ける印(コンテンツが決める)。後の開示が「この印の付いた行為」を指す。
public typealias ProvenanceTag = TypedID<ProvenanceTagTag>
/// 認識の表の見出し(見え方が切り替わる対象の汎用キー)。
public typealias SubjectID = TypedID<SubjectTag>
/// レシピ(原作 recipes.json の id と同じ綴り)。RFMatter の Recipe の ID。
public typealias RecipeID = TypedID<RecipeTag>
/// 人の集団(拠点の外の生存者のまとまり。R2〜R3 の接触・対立・和解)。
public typealias GroupID = TypedID<GroupTag>
/// 手作業(押し続けて 1 単位。原作 HandCraft)。工程 1 つを手でやる。
public typealias HandworkID = TypedID<HandworkTag>
/// 範囲の効果の種類(ある点・人・置いた物から半径 r の中で、振る舞いや数値が変わる)。
public typealias AuraKindID = TypedID<AuraKindTag>
/// 工程表(設計画面と同じ部品で開ける表)。ライン札以外の記録もこれで開く。
public typealias SheetID = TypedID<SheetTag>
/// 記録から開ける資料(DocumentDef)。
public typealias DocumentID = TypedID<DocumentTag>
/// 絵(立ち絵・山場・タイトル)。中身の分からない中立の番号にする(例 portrait.k03・beat.12)。
public typealias ArtID = TypedID<ArtTag>
/// 失敗の規則(何がどうなったら失敗か。期限は日数でなく値で判定する)。
public typealias FailureRuleID = TypedID<FailureRuleTag>

// MARK: - 実行中に生まれる物の ID

/// 置いた物・地図上の生き物・唯一品など、ゲーム中に生まれる実体の ID。世界ごとに 1 から順に振る(決定的)。
public struct EntityID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible, CodingKeyRepresentable {
    public let raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public var description: String { "#\(raw)" }
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(Int.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue; self.intValue = Int(stringValue) }
        init(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    public var codingKey: CodingKey { Key(intValue: raw) }
    public init?<T: CodingKey>(codingKey: T) {
        guard let v = codingKey.intValue ?? Int(codingKey.stringValue) else { return nil }
        raw = v
    }
}

/// 来歴の記録 1 件の ID(RFWorld の ProvenanceLedger が振る)。
public struct ProvenanceID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public var description: String { "prov\(raw)" }
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }

    public init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(Int.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

/// 連番の発行器。世界状態に入れて保存する(巻き戻しても番号は戻さない: 前の周回の記録と衝突させない)。
public struct IDAllocator: Codable, Equatable, Sendable {
    public private(set) var nextValue: Int
    public init(next: Int = 1) { self.nextValue = next }
    public mutating func next() -> Int {
        defer { nextValue += 1 }
        return nextValue
    }
}

public enum UIElementTag {}
/// 画面の要素(タブ・ボタン・行為・パネル)の ID。文字列で決める(例 "tab.base"・"crew.assign"・
/// "interaction.<InteractionID>")。表(ContentDB.uiGates)に無い要素はいつも出す。
/// 一覧と行為の要素の作り方は RFContent の UIElements。
public typealias UIElementID = TypedID<UIElementTag>

/// 画面の要素が開いた理由(W-01・INV-O4)。知識で開いたものは記憶を持って巻き戻しても残り、
/// 世界の状態で開いたものは巻き戻した先の世界に従う。
public enum DisclosureKind: String, Codable, Hashable, Sendable {
    case knowledge
    case world
}
