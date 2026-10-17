import Foundation
import ReForgeEngine
import RFTestSupport
import XCTest

final class LineBotTests: XCTestCase {
    func testHandOnlyCharcoalUseIsDailyHeatingBudget() throws {
        let loaded = try LineBotContent.load()
        let result = LineBot.handOnly(content: loaded.content, seed: 0, days: 4)
        for day in 2...4 {
            XCTAssertGreaterThanOrEqual(result.charcoalUsed[day, default: 0], 4, "day \(day)")
            XCTAssertLessThanOrEqual(result.charcoalUsed[day, default: 0], 6, "day \(day)")
        }
    }

    func testLineBotIsDeterministic() throws {
        let loaded = try LineBotContent.load()
        XCTAssertEqual(LineBot.line(content: loaded.content, seed: 7, path: .A, days: 10),
                       LineBot.line(content: loaded.content, seed: 7, path: .A, days: 10))
    }

    func testLaborNeverExceedsFourPeopleDays() throws {
        let loaded = try LineBotContent.load()
        let result = LineBot.line(content: loaded.content, seed: 0, path: .A, days: 10)
        for (day, labor) in result.labor {
            XCTAssertLessThanOrEqual(labor.assignedHours + labor.fellingHours, 32, "day \(day)")
            if labor.fellingHours == 0 { XCTAssertEqual(labor.woodAdded, 0, "day \(day)") }
        }
    }

    func testBothBundlesContainEveryKitIdentifier() throws {
        var pub = try TestContent.publicOnly()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LineBotPublicBundle.json")
        try ContentLoader.apply(json: Data(contentsOf: fixture), to: &pub, name: "line-bot-public")
        var sources = [(pub, LineBotContent.Source.publicBundle.rawValue)]
        if TestContent.hasPrivateLayer {
            sources.append((try TestContent.full(), LineBotContent.Source.generated.rawValue))
        }
        for (content, name) in sources {
            let missing = [
                content.modules[LineBotKit.minehead] == nil ? LineBotKit.minehead.rawValue : nil,
                content.modules[LineBotKit.furnace] == nil ? LineBotKit.furnace.rawValue : nil,
                content.modules[LineBotKit.anvil] == nil ? LineBotKit.anvil.rawValue : nil,
                content.structures[LineBotKit.kiln] == nil ? LineBotKit.kiln.rawValue : nil,
                content.handwork[LineBotKit.mine] == nil && content.interactions[LineBotKit.mineByHand] == nil ? LineBotKit.mine.rawValue : nil,
                content.handwork[LineBotKit.smelt] == nil ? LineBotKit.smelt.rawValue : nil,
                content.handwork[LineBotKit.hammer] == nil ? LineBotKit.hammer.rawValue : nil,
                content.interactions[LineBotKit.chopWood] == nil ? LineBotKit.chopWood.rawValue : nil,
                content.interactions[LineBotKit.burnCharcoal] == nil ? LineBotKit.burnCharcoal.rawValue : nil
            ].compactMap { $0 }
            XCTAssertTrue(missing.isEmpty, "W05|source=\(name)|missing=\(missing.joined(separator: ","))")
        }
    }
}
