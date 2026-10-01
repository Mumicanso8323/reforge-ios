import Foundation
import RFKernel
import XCTest

final class KernelTests: XCTestCase {
    func testTypedIDEncodesAsStringAndDictionaryKey() throws {
        let d: [FactID: Int] = ["fact.b": 2, "fact.a": 1]
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = String(decoding: try enc.encode(d), as: UTF8.self)
        XCTAssertEqual(json, #"{"fact.a":1,"fact.b":2}"#)
        XCTAssertEqual(try JSONDecoder().decode([FactID: Int].self, from: Data(json.utf8)), d)
        XCTAssertEqual(ItemID(rawValue: "wood"), "wood")
    }

    func testEntityIDDictionaryKey() throws {
        let d: [EntityID: String] = [EntityID(3): "x"]
        let data = try JSONEncoder().encode(d)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"3":"x"}"#)
        XCTAssertEqual(try JSONDecoder().decode([EntityID: String].self, from: data), d)
    }

    /// 流れは seed と名前だけで決まり、互いに影響しない(あるシステムが引く回数を変えても他は変わらない)。
    func testRandomStreamsAreIndependentAndDeterministic() {
        var a = RandomStreams(seed: 42)
        var b = RandomStreams(seed: 42)
        _ = a.use(.combat) { r in (0..<10).map { _ in r.next() } }
        let x = a.use(.narrative) { $0.next() }
        let y = b.use(.narrative) { $0.next() }
        XCTAssertEqual(x, y)
        var c = RandomStreams(seed: 43)
        XCTAssertNotEqual(c.use(.narrative) { $0.next() }, y)
    }

    func testFactExprJSON() throws {
        let json = #"{"all": ["fact.a", {"not": "fact.b"}, true]}"#
        let e = try JSONDecoder().decode(FactExpr.self, from: Data(json.utf8))
        XCTAssertEqual(e, .all([.fact("fact.a"), .not(.fact("fact.b")), .always]))
        XCTAssertTrue(e.evaluate(["fact.a"]))
        XCTAssertFalse(e.evaluate(["fact.a", "fact.b"]))
        XCTAssertEqual(try JSONDecoder().decode(FactExpr.self, from: JSONEncoder().encode(e)), e)
    }

    func testGridBitset() {
        var b = GridBitset(size: GridSize(width: 70, height: 3))
        b[GridPoint(69, 2)] = true
        b[GridPoint(0, 0)] = true
        b[GridPoint(100, 100)] = true
        XCTAssertTrue(b[GridPoint(69, 2)])
        XCTAssertFalse(b[GridPoint(1, 0)])
        XCTAssertEqual(b.countSet, 2)
    }

    func testPurityClampsAndPrints() {
        XCTAssertEqual(Purity(basisPoints: 12_000), .full)
        XCTAssertEqual(Purity(percent: 30, hundredths: 5).description, "30.05%")
    }

    /// 読むときは範囲外を丸めずエラーにする。
    func testPurityDecodeRejectsOutOfRange() throws {
        XCTAssertEqual(try JSONDecoder().decode([Purity].self, from: Data("[0, 10000]".utf8)), [.zero, .full])
        XCTAssertThrowsError(try JSONDecoder().decode([Purity].self, from: Data("[10001]".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode([Purity].self, from: Data("[-1]".utf8)))
    }
}
