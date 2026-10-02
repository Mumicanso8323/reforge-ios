import Foundation
import RFContent
import RFKernel

/// 深さの気配の監査(opening v0.2 TEST-O9。U19)。
///
/// hintThemes の事実ごとに、気配の主題がその段(auditStages の id)で画面に見えていて、見え方(名前・説明・文)に
/// その段の禁止語が無いことを確かめる。depthHints も同じ(段の既定は r1_end)。
/// - 気配を置かない事実は none に理由を書く(空は誤り)。
/// - 主題が無い行は、rule(数値や振る舞いで見せる)か pending(型・画面待ち)のどちらかが要る。
/// - 主題の見え方: scene:<SceneID> は場面の行の文、doc:<DocumentID> は資料の本文(段の本文も)、
///   hint:<HintID> は手がかりの文。ほかは認識の表で、その段に選ばれる見え方に名前が要る。
/// 違反の表示は禁止語の監査と同じく、語と文を伏せる(ForbiddenAudit.Violation)。
public enum HintAudit {
    public struct Problem: Hashable, Sendable, CustomStringConvertible {
        public enum Kind: Hashable, Sendable {
            /// 置かない理由が空。
            case emptyNone
            /// 段が auditStages に無い。
            case unknownStage(String)
            /// 主題も rule も pending も無い。
            case nothing
            /// 主題が見つからない(認識の表・場面・資料・手がかりに無い)。
            case missingSubject
            /// その段で見えない(文字列の門が閉じている・見え方に名前が無い)。
            case notVisible
            /// 見え方に禁止語がある。
            case forbidden(ForbiddenAudit.Violation)
        }

        /// 事実の ID か、工業の段の気配の番号。
        public var owner: String
        public var subject: String?
        public var kind: Kind

        public var description: String {
            let s = subject.map { " の \($0)" } ?? ""
            switch kind {
            case .emptyNone: return "\(owner): 気配を置かない理由が空"
            case .unknownStage(let st): return "\(owner): 段 \(st) が監査の段に無い"
            case .nothing: return "\(owner): 主題も rule も pending も無い(置かないなら none に理由を書く)"
            case .missingSubject: return "\(owner)\(s): 主題が見つからない"
            case .notVisible: return "\(owner)\(s): その段で見えない"
            case .forbidden(let v): return "\(owner)\(s): \(v)"
            }
        }
    }

    public static let defaultDepthStage = "r1_end"

    public static func audit(_ content: ContentDB) -> [Problem] {
        var out: [Problem] = []
        for (fact, t) in content.hintThemes.sorted(by: { $0.key < $1.key }) {
            let owner = fact.rawValue
            if let none = t.none {
                if none.trimmingCharacters(in: .whitespaces).isEmpty { out.append(Problem(owner: owner, kind: .emptyNone)) }
                continue
            }
            let subjects = t.subjects ?? []
            if subjects.isEmpty, t.rule == nil, (t.pending ?? []).isEmpty {
                out.append(Problem(owner: owner, kind: .nothing))
            }
            out += check(subjects, stage: t.stage ?? "", owner: owner, content)
        }
        for (id, d) in content.depthHints.sorted(by: { $0.key < $1.key }) {
            out += check(d.subjects ?? [], stage: d.stage ?? defaultDepthStage, owner: id, content)
        }
        return out
    }

    static func check(_ subjects: [SubjectID], stage: String, owner: String, _ content: ContentDB) -> [Problem] {
        guard let st = content.auditStages.first(where: { $0.id == stage }) else {
            return subjects.isEmpty ? [] : [Problem(owner: owner, kind: .unknownStage(stage))]
        }
        let known = ForbiddenAudit.closure(Set(st.facts), content)
        var out: [Problem] = []
        for s in subjects {
            func problem(_ k: Problem.Kind) { out.append(Problem(owner: owner, subject: s.rawValue, kind: k)) }
            let texts: [TextID]
            if let ts = textSubject(s, content) {
                guard !ts.isEmpty else { problem(.missingSubject); continue }
                let open = ts.filter { content.textGates[$0]?.gate.evaluate(known) ?? true }
                guard !open.isEmpty else { problem(.notVisible); continue }
                texts = open
            } else {
                guard content.perception[s] != nil else { problem(.missingSubject); continue }
                guard let v = Perceiver(content: content, known: known).variant(s), let name = v.name else {
                    problem(.notVisible); continue
                }
                texts = [name] + (v.description.map { [$0] } ?? [])
            }
            for t in texts {
                guard let body = content.texts[t] else { problem(.missingSubject); continue }
                for v in ForbiddenAudit.check(body, content: content, known: known, stage: stage, origin: t.rawValue) {
                    problem(.forbidden(v))
                }
            }
        }
        return out
    }

    /// 文の主題(scene・doc・hint)なら、その文字列の並び(見つからなければ空)。認識の表の主題なら nil。
    static func textSubject(_ s: SubjectID, _ content: ContentDB) -> [TextID]? {
        let raw = s.rawValue
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let kind = String(raw[..<colon]), rest = String(raw[raw.index(after: colon)...])
        switch kind {
        case "scene":
            return content.scenes[SceneID(rest)]?.lines.map(\.text) ?? []
        case "doc":
            guard let d = content.documents[DocumentID(rest)] else { return [] }
            return [d.body] + (d.stages?.steps.compactMap(\.body) ?? [])
        case "hint":
            return content.hints[HintID(rest)].map { [$0.text] } ?? []
        default:
            return nil
        }
    }
}
