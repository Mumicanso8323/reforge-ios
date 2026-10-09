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

    private func codes(_ s: String) -> String {
        s.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: "+")
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

    /// 受け皿の表の置き換えが、別の物を同じ字にしない(置き換える前は違う字だった 2 つが、置き換えた後で同じになる組が無い)。
    /// もともと同じ字を共有している物(同じ字を意図して共有する)は対象外。失敗の文は見出しとコードポイントだけ。
    func testSubstitutionsDoNotMergeDifferentGlyphs() throws {
        let db = try TestContent.full()
        var entries: [(owner: String, glyph: String)] = []
        for (id, def) in db.perception.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for (i, v) in def.variants.enumerated() { if let g = v.glyph { entries.append(("\(id.rawValue) v\(i)", g)) } }
        }
        for (id, g) in db.glyphs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) { entries.append((id.rawValue, g)) }
        entries += [("noahGlyph", TilePalette.noahGlyph), ("memberGlyph", TilePalette.memberGlyph),
                    ("spentGlyph", TilePalette.spentGlyph), ("fallback", "？"), ("fallbackPoi", "▒"), ("fallbackDeposit", "晶")]
        var byMapped: [String: [(owner: String, original: String)]] = [:]
        for e in entries where !e.glyph.allSatisfy(\.isWhitespace) { byMapped[MapGlyphFont.safe(e.glyph), default: []].append((e.owner, e.glyph)) }
        var merged: [String] = []
        for (mapped, owners) in byMapped.sorted(by: { $0.key < $1.key }) {
            let originals = Set(owners.map(\.original))
            guard originals.count > 1 else { continue }
            let names = owners.map { "\($0.owner)[\(codes($0.original))]" }
            merged.append("\(codes(mapped)) ← \(Array(Set(names)).sorted().prefix(6))")
        }
        XCTAssertEqual(merged, [], "置き換えで別の字が同じ字になる組(置き換え後の字 ← 見出し[元の字])")
    }

    /// 10 分の地図(公開+非公開を重ねた内容)に出る物の字は、全部違う。置き換えの表を通した後の字で比べる。
    /// 同じ物の見え方の違い(variants)は同じ物として数える。非公開の層が無い環境では、公開の試験用の内容だけなので省く。
    func testTenMinuteMapGlyphsAreAllDistinct() throws {
        try XCTSkipUnless(TestContent.hasPrivateLayer, "非公開の層が無い")
        let db = try TestContent.full()
        var owners: [String: Set<String>] = [:]   // 置き換え後の字 → 物の見出し
        func add(_ glyph: String, _ owner: String) {
            guard !glyph.allSatisfy(\.isWhitespace) else { return }
            owners[MapGlyphFont.safe(glyph), default: []].insert(owner)
        }
        for (id, def) in db.perception {
            for v in def.variants { if let g = v.glyph { add(g, id.rawValue) } }
        }
        for (id, g) in db.glyphs { add(g, id.rawValue) }
        for (name, g) in [("noahGlyph", TilePalette.noahGlyph), ("memberGlyph", TilePalette.memberGlyph),
                          ("spentGlyph", TilePalette.spentGlyph), ("fallback", "？"), ("fallbackPoi", "▒"), ("fallbackDeposit", "晶")] {
            add(g, name)
        }
        // 意図して同じ字を共有する物(同じ字で良いと決めた組)。理由: 人は名乗る前は全員同じ字・晶は鉱の種類をまとめる・
        // 残骸の 2 つは同じ種類・採取の拠点は同じ役目・水と浜は青い面の塗りで見分ける(game-designer 決定)。
        let allowedGroups: [Set<String>] = [
            ["poi:wreck.far", "poi:wreck.home", "fallbackPoi"],  // 見出しの無い POI の既定の字は、元から残骸と同じ字
            ["module:minehead", "structure:forage_post"],
            ["terrain:shore", "terrain:water"],
        ]
        func allowed(_ names: Set<String>) -> Bool {
            let rest = names.filter { !$0.hasPrefix("person:") && !$0.hasPrefix("deposit:") }
            return rest.count <= 1 || allowedGroups.contains { rest.isSubset(of: $0) }
        }
        let same = owners.filter { $0.value.count > 1 && !allowed($0.value) }.sorted { $0.key < $1.key }
            .map { "\(codes($0.key)) ← \($0.value.sorted().prefix(6))" }
        XCTAssertEqual(same, [], "10 分の地図で同じ字になる物の組(字 ← 見出し)")
    }

    /// 地図の字に、半角カナ(U+FF61〜FF9F)と、字が無い四角(豆腐)に見える箱の字を使わない。
    /// 書体にあっても、小さく描くと豆腐と見分けがつかない(録画で、岩場の半角カナが一面の豆腐に見えた)。
    func testMapGlyphsAreNeitherHalfWidthKanaNorBoxLookalikes() throws {
        let db = try TestContent.full()
        let boxes: Set<UInt32> = [0x25A1, 0x25A2, 0x25AB, 0x25AF, 0x2610, 0x25FB, 0x25FD, 0x2B1C, 0x2B1B, 0x25FE, 0x25FC]
        var bad: [String] = []
        func check(_ glyph: String, _ owner: String) {
            for u in MapGlyphFont.safe(glyph).unicodeScalars where (0xFF61...0xFF9F).contains(u.value) || boxes.contains(u.value) {
                bad.append("\(String(format: "U+%04X", u.value)) \(owner)")
            }
        }
        for (id, def) in db.perception.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for v in def.variants { if let g = v.glyph { check(g, id.rawValue) } }
        }
        for (id, g) in db.glyphs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) { check(g, id.rawValue) }
        for (name, g) in [("noahGlyph", TilePalette.noahGlyph), ("memberGlyph", TilePalette.memberGlyph),
                          ("spentGlyph", TilePalette.spentGlyph), ("fallback", "？"), ("fallbackPoi", "▒"), ("fallbackDeposit", "晶")] {
            check(g, name)
        }
        XCTAssertEqual(bad, [], "半角カナ・箱に見える字を使っている地図の字(コードポイント 見出し)")
    }

    /// 受け皿の表の置き換え先は、どれも書体にある。置き換え元は書体に無い(要らない行は消す)。
    func testSubstituteTableIsConsistent() throws {
        let font = try Self.bundledFontScalars()
        for (from, to) in MapGlyphFont.substitutes {
            XCTAssertTrue(to.unicodeScalars.allSatisfy { font.contains($0.value) }, "置き換え先が書体に無い \(code(to))")
            XCTAssertFalse(from.unicodeScalars.allSatisfy { font.contains($0.value) }, "置き換え元が書体にある(行が要らない) \(code(from))")
        }
        for (from, to) in MapGlyphFont.readable {
            XCTAssertTrue(to.unicodeScalars.allSatisfy { font.contains($0.value) }, "読める字への置き換え先が書体に無い \(code(to))")
            XCTAssertNotNil(from.unicodeScalars.first.map { (0xFF61...0xFF9F).contains($0.value) ? true : nil } ?? nil, "読める字の表の元は半角カナだけ \(code(from))")
        }
    }
}
