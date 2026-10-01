import Foundation
import RFKernel
import XCTest

final class ValueTests: XCTestCase {
    func testValueKeepsShape() throws {
        let json = #"{"a": 1, "b": true, "c": [0, "x", null], "d": {"e": 18446744073709551615}}"#
        let v = try JSONDecoder().decode(Value.self, from: Data(json.utf8))
        XCTAssertEqual(v, .object(["a": .int(1), "b": .bool(true), "c": .array([.int(0), .string("x"), .null]),
                                   "d": .object(["e": .uint(UInt64.max)])]))
    }
}
