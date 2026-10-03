import XCTest
import ReForgeEngine
@testable import ReForge

final class WalkEdgeTests: XCTestCase {
    func testSquareHasFourOuterEdges() {
        let edges = WalkEdge.segments(spans: [
            WalkSpan(y: 0, minX: 0, maxX: 2),
            WalkSpan(y: 1, minX: 0, maxX: 2),
            WalkSpan(y: 2, minX: 0, maxX: 2),
        ])
        XCTAssertEqual(edges, [
            .init(from: GridPoint(0, 0), to: GridPoint(3, 0)),
            .init(from: GridPoint(0, 3), to: GridPoint(3, 3)),
            .init(from: GridPoint(0, 0), to: GridPoint(0, 3)),
            .init(from: GridPoint(3, 0), to: GridPoint(3, 3)),
        ])
    }

    func testConcavityRetainsItsInnerOuterBoundary() {
        let edges = WalkEdge.segments(spans: [
            WalkSpan(y: 0, minX: 0, maxX: 2),
            WalkSpan(y: 1, minX: 0, maxX: 0),
            WalkSpan(y: 2, minX: 0, maxX: 2),
        ])
        XCTAssertTrue(edges.contains(.init(from: GridPoint(1, 1), to: GridPoint(3, 1))))
        XCTAssertTrue(edges.contains(.init(from: GridPoint(1, 2), to: GridPoint(3, 2))))
        XCTAssertEqual(WalkEdge.segments(spans: []), [])
    }
}
