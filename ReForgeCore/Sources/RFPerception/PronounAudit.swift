import RFContent
import RFKernel

public enum PronounAudit {
    public enum Severity: Hashable, Sendable { case error, review }

    public struct Finding: Hashable, Sendable {
        public var rule: String
        public var text: TextID
        public var language: LanguageID
        public var severity: Severity

        public init(rule: String, text: TextID, language: LanguageID, severity: Severity) {
            self.rule = rule
            self.text = text
            self.language = language
            self.severity = severity
        }
    }

    public static func check(_ content: ContentDB, language: LanguageID) -> [Finding] {
        guard let table = content.textTables.tables[language] else { return [] }
        var findings = Set<Finding>()
        for rule in content.pronounRules {
            for (text, about) in content.textAbout where about.contains(rule.about.rawValue) || about.contains("*") {
                guard let original = table[text] else { continue }
                let value = WordMatcher.removing(rule.allow[language], from: original, language: language)
                if rule.error[language].contains(where: { WordMatcher.contains(value, word: $0, language: language) }) {
                    findings.insert(Finding(rule: rule.id, text: text, language: language, severity: .error))
                }
                let reviewSeverity: Severity = about.contains("*") ? .error : .review
                if rule.review[language].contains(where: { WordMatcher.contains(value, word: $0, language: language) }) {
                    findings.insert(Finding(rule: rule.id, text: text, language: language, severity: reviewSeverity))
                }
            }
        }
        return findings.sorted { ($0.rule, $0.text, $0.language.rawValue, severityOrder($0.severity)) < ($1.rule, $1.text, $1.language.rawValue, severityOrder($1.severity)) }
    }

    /// 表のある全部の言語(擬似言語は日本語の表を変形した物なので除く)。
    public static func checkAll(_ content: ContentDB) -> [LanguageID: [Finding]] {
        var result: [LanguageID: [Finding]] = [:]
        for language in content.textTables.tables.keys where language != .pseudo {
            result[language] = check(content, language: language)
        }
        return result
    }

    private static func severityOrder(_ severity: Severity) -> Int {
        switch severity { case .error: 0; case .review: 1 }
    }
}
