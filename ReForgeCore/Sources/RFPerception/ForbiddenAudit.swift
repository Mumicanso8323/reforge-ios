import Foundation
import RFContent
import RFKernel

/// 禁止語の機械チェック(E-content.md §5.2、結合設計 TEST-S3)。
///
/// 2 段で捕まえる:
///  1. 静的な監査(audit): 知っている事実の段ごとに、その段で画面に出うる文字列(選ばれる見え方の名前・説明・
///     数値の段階の言葉と単位・地図の文字、門の開いた文字列)を全部作り、禁止語の規則に当てる。
///     段 = コンテンツの監査の段(auditStages)+ 規則ごとに自動で作る「その規則が解ける直前まで全部知った段」。
///  2. 走行中の監査(check / PerceptionAuditor): ボット走行で画面に出す文字列を、その時点の事実で当てる。
///
/// 規則の本物(語そのもの)は非公開のコンテンツにある。公開の試験用コンテンツは試験用の語だけを持つ。
/// 公開リポジトリの CI のログは誰でも読めるので、違反の表示は既定で語と文を伏せる
/// (環境変数 REFORGE_AUDIT_VERBOSE=1 のときだけ出す。手元で直すとき用)。
/// 英語の内部 ID・アンダーバー付きの識別子の漏れも同時に調べる(原作 CLAUDE.md「プレイヤーに見せてはいけないもの」)。
public enum ForbiddenAudit {
    public struct Violation: Hashable, Sendable, CustomStringConvertible {
        public var stage: String
        /// 当たった規則の名札(ForbiddenRule.id。無ければ "#番号")。英語の ID の漏れは "latin-id"。
        public var rule: String
        public var word: String
        public var text: String
        public var origin: String
        public var language: LanguageID

        public init(stage: String, rule: String, word: String, text: String, origin: String, language: LanguageID = .ja) {
            self.stage = stage
            self.rule = rule
            self.word = word
            self.text = text
            self.origin = origin
            self.language = language
        }

        public var description: String {
            if ForbiddenAudit.verbose { return "[\(stage)] 「\(word)」が「\(text)」(\(origin))" }
            let prefix = language == .ja ? "[\(stage)]" : "[\(stage)/\(language.rawValue)]"
            return "\(prefix) 規則 \(rule) が \(origin) に当たった(語と文は伏せた。REFORGE_AUDIT_VERBOSE=1 で表示)"
        }
    }

    public static let latinRule = "latin-id"
    public static let verboseEnv = "REFORGE_AUDIT_VERBOSE"

    static var verbose: Bool { ProcessInfo.processInfo.environment[verboseEnv] == "1" }

    /// その事実の集合で効いている規則(番号つき)。
    public static func activeRules(_ content: ContentDB, known: Set<FactID>) -> [(index: Int, rule: ForbiddenRule)] {
        content.forbidden.enumerated().filter { !$0.element.until.evaluate(known) }.map { ($0.offset, $0.element) }
    }

    /// その事実の集合で禁止されている語。
    public static func forbiddenWords(_ content: ContentDB, known: Set<FactID>, language: LanguageID = .ja) -> [String] {
        activeRules(content, known: known).flatMap { $0.rule.languageWords[wordsLanguage(language)] }
    }

    /// 声の表。scope を持つ規則が無ければ使わないので作らない。1 回の監査・1 回の検査にまとめて 1 度だけ作る。
    static func voices(_ content: ContentDB, rules: [ForbiddenRule]) -> [TextID: Set<TextVoice>] {
        rules.contains { $0.scope != nil } ? TextVoices.of(content) : [:]
    }

    static func ruleName(_ i: Int, _ r: ForbiddenRule) -> String { r.id ?? "#\(i)" }

    /// 文字列 1 つを調べる(走行中の監査)。
    public static func check(_ text: String, content: ContentDB, known: Set<FactID>, stage: String = "run",
                             origin: String = "", language: LanguageID = .ja, textID: TextID? = nil) -> [Violation]
    {
        check(text, rules: activeRules(content, known: known), allowed: content.latinAllowedByLanguage[wordsLanguage(language)], stage: stage,
              origin: origin, language: language, textID: textID, voices: voices(content, rules: content.forbidden))
    }

    /// 文字列の並びを調べる(Frame の全文字列など)。
    public static func check(_ texts: [String], content: ContentDB, known: Set<FactID>, stage: String = "run",
                             origin: String = "", language: LanguageID = .ja) -> [Violation]
    {
        let rules = activeRules(content, known: known)
        let voices = voices(content, rules: content.forbidden)
        return texts.flatMap { check($0, rules: rules, allowed: content.latinAllowedByLanguage[wordsLanguage(language)], stage: stage,
                                     origin: origin, language: language, textID: nil, voices: voices) }
    }

    static func check(_ text: String, rules: [(index: Int, rule: ForbiddenRule)], allowed: [String], stage: String,
                      origin: String, language: LanguageID = .ja, textID: TextID? = nil,
                      voices: [TextID: Set<TextVoice>] = [:]) -> [Violation]
    {
        var out: [Violation] = []
        for (i, r) in rules {
            guard applies(r.scope, textID: textID, voices: voices) else { continue }
            for w in r.languageWords[wordsLanguage(language)] where !w.isEmpty && WordMatcher.contains(text, word: w, language: language) {
                out.append(Violation(stage: stage, rule: ruleName(i, r), word: w, text: text, origin: origin, language: language))
            }
        }
        if looksLikeInternalID(text, allowed: allowed, language: language) {
            out.append(Violation(stage: stage, rule: latinRule, word: "internal-id", text: text, origin: origin, language: language))
        }
        return out
    }

    /// 英語の内部 ID・アンダーバー付きの識別子らしき文字列か。埋め込みの {名前} は文の型の一部なので除いて見る。
    /// 許す語(ContentDB.latinAllowed: 固有名・題名)は長いものから、語の境目でだけ取り除いてから判定する。
    public static func looksLikeInternalID(_ text: String, allowed: [String] = [], language: LanguageID = .ja) -> Bool {
        var body = text.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
        // 語の境目でだけ取り除く(許した語に英字が続く・前に付くものは別の語として調べる)
        for w in allowed.sorted(by: { $0.count > $1.count }) where !w.isEmpty {
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: w) + "(?![A-Za-z])"
            body = body.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        if language != .en { return body.range(of: #"[a-z]{3,}|_"#, options: .regularExpression) != nil }
        let pattern = #"(?<![A-Za-z])(?:[a-z][a-z0-9]*_[a-z0-9_]*|[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+)(?![A-Za-z])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(body.startIndex..., in: body)
        return regex.matches(in: body, range: range).contains { match in
            let value = (body as NSString).substring(with: match.range)
            return !value.contains(".") || value.split(separator: ".").contains(where: { $0.count > 1 })
        }
    }

    // MARK: 静的な監査

    /// 静的な監査。段ごとに出うる文字列を全部作って当てる。違反は重ねずに返す。
    public static func audit(_ content: ContentDB, language: LanguageID = .ja) -> [Violation] {
        var out: [Violation] = []
        var seen = Set<Violation>()
        let voices = voices(content, rules: content.forbidden)
        func add(_ vs: [Violation]) {
            for v in vs where seen.insert(Violation(stage: "", rule: v.rule, word: v.word, text: v.text, origin: v.origin, language: v.language)).inserted {
                out.append(v)
            }
        }
        for st in stages(content) {
            let known = closure(Set(st.facts), content)
            var rules = activeRules(content, known: known)
            if let only = st.onlyRule { rules = rules.filter { $0.index == only } }
            for visible in visibleTexts(content, known: known, language: language) {
                add(check(visible.text, rules: rules, allowed: content.latinAllowedByLanguage[wordsLanguage(language)], stage: st.id,
                          origin: visible.origin, language: language, textID: visible.id, voices: voices))
            }
        }
        return out
    }

    public static func auditAll(_ content: ContentDB) -> [LanguageID: [Violation]] {
        Dictionary(uniqueKeysWithValues: content.textTables.available.sorted { $0.rawValue < $1.rawValue }.map { ($0, audit(content, language: $0)) })
    }

    /// アプリの固定文言(Localizable.xcstrings のキーなど。いつでも画面に出うる)を全段で調べる。
    public static func auditFixedStrings(_ strings: [String], content: ContentDB, origin: String) -> [Violation] {
        var out = Set<Violation>()
        // 文字列カタログのキーの書式の指定(%lld・%@・%%・%1$@ など)は文ではないので外してから見る(英字の ID の検査に当たらないように)
        let plain = strings.map { $0.replacingOccurrences(of: #"%(\d+\$)?(lld|ld|d|@|%)"#, with: " ", options: .regularExpression) }
        for st in stages(content) {
            let known = closure(Set(st.facts), content)
            for s in plain { out.formUnion(check(s, rules: activeRules(content, known: known), allowed: content.latinAllowed, stage: st.id,
                                                 origin: origin)) }
        }
        return out.sorted { ($0.origin, $0.text, $0.rule) < ($1.origin, $1.text, $1.rule) }
    }

    struct Stage {
        var id: String
        var facts: Set<FactID>
        /// 自動で作った段は、その規則だけを当てる。
        var onlyRule: Int?
    }

    /// 調べる段: コンテンツの段(無ければ「何も知らない」段)+ 規則ごとの自動の段。
    /// 自動の段は「その規則の until に出てくる事実(と、それを含意する事実)以外を全部知っている」集合。
    /// 規則が解ける前に、ほかの事実の組み合わせで語が出てしまう漏れを、段の書き忘れに頼らず捕まえる。
    /// 規則の strict = false で外せる(段を手で書いた規則だけ)。
    static func stages(_ content: ContentDB) -> [Stage] {
        var out: [Stage] = (content.auditStages.isEmpty ? [AuditStage(id: "start", facts: [])] : content.auditStages)
            .map { Stage(id: $0.id, facts: Set($0.facts), onlyRule: nil) }
        let all = allFacts(content)
        for (i, r) in content.forbidden.enumerated() where r.strict ?? true {
            let mentioned = r.until.mentionedFacts
            let candidates = all.filter { closure([$0], content).isDisjoint(with: mentioned) }
            let known = closure(candidates, content)
            guard !r.until.evaluate(known) else { continue }
            out.append(Stage(id: "until:\(ruleName(i, r))", facts: known, onlyRule: i))
        }
        return out
    }

    /// コンテンツに出てくる事実すべて(定義・式・段)。
    static func allFacts(_ content: ContentDB) -> Set<FactID> {
        var s = Set(content.facts.keys)
        for d in content.perception.values { for v in d.variants { s.formUnion(v.when.mentionedFacts) } }
        for r in content.forbidden { s.formUnion(r.until.mentionedFacts) }
        for g in content.textGates.values { s.formUnion(g.gate.mentionedFacts) }
        for st in content.auditStages { s.formUnion(st.facts) }
        return s
    }

    /// 含意(FactDef.implies)で閉じる。StepContext.learn と同じ広げ方。
    public static func closure(_ facts: Set<FactID>, _ content: ContentDB) -> Set<FactID> {
        var out = facts
        var queue = Array(facts)
        while let f = queue.popLast() {
            for g in content.facts[f]?.implies ?? [] where out.insert(g).inserted { queue.append(g) }
        }
        return out
    }

    /// その事実の集合で画面に出うる文字列(文, 出どころ)。
    /// - 認識の表の見え方だけが指す文字列は、その段で選ばれた見え方のものだけ。
    /// - それ以外の文字列(場面・一言・所見・理由…と、どこからも指されていない文字列)は、門が開いていれば出うる
    ///   (門が無ければいつでも出うる。安全側)。
    struct VisibleText { var text: String; var id: TextID?; var origin: String }

    static func visibleTexts(_ content: ContentDB, known: Set<FactID>, language: LanguageID = .ja) -> [VisibleText] {
        var out: [VisibleText] = []
        let p = Perceiver(content: content, known: known, language: language)
        var perceptionTexts = Set<TextID>()
        for d in content.perception.values {
            for v in d.variants { perceptionTexts.formUnion(texts(of: v)) }
        }
        let elsewhere = ContentValidator.nonPerceptionTextRefs(content)
        for (s, _) in content.perception.sorted(by: { $0.key < $1.key }) {
            guard let v = p.variant(s) else { continue }
            for t in texts(of: v).sorted() where content.textTables.tables[wordsLanguage(language)]?[t] != nil {
                out.append(VisibleText(text: p.rawText(t), id: t, origin: "\(s.rawValue) → \(t.rawValue)"))
            }
            if let g = v.glyph { out.append(VisibleText(text: g, id: nil, origin: "\(s.rawValue) の地図の文字")) }
        }
        for (id, s) in (content.textTables.tables[wordsLanguage(language)] ?? [:]).sorted(by: { $0.key < $1.key }) {
            if perceptionTexts.contains(id), !elsewhere.contains(id) { continue }
            if content.textGates[id]?.gate.evaluate(known) ?? true { out.append(VisibleText(text: s, id: id, origin: id.rawValue)) }
        }
        for (s, g) in content.glyphs.sorted(by: { $0.key < $1.key }) { out.append(VisibleText(text: g, id: nil, origin: "\(s.rawValue) の地図の文字")) }
        return out
    }

    static func texts(of v: Variant) -> Set<TextID> {
        var s = Set([v.name, v.description].compactMap { $0 })
        switch v.display {
        case .bands(_, let labels): s.formUnion(labels)
        case .number(_, let unit, _): if let u = unit { s.insert(u) }
        case .hidden, nil: break
        }
        return s
    }

    static func wordsLanguage(_ language: LanguageID) -> LanguageID { language == .pseudo ? .ja : language }

    static func applies(_ scope: ForbiddenScope?, textID: TextID?, voices: [TextID: Set<TextVoice>]) -> Bool {
        guard let scope else { return true }
        let values = textID.flatMap { voices[$0] } ?? [.other]
        return values.contains { voice in
            switch voice {
            case .person(let person): return scope.speakers.contains(person)
            case .narration: return scope.narration
            case .other: return scope.other
            }
        }
    }
}
