import XCTest
import CoreGraphics
import ReForgeEngine
@testable import ReForge

final class StickMathTests: XCTestCase {
    func testDirectionsAndNeutralRange() {
        let cases: [(CGSize, StickDirection?)] = [
            (.init(width: 0, height: 0), nil), (.init(width: 14, height: 0), nil),
            (.init(width: 15, height: 0), .east), (.init(width: 0, height: 15), .south),
            (.init(width: -15, height: 0), .west), (.init(width: 0, height: -15), .north),
            (.init(width: 20, height: 20), .southEast), (.init(width: -20, height: 20), .southWest),
            (.init(width: -20, height: -20), .northWest), (.init(width: 20, height: -20), .northEast),
            (.init(width: 30, height: 8), .east), (.init(width: 8, height: 30), .south),
            (.init(width: -30, height: 8), .west), (.init(width: 8, height: -30), .north),
            (.init(width: 30, height: 30), .southEast), (.init(width: -30, height: -30), .northWest),
        ]
        for (offset, expected) in cases {
            XCTAssertEqual(StickMath.direction(offset: offset, previous: nil, directions: 8, neutralRadius: 14), expected)
        }
    }

    func testFourDirectionsHysteresisAndLimit() {
        XCTAssertEqual(StickMath.direction(offset: .init(width: 20, height: 20), previous: nil, directions: 4, neutralRadius: 14), .south)
        XCTAssertEqual(StickMath.direction(offset: .init(width: 20, height: 8), previous: .east, directions: 8, neutralRadius: 14), .east)
        let offset = StickMath.knobOffset(.init(width: 96, height: 0))
        XCTAssertEqual(offset.width, 48)
        XCTAssertEqual(offset.height, 0)
    }
}
