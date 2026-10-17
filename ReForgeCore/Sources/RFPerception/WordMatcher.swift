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

    private static func normalizedEnglish(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func isAlphaNumeric(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
