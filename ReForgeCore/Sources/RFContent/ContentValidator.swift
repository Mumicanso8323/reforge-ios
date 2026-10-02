import RFKernel

/// コンテンツの検証(読み込みの後、テストと CI で回す)。エラーは直すまで出荷しない。警告は理由を書いて残してよい。
/// 担当は自分の集まりの検証をここに足す(1 つの関数 = 1 つの規則)。
///
/// メッセージには ID だけを書き、本文・禁止語を書かない(公開の CI のログに出ても漏れないように)。
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
        // 認識の層(U3)
        perceptionHasDefault(db, &out)
        perceptionFactsDefined(db, &out)
        perceptionDisplaysWellFormed(db, &out)
        perceptionGlyphsAreOneCell(db, &out)
        subjectsHavePerception(db, &out)
        referencedTextsExist(db, &out)
        unknownTextExists(db, &out)
        forbiddenRulesWellFormed(db, &out)
        auditStagesWellFormed(db, &out)
        textGatesWellFormed(db, &out)
        factsWellFormed(db, &out)
        latinAllowedIsNotAnID(db, &out)
        // 出来事・始まり
        startMembersExist(db, &out)
        eventsChangeTheWorld(db, &out)
        eventsNotTriggeredByDays(db, &out)
        narrativeRules(db, &out)  // 出来事まわり(U11。Schema/Condition.swift)
        worldTypeRules(db, &out)  // 場所・縛り・電力・掘った量・壊す・集団との戦い(U16。Schema/WorldTypes.swift)
        return out
    }

    // MARK: 認識の表

    /// 認識の表の各見出しは、最後に when = true の既定の見え方を持つ。
    static func perceptionHasDefault(_ db: ContentDB, _ out: inout [Issue]) {
        for (s, def) in db.perception.sorted(by: { $0.key < $1.key }) where def.variants.last?.when != .always {
            out.append(Issue(level: .error, rule: "perception.default", message: "\(s) の最後の見え方が when=true でない"))
        }
    }

    /// 見え方の when に出てくる事実は定義がある(誤記の見え方は永遠に選ばれない)。
    static func perceptionFactsDefined(_ db: ContentDB, _ out: inout [Issue]) {
        for (s, def) in db.perception.sorted(by: { $0.key < $1.key }) {
            for f in def.variants.reduce(into: Set<FactID>(), { $0.formUnion($1.when.mentionedFacts) }).sorted()
                where db.facts[f] == nil
            {
                out.append(Issue(level: .error, rule: "perception.fact", message: "\(s) の見え方が知らない事実 \(f) を見ている"))
            }
        }
    }

    /// 段階の見せ方は、しきい値が昇順で、言葉がしきい値より 1 つ多い。数の見せ方は割る数が正。
    static func perceptionDisplaysWellFormed(_ db: ContentDB, _ out: inout [Issue]) {
        for (s, def) in db.perception.sorted(by: { $0.key < $1.key }) {
            for v in def.variants {
                switch v.display {
                case .bands(let t, let labels):
                    if labels.count != t.count + 1 || zip(t, t.dropFirst()).contains(where: { $0 >= $1 }) {
                        out.append(Issue(level: .error, rule: "perception.bands",
                                         message: "\(s) の段階: しきい値は昇順・言葉はしきい値 + 1 個"))
                    }
                case .number(let d, _, let places) where d <= 0 || !(0...6).contains(places ?? 0):
                    out.append(Issue(level: .error, rule: "perception.number",
                                     message: "\(s) の割る数が 0 以下か、小数の桁が 0〜6 の外"))
                default: break
                }
            }
        }
    }

    /// 地図の文字は 1 文字(1 マス = 1 文字の正方形の枠)。
    static func perceptionGlyphsAreOneCell(_ db: ContentDB, _ out: inout [Issue]) {
        var glyphs: [(String, String)] = db.glyphs.map { ($0.key.rawValue, $0.value) }
        for (s, def) in db.perception { glyphs += def.variants.compactMap { $0.glyph }.map { (s.rawValue, $0) } }
        for (s, g) in glyphs.sorted(by: { $0.0 < $1.0 }) where g.count != 1 {
            out.append(Issue(level: .error, rule: "perception.glyph", message: "\(s) の地図の文字が 1 文字でない"))
        }
    }

    /// 画面に名前が出る定義には、認識の表の見出しがある(無ければ画面に「？」が出る)。
    static func subjectsHavePerception(_ db: ContentDB, _ out: inout [Issue]) {
        var need: [(SubjectID, String)] = []
        need += db.terrains.keys.map { (Subject.terrain($0), "terrain") }
        need += db.pois.keys.map { (Subject.poi($0), "poi") }
        need += db.modules.keys.map { (Subject.module($0), "module") }
        need += db.structures.keys.map { (Subject.structure($0), "structure") }
        need += db.people.values.map { ($0.name, "people \($0.id)") }
        need += db.stats.keys.map { (Subject.stat($0), "stat") }
        need += db.enemies.keys.map { (Subject.enemy($0), "enemy") }
        need += db.research.keys.map { (Subject.research($0), "research") }
        need += db.skills.keys.map { (Subject.skill($0), "skill") }
        need += db.abilities.keys.map { (Subject.ability($0), "ability") }
        need += db.groups.keys.map { (Subject.group($0), "group") }
        for (id, sh) in db.sheets {
            need.append((sh.title, "sheet \(id)"))
            need += (sh.rows + (sh.entryRows ?? [])).map { ($0.subject, "sheet \(id)") }
            for e in sh.entries ?? [] { need += [(e.subject, "sheet \(id)")] + (e.rows ?? []).map { ($0.subject, "sheet \(id)") } }
        }
        for (id, h) in db.hints { need += [(h.about, "hint \(id)"), (h.source, "hint \(id)")] }
        for (id, p) in db.pois { need += (p.parts ?? []).map { (Subject.part($0), "poi \(id)") } }
        var items = Set<ItemID>()
        for y in db.start.items { if let i = y.item { items.insert(i) } }
        for i in db.interactions.values { for y in i.yields { if let it = y.item { items.insert(it) } } }
        for e in db.enemies.values { for y in e.drops { if let it = y.item { items.insert(it) } } }
        for m in db.modules.values { for c in m.cost { if let it = c.item { items.insert(it) } } }
        for s in db.structures.values { for c in s.cost { if let it = c.item { items.insert(it) } } }
        need += items.map { (Subject.item($0), "item") }
        var reported = Set<SubjectID>()
        for (s, origin) in need.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) })
            where db.perception[s] == nil && reported.insert(s).inserted
        {
            out.append(Issue(level: .error, rule: "perception.missing",
                             message: "\(s)(\(origin))の見え方が無い。画面に「？」が出る"))
        }
    }

    // MARK: 文字列表

    /// 認識の表以外が指す文字列(場面・一言・所見・ヒント・目標・章・失敗の理由・選択肢・置けない理由・死因)。
    public static func nonPerceptionTextRefs(_ db: ContentDB) -> Set<TextID> {
        Set(nonPerceptionRefs(db).map(\.0))
    }

    static func nonPerceptionRefs(_ db: ContentDB) -> [(TextID, String)] {
        var refs: [(TextID, String)] = []
        for (id, sc) in db.scenes { for l in sc.lines { refs.append((l.text, "scene \(id)")) } }
        for (id, l) in db.lines { refs.append((l.text, "line \(id)")) }
        for (id, f) in db.findings { refs.append((f.text, "finding \(id)")) }
        for (id, h) in db.hints { refs.append((h.text, "hint \(id)")) }
        for (id, o) in db.objectives { refs.append((o.text, "objective \(id)")) }
        for (id, c) in db.chapters { refs.append((c.title, "chapter \(id)")) }
        for (id, f) in db.failureRules { refs.append((f.cause, "failureRule \(id)")) }
        for (id, m) in db.modules { if let r = m.placement.reasonIfBlocked { refs.append((r, "module \(id)")) } }
        for (id, sh) in db.sheets {
            let rows = sh.rows + (sh.entryRows ?? []) + (sh.entries ?? []).flatMap { $0.rows ?? [] }
            for r in rows { if let n = r.note { refs.append((n, "sheet \(id)")) } }
        }
        for (id, d) in db.documents { refs += [(d.title, "document \(id)"), (d.body, "document \(id)")] }
        for (id, e) in db.events {
            for c in e.choices ?? [] {
                refs.append((c.label, "event \(id)"))
                refs += c.effects.compactMap { causeText($0) }.map { ($0, "event \(id)") }
            }
            refs += e.effects.compactMap { causeText($0) }.map { ($0, "event \(id)") }
        }
        return refs
    }

    private static func causeText(_ e: Effect) -> TextID? {
        if case .die(_, let cause) = e { return cause }
        return nil
    }

    /// 認識の表・出来事・場面などが指す文字列が文字列表にある。
    static func referencedTextsExist(_ db: ContentDB, _ out: inout [Issue]) {
        var refs = nonPerceptionRefs(db)
        for (s, def) in db.perception {
            for v in def.variants {
                if let n = v.name { refs.append((n, "perception \(s)")) }
                if let d = v.description { refs.append((d, "perception \(s)")) }
                switch v.display {
                case .bands(_, let labels): refs += labels.map { ($0, "perception \(s)") }
                case .number(_, let unit?, _): refs.append((unit, "perception \(s)"))
                default: break
                }
            }
        }
        var reported = Set<String>()
        for (t, origin) in refs.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) })
            where db.texts[t] == nil && reported.insert("\(t)|\(origin)").inserted
        {
            out.append(Issue(level: .error, rule: "text.exists", message: "\(origin) が指す文字列 \(t) が無い"))
        }
    }

    /// 見え方の無い見出しに出す「？」がある。
    static func unknownTextExists(_ db: ContentDB, _ out: inout [Issue]) {
        if db.texts["text.unknown"] == nil {
            out.append(Issue(level: .error, rule: "text.unknown", message: "文字列 text.unknown が無い"))
        }
    }

    // MARK: 禁止語・監査の段・門

    static func forbiddenRulesWellFormed(_ db: ContentDB, _ out: inout [Issue]) {
        var ids = Set<String>()
        for (i, r) in db.forbidden.enumerated() {
            let name = r.id ?? "#\(i)"
            if r.words.isEmpty || r.words.contains(where: \.isEmpty) {
                out.append(Issue(level: .error, rule: "forbidden.words", message: "規則 \(name) に空の語がある"))
            }
            if let id = r.id, !ids.insert(id).inserted {
                out.append(Issue(level: .error, rule: "forbidden.id", message: "規則の名札 \(id) が重なっている"))
            }
            // 知らない事実を待つ規則は解けない(安全側)ので警告にとどめる
            for f in r.until.mentionedFacts.sorted() where db.facts[f] == nil {
                out.append(Issue(level: .warning, rule: "forbidden.fact", message: "規則 \(name) が知らない事実 \(f) を待っている"))
            }
        }
    }

    static func auditStagesWellFormed(_ db: ContentDB, _ out: inout [Issue]) {
        var ids = Set<String>()
        for st in db.auditStages {
            if !ids.insert(st.id).inserted {
                out.append(Issue(level: .error, rule: "auditStage.id", message: "監査の段 \(st.id) が重なっている"))
            }
            for f in st.facts.sorted() where db.facts[f] == nil {
                out.append(Issue(level: .error, rule: "auditStage.fact", message: "監査の段 \(st.id) の事実 \(f) が無い"))
            }
        }
    }

    static func textGatesWellFormed(_ db: ContentDB, _ out: inout [Issue]) {
        for (t, g) in db.textGates.sorted(by: { $0.key < $1.key }) {
            if db.texts[t] == nil {
                out.append(Issue(level: .error, rule: "textGate.text", message: "門の文字列 \(t) が無い"))
            }
            for f in g.gate.mentionedFacts.sorted() where db.facts[f] == nil {
                out.append(Issue(level: .error, rule: "textGate.fact", message: "\(t) の門が知らない事実 \(f) を見ている"))
            }
        }
    }

    /// 事実の含意・始まりの事実・出来事で知る事実・条件で見る事実に定義がある。
    static func factsWellFormed(_ db: ContentDB, _ out: inout [Issue]) {
        var refs: [(FactID, String)] = []
        for (id, f) in db.facts { refs += (f.implies ?? []).map { ($0, "fact \(id) の含意") } }
        refs += db.start.facts.map { ($0, "start") }
        for (id, e) in db.events {
            var effects = e.effects
            for c in e.choices ?? [] { effects += c.effects }
            for ef in effects { if case .learn(let f) = ef { refs.append((f, "event \(id)")) } }
            refs += knownFacts(e.trigger.when).map { ($0, "event \(id) の引き金") }
        }
        for (f, origin) in refs.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) }) where db.facts[f] == nil {
            out.append(Issue(level: .error, rule: "fact.defined", message: "\(origin) の事実 \(f) が無い"))
        }
    }

    static func knownFacts(_ c: Condition) -> Set<FactID> {
        switch c {
        case .known(let e): e.mentionedFacts
        case .all(let xs), .any(let xs): xs.reduce(into: Set()) { $0.formUnion(knownFacts($1)) }
        case .not(let x): knownFacts(x)
        default: []
        }
    }

    /// 許すラテン文字の語は固有名・題名だけ。ID らしい語(アンダーバー・小文字と記号だけ)を許すと、
    /// 英語の ID の漏れの検査がその語で素通りになる。
    static func latinAllowedIsNotAnID(_ db: ContentDB, _ out: inout [Issue]) {
        for (i, w) in db.latinAllowed.enumerated() {
            if w.isEmpty || w.contains("_") || w.range(of: #"^[a-z0-9.:\-]+$"#, options: .regularExpression) != nil {
                out.append(Issue(level: .error, rule: "latinAllowed.id", message: "許す語 #\(i) が ID のように見える(大文字を含む固有名だけ許す)"))
            }
        }
    }

    // MARK: 始まり・出来事

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
