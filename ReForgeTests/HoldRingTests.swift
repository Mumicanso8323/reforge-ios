import XCTest
@testable import ReForge

@MainActor
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

    func testSpokenValue() throws {
        let tables = try AppModel.loadBundledContent(bundle: .main).textTables
        UIText.shared.configure(tables: tables, language: .ja, markFallback: false)
        XCTAssertEqual(HoldRing.spokenValue(hold: true), UIText.shared.string("ui.a11y.hold"))
        XCTAssertEqual(UIText.shared.string("ui.a11y.hold"), "長押し") // ja-table
        XCTAssertNil(HoldRing.spokenValue(hold: false))
    }
}
