import RFKernel

// 認識の表(D: Perception-Truth)。真実の ID(SubjectID)ごとに、知っている事実に応じた見え方を並べる。
// 上から順に when を調べ、最初に成り立った見え方を使う。最後の行は when = true(既定の見え方)にする(検証で確かめる)。
//
// 見出しの名前の付け方(コンテンツ全体の約束):
//   物の種類・モジュール・建造物・地形・POI・人などは、その ID の文字列をそのまま見出しにする
//   (例: ItemKindID "item.ore.red" の見え方は SubjectID "item.ore.red")。
//   名前の部品(純度の等級・形の接尾辞)・ノートの出典・地図のラベル・数値の見せ方も見出しを持つ。

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
