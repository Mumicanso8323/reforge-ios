import XCTest
@testable import ReForgeCore

final class ResourceCounterTests: XCTestCase {
    func testInitClampsIntoRange() {
        XCTAssertEqual(ResourceCounter(amount: 15, capacity: 10).amount, 10)
        XCTAssertEqual(ResourceCounter(amount: -3, capacity: 10).amount, 0)
    }

    func testAddClampsAtCapacityAndReportsApplied() {
        var c = ResourceCounter(amount: 8, capacity: 10)
        XCTAssertEqual(c.add(5), 2)
        XCTAssertEqual(c.amount, 10)
        XCTAssertTrue(c.isFull)
    }

    func testConsumeClampsAtZeroAndReportsApplied() {
        var c = ResourceCounter(amount: 3, capacity: 10)
        XCTAssertEqual(c.consume(5), 3)
        XCTAssertEqual(c.amount, 0)
        XCTAssertTrue(c.isEmpty)
    }

    func testAdjustDoesNotOverflow() {
        var c = ResourceCounter(amount: 5, capacity: 10)
        XCTAssertEqual(c.adjust(by: .max), 5)
        XCTAssertEqual(c.amount, 10)
        XCTAssertEqual(c.adjust(by: .min), -10)
        XCTAssertEqual(c.amount, 0)
    }

    func testZeroCapacity() {
        var c = ResourceCounter(capacity: 0)
        XCTAssertEqual(c.add(1), 0)
        XCTAssertTrue(c.isEmpty && c.isFull)
    }
}
