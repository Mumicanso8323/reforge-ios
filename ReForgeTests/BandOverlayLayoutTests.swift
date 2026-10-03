import XCTest
@testable import ReForge

/// A-02 決断の帯: 帯を重ねる置き方では、帯の出入りで地図の枠が変わらない。
final class BandOverlayLayoutTests: XCTestCase {
    private let container = CGSize(width: 390, height: 560)

    func testMapFrameDoesNotDependOnBandHeight() {
        let none = BandOverlayLayout.mapFrame(container: container, band: 0)
        for h: CGFloat in [44, 96, 140, 900] {
            XCTAssertEqual(BandOverlayLayout.mapFrame(container: container, band: h), none)
        }
        XCTAssertEqual(none, CGRect(origin: .zero, size: container))
    }

    func testBandSitsAtTheBottomEdgeOfTheMapArea() {
        let f = BandOverlayLayout.bandFrame(container: container, band: 100)
        XCTAssertEqual(f.maxY, container.height)
        XCTAssertEqual(f.height, 100)
        XCTAssertEqual(BandOverlayLayout.bandFrame(container: container, band: 900).height, container.height)
    }

    func testControlLiftMatchesTheBandAndNeverUsesMoreThanHalfTheMap() {
        XCTAssertEqual(BandOverlayLayout.controlLift(band: 0), 0)
        XCTAssertEqual(BandOverlayLayout.controlLift(band: 100), 100)
        XCTAssertEqual(BandOverlayLayout.controlLift(band: 100, mapHeight: container.height), 100)
        XCTAssertEqual(BandOverlayLayout.controlLift(band: 900, mapHeight: container.height), container.height / 2)
    }
}
