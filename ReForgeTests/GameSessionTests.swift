import XCTest
import ReForgeCore
@testable import ReForge

final class GameSessionTests: XCTestCase {
    func testGatherStopsAtCapacity() {
        let session = GameSession(resource: ResourceCounter(amount: 9, capacity: 10))
        session.gather()
        session.gather()
        XCTAssertEqual(session.resource.amount, 10)
    }

    func testEndTurnAdvancesClockAndConsumes() {
        let session = GameSession(resource: ResourceCounter(amount: 2, capacity: 10))
        session.endTurn()
        XCTAssertEqual(session.elapsedTicks, 1)
        XCTAssertEqual(session.resource.amount, 1)
    }

    func testAdBannerHeightIs50pt() {
        XCTAssertEqual(AdLayout.bannerHeight, 50)
    }
}
