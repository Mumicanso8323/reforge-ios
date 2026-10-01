import Foundation
import RFContent
import RFKernel
import RFMatter
import RFWorld

/// 認識の層。プレイヤーに見える名前・説明・数値の見せ方を、真実の ID と「いま知っている事実の集合」から引く。
///
/// - 名前は保存しない。毎回ここで引くので、事実を 1 つ知った瞬間に、既に作った物・置いた物・図鑑・ノートの
///   出典・地図のラベル・過去の記録(日誌)の名前が全部、新しい見え方になる(遡る書き換え)。
/// - ここが返す文字列だけが画面に出る。英語の ID・見出しは決して返さない(見え方が無ければ unknownText)。
/// - 監査つき(auditing = true)で作ると、返す文字列をすべて禁止語の規則で調べ、違反を violations に残す
///   (ボット走行のテストで漏れを捕まえる)。
public struct Perceiver: Sendable {
    public let content: ContentDB
    public let known: Set<FactID>

    /// 見え方の無い見出しに出す文字列のキー。
    public static let unknownText: TextID = "text.unknown"

    public init(content: ContentDB, known: Set<FactID>) {
        self.content = content
        self.known = known
    }

    public init(content: ContentDB, world: WorldState) {
        self.init(content: content, known: world.knowledge.factSet)
    }

    /// いま使う見え方(見出しが表に無ければ nil)。
    public func variant(_ s: SubjectID) -> Variant? {
        content.perception[s]?.variants.first { $0.when.evaluate(known) }
    }

    public func name(_ s: SubjectID) -> String {
        text(variant(s)?.name ?? Self.unknownText)
    }

    public func description(_ s: SubjectID) -> String? {
        variant(s)?.description.map { text($0) }
    }

    /// 文字列表から引き、{名前} を埋める。キーが表に無ければ unknownText(英語のキーは出さない)。
    public func text(_ id: TextID, _ args: [String: String] = [:]) -> String {
        var s = content.texts[id] ?? content.texts[Self.unknownText] ?? "？"
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    /// 物質の名前(名前の部品を 1 つずつ引いて連結する)。
    public func name(of name: MatterName) -> String {
        name.parts.map { part -> String in
            // 無修飾・異常の段で語が空のときは、見え方の name を書かない(空文字列)
            guard let v = variant(Subject.namePart(part)) else { return "" }
            return v.name.map { text($0) } ?? ""
        }.joined()
    }

    public func name(of stuff: Stuff, naming: (Matter) -> MatterName = { NameGenerator.name(for: $0) }) -> String {
        switch stuff {
        case .item(let i): name(Subject.item(i))
        case .matter(let m): name(of: naming(m))
        }
    }

    /// 数値の見せ方(隠れた値は nil)。
    public func stat(_ id: StatID, value: Milli) -> String? {
        guard let display = variant(Subject.stat(id))?.display else { return nil }
        switch display {
        case .hidden:
            return nil
        case .bands(let thresholds, let labels):
            var label = labels.first
            for (i, t) in thresholds.enumerated() where value.raw >= Int64(t) && i + 1 < labels.count { label = labels[i + 1] }
            return label.map { text($0) }
        case .number(let divisor, let unit):
            let v = divisor > 0 ? value.raw / Int64(divisor) : value.raw
            return "\(v)" + (unit.map { text($0) } ?? "")
        }
    }

    /// 地図の文字(見え方 → 既定の文字の表 → "？")。
    public func glyph(_ s: SubjectID) -> String {
        variant(s)?.glyph ?? content.glyphs[s] ?? "？"
    }
}
