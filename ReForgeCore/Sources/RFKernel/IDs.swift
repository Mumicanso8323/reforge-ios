/// 型付きの ID。中身は文字列(コンテンツの JSON に書く ID と同じ)。
///
/// - 文字列は「真実の ID」。プレイヤーに見せる名前は持たない(見せ方は RFPerception がコンテンツの表から引く)。
/// - 種類の取り違えを型で防ぐ(FactID を ItemKindID の所に渡せない)。
/// - 辞書のキーにしても JSON がオブジェクトになる(CodingKeyRepresentable)。セーブの差分が読みやすい。
public struct TypedID<Tag>: Hashable, Comparable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) { self.raw = raw }
    public init(stringLiteral value: String) { self.raw = value }

    public var description: String { raw }
    public static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }
}

extension TypedID: Codable {
    public init(from decoder: Decoder) throws {
        raw = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

extension TypedID: CodingKeyRepresentable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public var codingKey: CodingKey { Key(stringValue: raw) }
    public init?<T: CodingKey>(codingKey: T) { self.raw = codingKey.stringValue }
}

// MARK: - ID の種類(タグ)。コンテンツに定義がある物はすべてここに並ぶ。

public enum FactTag {}
public enum ItemKindTag {}
public enum FormTag {}
public enum TraitTag {}
public enum ProcessTag {}
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
public enum ObservationTag {}
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
public enum SheetTag {}
public enum FailureRuleTag {}

/// 知っている事実(認識の層の単位)。例: "fact.sky.double_moon_seen"。
public typealias FactID = TypedID<FactTag>
/// 物の種類(真実)。例: "item.iron"。純度・形は別に持つ。
public typealias ItemKindID = TypedID<ItemKindTag>
/// 形(塊・板・粉…)。
public typealias FormID = TypedID<FormTag>
/// 性質(硬さ・粘り…)。値は Int(万分率など、性質ごとにコンテンツで決める)。
public typealias TraitID = TypedID<TraitTag>
/// 発明の工程(石臼・洗い樋・炉…)の種類。モジュールの種類と 1 対 1 とは限らない。
public typealias ProcessID = TypedID<ProcessTag>
/// 地図に置ける生産モジュールの種類。
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
/// 試作の所見(「塊のままでは中まで水が通らない」など)の種類。
public typealias ObservationID = TypedID<ObservationTag>
public typealias HintID = TypedID<HintTag>
public typealias ResearchID = TypedID<ResearchTag>
public typealias SkillID = TypedID<SkillTag>
/// ノアや仲間の特別な力(名前は認識の層で引く)。
public typealias AbilityID = TypedID<AbilityTag>
public typealias EnemyKindID = TypedID<EnemyKindTag>
public typealias CounterID = TypedID<CounterTag>
public typealias ObjectiveID = TypedID<ObjectiveTag>
public typealias EndingID = TypedID<EndingTag>
public typealias ChapterID = TypedID<ChapterTag>
/// 地図の層(地表・地下…)。
public typealias LayerID = TypedID<LayerTag>
/// 数値の種類(大気・精神力…)。認識の層で「見せ方」を切り替える単位にもなる。
public typealias StatID = TypedID<StatTag>
/// 来歴に付ける印(コンテンツが決める)。後の開示が「この印の付いた行為」を指す。
public typealias ProvenanceTag = TypedID<ProvenanceTagTag>
/// 認識の表の見出し(見え方が切り替わる対象の汎用キー)。
public typealias SubjectID = TypedID<SubjectTag>
/// 手作業・固定レシピ(発明でない作り方)。
public typealias RecipeID = TypedID<RecipeTag>
/// 範囲の効果の種類(ある点・人・置いた物から半径 r の中で、振る舞いや数値が変わる)。
public typealias AuraKindID = TypedID<AuraKindTag>
/// 工程表(設計画面と同じ部品で開ける表)。ライン札以外の記録もこれで開く。
public typealias SheetID = TypedID<SheetTag>
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
