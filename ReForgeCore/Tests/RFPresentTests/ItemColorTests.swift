import RFContent
import RFKernel
import RFMatter
import RFPerception
import RFPresent
import RFWorld
import XCTest

/// 品の名前の色は、認識の層の見え方からだけ決まる(色で真実がばれない)。
final class ItemColorTests: XCTestCase {
    /// 2 つの物質。真実の素材の種類だけが違い、知らないうちの見え方は同じ(色の系統なし)。
    /// 事実 fact.test.tint を知ると、片方だけ紫の見え方になる。
    private func content() -> ContentDB {
        var db = ContentDB()
        db.perception["substance:Fe"] = SubjectDef(subject: "substance:Fe", variants: [
            Variant(when: .always, name: "text.test.a", tint: ItemTint(hue: .warm, vividness: 0)),
        ])
        db.perception["substance:Xq"] = SubjectDef(subject: "substance:Xq", variants: [
            Variant(when: .fact("fact.test.tint"), name: "text.test.b", tint: ItemTint(hue: .violet, vividness: 5)),
            Variant(when: .always, name: "text.test.a"),
        ])
        db.perception["substance:Yq"] = SubjectDef(subject: "substance:Yq", variants: [
            Variant(when: .always, name: "text.test.a"),
        ])
        return db
    }

    private func matter(_ s: SubstanceID) -> Stuff {
        .matter(Matter(substance: s, purity: Purity(percent: 60), stage: .metal, shape: .lump))
    }

    func testUnknownTintIsNeutral() {
        let p = Perceiver(content: content(), known: [])
        XCTAssertEqual(p.tint(of: matter("Xq")), .neutral)
        // 表に無い見出しも中立
        XCTAssertEqual(p.tint(of: matter("Zz")), .neutral)
        let c = ItemColor.base(.neutral, purity: Purity(percent: 60))
        XCTAssertLessThanOrEqual(Int(c.r) - Int(c.b), 12, "中立の色はほぼ無彩色")
        XCTAssertEqual(ItemColor.effects(.neutral, purity: nil), [])
    }

    func testTwoTruthsLookTheSameUntilKnown() {
        let p = Perceiver(content: content(), known: [])
        let a = p.tint(of: matter("Xq")), b = p.tint(of: matter("Yq"))
        XCTAssertEqual(a, b)
        XCTAssertEqual(ItemColor.base(a, purity: Purity(percent: 60)), ItemColor.base(b, purity: Purity(percent: 60)))
        XCTAssertEqual(ItemColor.effects(a, purity: nil), ItemColor.effects(b, purity: nil))
    }

    func testKnowingAFactChangesTheColor() {
        let before = Perceiver(content: content(), known: [])
        let after = Perceiver(content: content(), known: ["fact.test.tint"])
        let pur = Purity(percent: 60)
        XCTAssertNotEqual(ItemColor.base(before.tint(of: matter("Xq")), purity: pur),
                          ItemColor.base(after.tint(of: matter("Xq")), purity: pur))
        XCTAssertTrue(ItemColor.effects(after.tint(of: matter("Xq")), purity: pur).contains(.shimmer))
        // 事実に関係しない物は変わらない
        XCTAssertEqual(before.tint(of: matter("Yq")), after.tint(of: matter("Yq")))
    }

    func testPurityRaisesBrightness() {
        let t = ItemTint(hue: .warm, vividness: 1)
        func lum(_ c: RGB) -> Int { Int(c.r) + Int(c.g) + Int(c.b) }
        let low = ItemColor.base(t, purity: Purity(percent: 30))
        let mid = ItemColor.base(t, purity: Purity(percent: 80))
        let top = ItemColor.base(t, purity: Purity(basisPoints: 9990))
        XCTAssertLessThan(lum(low), lum(mid))
        XCTAssertLessThan(lum(mid), lum(top))
        // 純度が見えていないときは中くらい
        XCTAssertEqual(ItemColor.base(t, purity: nil), ItemColor.base(t, purity: nil))
    }

    func testGlossOnlyPassesBriefly() {
        let base = RGB(100, 100, 100)
        // 周期の大半は静か
        XCTAssertEqual(ItemColor.animated(base, effects: .gloss, index: 0, length: 4, time: 2.0), base)
        XCTAssertNotEqual(ItemColor.animated(base, effects: .gloss, index: 1, length: 4, time: 0.1), base)
    }
}
