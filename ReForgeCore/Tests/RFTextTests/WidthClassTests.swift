import RFKernel
import RFText
import XCTest

final class WidthClassTests: XCTestCase {
    func testTableValues() {
        let expected: [(WidthClass, Int, Int?, Int?)] = [
            (.button, 16, 150, 1), (.band, 14, 110, 1), (.tab, 12, 64, 1), (.card, 15, 343, 2),
            (.bubble, 14, 260, 4), (.prologue, 17, 310, 2), (.label, 12, 120, 1), (.body, 15, 343, nil),
        ]
        XCTAssertEqual(expected.count, WidthClass.allCases.count)
        for (cls, size, width, lines) in expected {
            XCTAssertEqual(cls.pointSize, size, "\(cls)")
            XCTAssertEqual(cls.maxWidth, width, "\(cls)")
            XCTAssertEqual(cls.maxLines, lines, "\(cls)")
        }
        XCTAssertEqual(WidthClass.minimumScale, 85)
    }

    func testShrinkAndGrowFlags() {
        XCTAssertEqual(Set(WidthClass.allCases.filter(\.shrinkable)), [.button, .band])
        XCTAssertEqual(Set(WidthClass.allCases.filter(\.growsWithText)), [.card, .bubble, .prologue, .body])
    }

    func testClassOfID() {
        for cls in WidthClass.allCases {
            XCTAssertEqual(WidthClass.of(TextID("ui.\(cls.rawValue).x")), cls)
        }
        for other in ["ui.a11y.x", "ui.daywrap.x", "ui.unknown.x", "ui.button", "button.x", "ui..x", ""] {
            XCTAssertEqual(WidthClass.of(TextID(other)), .body, other)
        }
    }
}
