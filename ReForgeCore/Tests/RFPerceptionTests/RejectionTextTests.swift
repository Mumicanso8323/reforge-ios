import Foundation
import RFContent
import RFKernel
import RFPerception
import RFTestSupport
import XCTest

/// A: 断りの文に、埋まらない {…} が残らない。
/// 断りの理由(reason.*)は、ソースに書かれた文字列の全部を拾って数える(新しい理由を足しても、この試験の対象になる)。
final class RejectionTextTests: XCTestCase {
    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources", isDirectory: true)

    /// Sources の全 Swift ファイルの中身。
    static func allSource() throws -> [String] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: sources, includingPropertiesForKeys: nil) else { return [] }
        return try e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
    }

    static func matches(_ pattern: String, in s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range(at: 1), in: s).map { String(s[$0]) }
        }
    }

    func reasonIDs() throws -> [String] {
        var out = Set<String>()
        for s in try Self.allSource() { out.formUnion(Self.matches("\"(reason\\.[a-z_0-9.]+)\"", in: s)) }
        return out.sorted()
    }

    func detailKeys() throws -> [String] {
        var out = Set<String>()
        for s in try Self.allSource() {
            for line in s.split(separator: "\n") where line.contains("Rejection(") || line.contains("detail:") {
                out.formUnion(Self.matches("\"([a-z][a-zA-Z]*)\": *\\.(?:int|string)", in: String(line)))
            }
        }
        return out.sorted()
    }

    func noBraces(_ s: String) -> Bool { !s.contains("{") && !s.contains("}") }

    /// 理由の全種類(ソースに書かれた reason.* の全部)× 差し込みの種類: 文にして { } が残らない。
    func testNoPlaceholderSurvivesForEveryReason() throws {
        let ids = try reasonIDs()
        let keys = try detailKeys()
        XCTAssertGreaterThan(ids.count, 100, "ソースの走査が空振りでない")
        XCTAssertTrue(keys.contains("days") && keys.contains("count") && keys.contains("item"))
        var content = try TestContent.publicOnly()
        let p0 = Perceiver(content: content, known: [])
        let all = "{" + keys.joined(separator: "}{") + "}{0}"
        // 見本の値: 数は数、品は公開の層の品、それ以外の文字列(向き・原因など)は文字
        let item: ItemID = "stick"
        var detail: [String: Value] = [:]
        for k in keys { detail[k] = ["item"].contains(k) ? .string(item.rawValue) : .int(3) }
        for id in ids {
            let tid = TextID(rawValue: id)
            // 1) 文が表に無い: わからない文(英語のキーも波かっこも出ない)
            XCTAssertTrue(noBraces(p0.rejectionText(tid, detail: detail)), id)
            XCTAssertTrue(noBraces(p0.rejectionText(tid)), id)
            // 2) 差し込みの名前を全部持つ文: 持っている値で埋まる。値が無い名前が残れば、わからない文にする
            let saved = content.texts[tid]
            content.texts[tid] = all
            let p = Perceiver(content: content, known: [])
            let full = p.rejectionText(tid, detail: detail)
            XCTAssertTrue(noBraces(full), "\(id): 埋まらない { } が残った: \(full)")
            XCTAssertTrue(noBraces(p.rejectionText(tid)), "\(id): 値が無いとき")
            XCTAssertTrue(noBraces(p.rejectionText(tid, detail: ["days": .int(2)])), "\(id): 一部だけの値")
            content.texts[tid] = saved
        }
    }

    /// 公開の層の reason.* の文は、断りが持つ値で埋まる({0} は品の名前)。
    func testPublicReasonTextsAreFilled() throws {
        let content = try TestContent.publicOnly()
        let p = Perceiver(content: content, known: [])
        let withItem = content.texts.filter { $0.key.rawValue.hasPrefix("reason.") && $0.value.contains("{0}") }
        XCTAssertFalse(withItem.isEmpty)
        let item: ItemID = "stick"
        let name = p.name(Subject.item(item))
        for (id, _) in withItem {
            let s = p.rejectionText(id, detail: ["item": .string(item.rawValue)])
            XCTAssertTrue(noBraces(s), "\(id.rawValue): \(s)")
            XCTAssertTrue(s.contains(name), "\(id.rawValue): 品の名前が入る")
            XCTAssertTrue(noBraces(p.rejectionText(id)), "\(id.rawValue): 品が分からなくても { } は出さない")
        }
    }

    /// 日数・人数の差し込み(クールダウン・人数)。
    func testNumbersAreSubstituted() throws {
        var content = try TestContent.publicOnly()
        content.texts["reason.explore.cooldown"] = "あと{days}日"
        content.texts["reason.explore.need_more_people"] = "{count}人"
        let p = Perceiver(content: content, known: [])
        XCTAssertEqual(p.rejectionText("reason.explore.cooldown", detail: ["days": .int(4)]), "あと4日")
        XCTAssertEqual(p.rejectionText("reason.explore.need_more_people", detail: ["count": .int(2)]), "2人")
        XCTAssertTrue(noBraces(p.rejectionText("reason.explore.cooldown")))
    }
}
