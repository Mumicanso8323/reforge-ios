import Foundation
import RFContent
import RFKernel

/// 文言が誰の声として使われるか。1 つの文言が複数の場所で使われれば、声も複数になる。
public enum TextVoice: Hashable, Sendable {
    case person(PersonID)
    case narration
    case other
}

public enum TextVoices {
    private static let counter = NSLock()
    nonisolated(unsafe) private static var built = 0
    /// 試験用: 声の表を作った回数。
    public static var buildCount: Int { counter.lock(); defer { counter.unlock() }; return built }

    public static func of(_ content: ContentDB) -> [TextID: Set<TextVoice>] {
        counter.lock(); built += 1; counter.unlock()
        var result: [TextID: Set<TextVoice>] = [:]
        func add(_ text: TextID, _ voice: TextVoice) { result[text, default: []].insert(voice) }

        for scene in content.scenes.values {
            for line in scene.lines {
                add(line.text, line.speaker.map(TextVoice.person) ?? .narration)
            }
        }
        for line in content.lines.values {
            add(line.text, .person(line.speaker))
        }

        for text in ContentValidator.otherTextRefs(content) { add(text, .other) }
        for definition in content.perception.values {
            for variant in definition.variants {
                for text in ForbiddenAudit.texts(of: variant) { add(text, .other) }
            }
        }
        for table in content.textTables.tables.values {
            for text in table.keys where result[text] == nil { add(text, .other) }
        }
        return result
    }
}
