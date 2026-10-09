import Foundation
import RFContent
import RFPerception
import RFPresent
import RFTestSupport
import XCTest

/// 地図に描く字が、同梱フォント(BIZ UD ゴシック)に全部あるかの照合。
/// 地図は 1 マス 1 字を固定の書体で描くので、書体に無い字は字が無い四角(豆腐)になる。
/// 失敗の文には字のコードポイントと見出しだけを出す(文言は出さない)。
final class MapGlyphCoverageTests: XCTestCase {
    /// ttf の cmap(format 4 と 12)から、書体にある字のコードポイントの集合を読む。
    static func coveredScalars(ttf data: [UInt8]) -> Set<UInt32> {
        func u16(_ o: Int) -> Int { Int(data[o]) << 8 | Int(data[o + 1]) }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        var table = 0
        for i in 0..<u16(4) where String(decoding: data[(12 + i * 16)..<(16 + i * 16)], as: UTF8.self) == "cmap" {
            table = u32(12 + i * 16 + 8)
        }
        precondition(table > 0, "cmap が無い")
        var out = Set<UInt32>()
        for i in 0..<u16(table + 2) {
            let sub = table + u32(table + 4 + i * 8 + 4)
            switch u16(sub) {
            case 4:
                let segs = u16(sub + 6) / 2
                let ends = sub + 14
                let starts = ends + segs * 2 + 2
                let deltas = starts + segs * 2
                let ranges = deltas + segs * 2
                for s in 0..<segs {
                    let end = u16(ends + s * 2), start = u16(starts + s * 2)
                    guard start <= end, start != 0xFFFF else { continue }
                    for c in start...end {
                        if u16(ranges + s * 2) == 0 {
                            if (c + u16(deltas + s * 2)) & 0xFFFF != 0 { out.insert(UInt32(c)) }
                        } else {
                            let g = u16(ranges + s * 2 + u16(ranges + s * 2) + (c - start) * 2)
                            if g != 0 { out.insert(UInt32(c)) }
                        }
                    }
                }
            case 12:
                for g in 0..<u32(sub + 12) {
                    let o = sub + 16 + g * 12
                    let s = u32(o), e = u32(o + 4)
                    if s <= e { for c in s...e { out.insert(UInt32(c)) } }
                }
            default: break
            }
        }
        return out
    }

    static func bundledFontScalars() throws -> Set<UInt32> {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("ReForge/Resources/Fonts/BIZUDGothic-Regular.ttf")
        let data = try Data(contentsOf: url)
        return coveredScalars(ttf: [UInt8](data))
    }

    private func code(_ c: Character) -> String {
        c.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: "+")
    }

    /// 内容(公開 + 非公開があれば重ねた物)の全ての地図の字が、受け皿の表を通したあとに書体にある。
    func testEveryContentGlyphIsInBundledFont() throws {
        let font = try Self.bundledFontScalars()
        XCTAssertTrue(font.contains(0x40), "cmap の読み取りが壊れている")
        let db = try TestContent.full()
        var missing: [String] = []
        func check(_ glyph: String, _ owner: String) {
            for c in MapGlyphFont.safe(glyph) where !c.isWhitespace && !c.unicodeScalars.allSatisfy({ font.contains($0.value) }) {
                missing.append("\(code(c)) \(owner)")
            }
        }
        for (id, def) in db.perception.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for (i, v) in def.variants.enumerated() {
                if let g = v.glyph { check(g, "\(id.rawValue) v\(i)") }
            }
        }
        for (id, g) in db.glyphs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) { check(g, id.rawValue) }
        let fixed = [("noahGlyph", TilePalette.noahGlyph), ("memberGlyph", TilePalette.memberGlyph),
                     ("spentGlyph", TilePalette.spentGlyph), ("fallback", "？"), ("fallbackPoi", "▒"), ("fallbackDeposit", "晶")]
        for (name, g) in fixed { check(g, name) }
        XCTAssertEqual(missing, [], "同梱フォントに無い地図の字(コードポイント 見出し)")
    }

    /// 受け皿の表の置き換え先は、どれも書体にある。置き換え元は書体に無い(要らない行は消す)。
    func testSubstituteTableIsConsistent() throws {
        let font = try Self.bundledFontScalars()
        for (from, to) in MapGlyphFont.substitutes {
            XCTAssertTrue(to.unicodeScalars.allSatisfy { font.contains($0.value) }, "置き換え先が書体に無い \(code(to))")
            XCTAssertFalse(from.unicodeScalars.allSatisfy { font.contains($0.value) }, "置き換え元が書体にある(行が要らない) \(code(from))")
        }
    }
}
