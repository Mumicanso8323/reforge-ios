#if DEBUG
import Foundation
import ReForgeEngine

/// 序の場面の画面の写真・動画のための、公開の層の試験の見本(中立の 3 行 × 2 場面。PT-B6 §3)。
/// DEBUG のビルドだけが読む。本番の束には入らない。物語の本文ではなく、見せ方を確かめるための文だけ。
/// 文は訳さない(5 言語の写真でも同じ見本)ので、Text(verbatim:) と同じく sample(verbatim:) で書く(gen-xcstrings が見ない形)。
@MainActor
@Observable
final class DebugPrologue {
    private static func sample(verbatim text: String) -> String { text }

    static let scenes: [[String]] = [
        [
            sample(verbatim: "試験の一行目"),
            sample(verbatim: "試験の二行目"),
            sample(verbatim: "試験の三行目"),
        ],
        [
            sample(verbatim: "試験の四行目"),
            sample(verbatim: "試験の五行目"),
            sample(verbatim: "試験の六行目"),
        ],
    ]

    private(set) var scene = 0
    private(set) var line = 0

    /// いま見せる序(終わったら nil)。本体の PrologueView と同じ形。
    var view: PrologueView? {
        guard scene < Self.scenes.count else { return nil }
        return PrologueView(lines: Array(Self.scenes[scene].prefix(line + 1)), waiting: true)
    }

    /// 送り。場面の最後の行の後は次の場面の 1 行目へ。最後の場面の最後の行の後は終わる。
    func advance() {
        guard scene < Self.scenes.count else { return }
        if line + 1 < Self.scenes[scene].count {
            line += 1
        } else {
            scene += 1
            line = 0
        }
    }
}
#endif
