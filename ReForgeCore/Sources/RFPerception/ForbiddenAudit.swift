import Foundation
import RFContent
import RFKernel

/// 禁止語の機械チェック(D-perception の §4)。
///
/// 2 段で捕まえる:
///  1. 静的な監査(audit): コンテンツの監査の段(AuditStage = 知っている事実の集合)ごとに、その段で出うる
///     文字列(認識の表の見え方・門の開いた文字列)を全部作り、禁止語の規則に当てる。
///  2. 走行中の監査(check): ボット走行で画面に出す文字列をすべて当てる(テストで 0 件を確かめる)。
///
/// 規則の本物(語そのもの)は非公開のコンテンツにある。公開の試験用コンテンツは試験用の語だけを持つ。
/// 英語の内部 ID の漏れ([a-z_] の並び)も同時に調べる。
public enum ForbiddenAudit {
    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        public var stage: String
        public var word: String
        public var text: String
        public var origin: String

        public var description: String { "[\(stage)] 「\(word)」が「\(text)」(\(origin))" }
    }

    /// その事実の集合で禁止されている語。
    public static func forbiddenWords(_ content: ContentDB, known: Set<FactID>) -> [String] {
        content.forbidden.filter { !$0.until.evaluate(known) }.flatMap(\.words)
    }

    /// 文字列 1 つを調べる(走行中の監査)。
    public static func check(_ text: String, content: ContentDB, known: Set<FactID>, stage: String = "run",
                             origin: String = "") -> [Violation]
    {
        var out = forbiddenWords(content, known: known).filter { text.contains($0) }.map {
            Violation(stage: stage, word: $0, text: text, origin: origin)
        }
        if text.range(of: "[a-z]{3,}|_", options: .regularExpression) != nil {
            out.append(Violation(stage: stage, word: "(英語の ID)", text: text, origin: origin))
        }
        return out
    }

    /// 静的な監査。段が無ければ「何も知らない」段だけで調べる。
    public static func audit(_ content: ContentDB) -> [Violation] {
        let stages = content.auditStages.isEmpty ? [AuditStage(id: "start", facts: [])] : content.auditStages
        var out: [Violation] = []
        for st in stages {
            let known = Set(st.facts)
            let p = Perceiver(content: content, known: known)
            // 認識の表: その段で選ばれる見え方の名前・説明
            for (s, _) in content.perception.sorted(by: { $0.key < $1.key }) {
                guard let v = p.variant(s) else { continue }
                for t in [v.name, v.description].compactMap({ $0 }) {
                    out += check(p.text(t), content: content, known: known, stage: st.id, origin: "\(s)")
                }
            }
            // 文字列表: 門が無い(いつでも出うる)か、門が開いている文字列
            let referencedByPerception = Set(content.perception.values.flatMap(\.variants).flatMap {
                [$0.name, $0.description].compactMap { $0 }
            })
            for (id, s) in content.texts.sorted(by: { $0.key < $1.key }) where !referencedByPerception.contains(id) {
                let open = content.textGates[id]?.gate.evaluate(known) ?? true
                if open { out += check(s, content: content, known: known, stage: st.id, origin: "\(id)") }
            }
        }
        return out
    }
}
