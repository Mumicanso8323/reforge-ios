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

    private func rules(_ edit: (inout TimeTintDef) -> Void) throws -> Set<String> {
        var content = try TestContent.publicOnly()
        edit(&content.timeTint!)
        return Set(ContentValidator.validate(content).filter { $0.level == .error && $0.rule.hasPrefix("timeTint") }.map(\.rule))
    }

    func testStructuralRules() throws {
        XCTAssertTrue(try rules { $0.keys = [] }.contains("timeTint.keys"))
        XCTAssertTrue(try rules { $0.keys = [$0.keys[0]] }.contains("timeTint.keys"))
        XCTAssertTrue(try rules { $0.keys[0].at = 1 }.contains("timeTint.at"))
        XCTAssertTrue(try rules { $0.keys[$0.keys.count - 1].at += 1 }.contains("timeTint.at"))
    }

    func testRangeRules() throws {
        XCTAssertTrue(try rules { $0.keys[0].brightness = 1001 }.contains("timeTint.brightness"))
        XCTAssertTrue(try rules { $0.keys[0].brightness = -1 }.contains("timeTint.brightness"))
        XCTAssertTrue(try rules { $0.keys[0].outside = 1001 }.contains("timeTint.brightness"))
        XCTAssertTrue(try rules { $0.keys[0].outside = -1 }.contains("timeTint.brightness"))
        XCTAssertTrue(try rules { $0.keys[0].strength = 351 }.contains("timeTint.strength"))
        XCTAssertFalse(try rules { $0.keys[0].strength = 350; $0.keys[0].tint = [0, 0, 0] }.contains("timeTint.strength"))
        XCTAssertTrue(try rules { $0.keys[0].tint = [1, 2] }.contains("timeTint.tint"))
        XCTAssertTrue(try rules { $0.keys[0].tint = [1, 2, 3, 4] }.contains("timeTint.tint"))
        XCTAssertTrue(try rules { $0.keys[0].tint = [1, 2, 256] }.contains("timeTint.tint"))
    }

    func testReservedRedBoundaries() throws {
        // hue exactly 18 degrees is reserved, 19 degrees is not (integer check)
        XCTAssertTrue(TimeTintPalette.isReservedRed(r: 200, g: 60, b: 0))
        XCTAssertFalse(TimeTintPalette.isReservedRed(r: 200, g: 61, b: 0))
        // saturation exactly 50% is reserved, 49% is not
        XCTAssertTrue(TimeTintPalette.isReservedRed(r: 150, g: 50, b: 50))
        XCTAssertFalse(TimeTintPalette.isReservedRed(r: 150, g: 51, b: 51))
        XCTAssertTrue(try rules { $0.keys[0].tint = [200, 60, 0] }.contains("timeTint.reservedRed"))
        XCTAssertFalse(try rules { $0.keys[0].tint = [200, 61, 0] }.contains("timeTint.reservedRed"))
    }
}
