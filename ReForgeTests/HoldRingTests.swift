import XCTest
@testable import ReForge

final class HoldRingTests: XCTestCase {
    func testTrimIsZeroWhenNotPressingOrNoValue() {
        XCTAssertEqual(HoldRing.trim(permille: nil, pressing: false), 0)
        XCTAssertEqual(HoldRing.trim(permille: nil, pressing: true), 0)
        XCTAssertEqual(HoldRing.trim(permille: 500, pressing: false), 0)
    }

    func testTrimFollowsProgressAndClamps() {
        XCTAssertEqual(HoldRing.trim(permille: 0, pressing: true), 0)
        XCTAssertEqual(HoldRing.trim(permille: 250, pressing: true), 0.25, accuracy: 0.0001)
        XCTAssertEqual(HoldRing.trim(permille: 1000, pressing: true), 1)
        XCTAssertEqual(HoldRing.trim(permille: 1500, pressing: true), 1)
        XCTAssertEqual(HoldRing.trim(permille: -5, pressing: true), 0)
    }

    func testSpokenValue() {
        XCTAssertEqual(HoldRing.spokenValue(hold: true), "長押し")
        XCTAssertNil(HoldRing.spokenValue(hold: false))
    }
}
