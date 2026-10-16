import RFContent
import RFTestSupport
import XCTest

final class TimeTintValidationTests: XCTestCase {
    func testTimeTintValidatorRejectsUnorderedStrengthAndReservedRed() throws {
        var unordered = try TestContent.publicOnly()
        unordered.timeTint!.keys.swapAt(0, 1)
        XCTAssertTrue(ContentValidator.validate(unordered).contains { $0.level == .error && $0.rule == "timeTint.at" })

        var strength = try TestContent.publicOnly()
        strength.timeTint!.keys[0].strength = 400
        XCTAssertTrue(ContentValidator.validate(strength).contains { $0.level == .error && $0.rule == "timeTint.strength" })

        var red = try TestContent.publicOnly()
        red.timeTint!.keys[0].tint = [255, 0, 0]
        XCTAssertTrue(ContentValidator.validate(red).contains { $0.level == .error && $0.rule == "timeTint.reservedRed" })
    }

    func testPublicTimeTintAndPaletteForwardingAreValid() throws {
        let content = try TestContent.publicOnly()
        XCTAssertEqual(ContentValidator.validate(content).filter { $0.level == .error && $0.rule.hasPrefix("timeTint") }, [])
        XCTAssertTrue(TimeTintPalette.isReservedRed(r: 255, g: 0, b: 0))
        XCTAssertFalse(TimeTintPalette.isReservedRed(r: 150, g: 72, b: 72))
    }
}
