import Foundation
import RFKernel

/// 言語ごとの禁止語の照らし方。英語だけは語の境目を使い、それ以外は正規化した部分一致にする。
public enum WordMatcher {
    public static func contains(_ text: String, word: String, language: LanguageID) -> Bool {
        let source = text.precomposedStringWithCanonicalMapping
        let target = word.precomposedStringWithCanonicalMapping
        guard !target.isEmpty else { return false }
        guard language == .en else { return source.contains(target) }

        let normalizedText = normalizedEnglish(source)
        let normalizedWord = normalizedEnglish(target)
        var search = normalizedText[...]
        while let range = search.range(of: normalizedWord) {
            let before = range.lowerBound > normalizedText.startIndex ? normalizedText[normalizedText.index(before: range.lowerBound)] : nil
            let after = range.upperBound < normalizedText.endIndex ? normalizedText[range.upperBound] : nil
            if !isAlphaNumeric(before) && !isAlphaNumeric(after) { return true }
            search = search[range.upperBound...]
        }
        return false
    }

    /// 文から語を除く(除いた所は空白にする。前後の字が新しい語にくっつかないように)。英語は大文字小文字を区別しない。
    public static func removing(_ words: [String], from text: String, language: LanguageID) -> String {
        var result = text.precomposedStringWithCanonicalMapping
        for word in words.map(\.precomposedStringWithCanonicalMapping) where !word.isEmpty {
            result = result.replacingOccurrences(of: word, with: " ", options: language == .en ? [.caseInsensitive] : [])
        }
        return result
    }

    private static func normalizedEnglish(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func isAlphaNumeric(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
