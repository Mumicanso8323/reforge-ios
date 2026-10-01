import RFKernel

/// コンテンツの検証(読み込みの後、テストと CI で回す)。エラーは直すまで出荷しない。警告は理由を書いて残してよい。
/// 担当は自分の集まりの検証をここに足す(1 つの関数 = 1 つの規則)。
public enum ContentValidator {
    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        public enum Level: String, Sendable { case error, warning }
        public var level: Level
        public var rule: String
        public var message: String

        public var description: String { "[\(level.rawValue)] \(rule): \(message)" }
    }

    public static func validate(_ db: ContentDB) -> [Issue] {
        var out: [Issue] = []
        perceptionHasDefault(db, &out)
        referencedTextsExist(db, &out)
        startMembersExist(db, &out)
        eventsChangeTheWorld(db, &out)
        eventsNotTriggeredByDays(db, &out)
        narrativeRules(db, &out)  // 出来事まわり(U11。Schema/Condition.swift)
        return out
    }

    /// 認識の表の各見出しは、最後に when = true の既定の見え方を持つ。
    static func perceptionHasDefault(_ db: ContentDB, _ out: inout [Issue]) {
        for (s, def) in db.perception.sorted(by: { $0.key < $1.key }) where def.variants.last?.when != .always {
            out.append(Issue(level: .error, rule: "perception.default", message: "\(s) の最後の見え方が when=true でない"))
        }
    }

    /// 認識の表・出来事・場面が指す文字列が文字列表にある。
    static func referencedTextsExist(_ db: ContentDB, _ out: inout [Issue]) {
        var refs: [(TextID, String)] = []
        for (s, def) in db.perception {
            for v in def.variants {
                if let n = v.name { refs.append((n, "perception \(s)")) }
                if let d = v.description { refs.append((d, "perception \(s)")) }
            }
        }
        for (id, sc) in db.scenes { for l in sc.lines { refs.append((l.text, "scene \(id)")) } }
        for (id, l) in db.lines { refs.append((l.text, "line \(id)")) }
        for (id, f) in db.findings { refs.append((f.text, "finding \(id)")) }
        for (t, origin) in refs.sorted(by: { $0.0 < $1.0 }) where db.texts[t] == nil {
            out.append(Issue(level: .error, rule: "text.exists", message: "\(origin) が指す文字列 \(t) が無い"))
        }
    }

    static func startMembersExist(_ db: ContentDB, _ out: inout [Issue]) {
        for p in db.start.members + (db.start.unmet ?? []) where db.people[p] == nil {
            out.append(Issue(level: .error, rule: "start.people", message: "始まりの人 \(p) の定義が無い"))
        }
    }

    /// 「文を出すだけ」の出来事を基本にしない(効果が場面だけの出来事は警告)。
    static func eventsChangeTheWorld(_ db: ContentDB, _ out: inout [Issue]) {
        for (id, e) in db.events.sorted(by: { $0.key < $1.key }) {
            let worldEffects = e.effects.filter { if case .startScene = $0 { false } else { true } }
            if worldEffects.isEmpty, (e.choices ?? []).isEmpty {
                out.append(Issue(level: .warning, rule: "event.changes-world",
                                 message: "\(id) は世界の状態を変えない(場面だけ)"))
            }
        }
    }

    /// 物語の引き金に日数を使わない(行動と世界の状態で引く)。
    static func eventsNotTriggeredByDays(_ db: ContentDB, _ out: inout [Issue]) {
        func usesDay(_ c: Condition) -> Bool {
            switch c {
            case .dayAtLeast: true
            case .all(let xs), .any(let xs): xs.contains(where: usesDay)
            case .not(let x): usesDay(x)
            default: false
            }
        }
        for (id, e) in db.events.sorted(by: { $0.key < $1.key }) where usesDay(e.trigger.when) {
            out.append(Issue(level: .warning, rule: "event.no-day-trigger", message: "\(id) の引き金が日数"))
        }
    }
}
