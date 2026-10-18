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

    /// W-05 §2.1 の表の数(費用・batch・行為の時間と取れ高・手作業の回数・運搬・仲間の速さ・熱・時計・地図)が、
    /// 公開の束と生成したコンテンツで同じか。違いはボットの側で両方に対応する(時計の保持・手掘りの石のハンマー・
    /// 叩く場の焚き火・手が先・火の枠)。非公開の層が無ければ飛ばす。
    func testPublicBundleMatchesGeneratedNumbers() throws {
        guard TestContent.hasPrivateLayer else { throw XCTSkip("no private layer") }
        var pub = try TestContent.publicOnly()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LineBotPublicBundle.json")
        try ContentLoader.apply(json: Data(contentsOf: fixture), to: &pub, name: "line-bot-public")
        let generated = try TestContent.full()

        func facts(_ c: ContentDB) -> [String: String] {
            var out: [String: String] = [:]
            func cost(_ ingredients: [Ingredient]?) -> String {
                (ingredients ?? []).map { "\($0.item?.rawValue ?? "?"):\($0.quantity)" }.sorted().joined(separator: ",")
            }
            out["clock"] = "\(c.clock.dayRealSeconds)/\(c.clock.dayGameHours)/\(c.clock.nightGameHours)"
            out["map"] = "\(c.mapGen.size.width)x\(c.mapGen.size.height)"
            out["hauling"] = "\(c.hauling?.perPersonPerDay ?? 10)/\(c.hauling?.freeDistance ?? 8)/\(c.hauling?.stepDistance ?? 5)/\(c.hauling?.keepPermille ?? 800)"
            out["crew.gatherPermille"] = "\(c.crewWork?.gatherPermille ?? -1)"
            for id in [LineBotKit.minehead, LineBotKit.furnace, LineBotKit.anvil] {
                let m = c.modules[id]
                out["module.\(id.rawValue)"] = "cost=\(cost(m?.cost)) cycle=\(m?.cycleSeconds ?? -1) batch=\(m?.batch ?? 1)"
            }
            if let f = c.modules[LineBotKit.furnace]?.hearth?.furnace {
                out["furnace.heat"] = "work=\(f.work) max=\(f.max) cool=\(f.cool) preheat=\(f.preheat) preheatCost=\(f.preheatCost.sorted { $0.key < $1.key }) burn=\(f.burn.sorted { $0.key < $1.key }) woodCap=\(f.cap("wood"))"
            }
            let kiln = c.structures[LineBotKit.kiln]
            out["structure.kiln"] = "cost=\(cost(kiln?.cost)) build=\(kiln?.buildSeconds ?? -1)"
            for id in [LineBotKit.chopWood, LineBotKit.burnCharcoal] {
                let i = c.interactions[id]
                out[id.rawValue] = "seconds=\(i?.seconds ?? -1) hold=\(i?.hold ?? false) cost=\(cost(i?.cost)) yields=\((i?.yields ?? []).map { "\($0.item?.rawValue ?? "?"):\($0.min)-\($0.max)" }) to=\(String(describing: i?.yieldsTo))"
            }
            // 手掘りは公開の束が handwork、生成したコンテンツが行為。1 回掘る時間(ゲーム秒)で比べる。
            if let h = c.handwork[LineBotKit.mine] { out["dig.seconds"] = "\(h.presses * (h.pressSeconds ?? 160))" }
            else if let i = c.interactions[LineBotKit.mineByHand] { out["dig.seconds"] = "\(i.seconds)" }
            for id in [LineBotKit.smelt, LineBotKit.hammer] {
                let h = c.handwork[id]
                out[id.rawValue] = "presses=\(h?.presses ?? -1) press=\(h?.pressSeconds ?? 160)"
            }
            return out
        }
        let a = facts(pub), b = facts(generated)
        let differing = Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.sorted()
        XCTAssertTrue(differing.isEmpty, "W05|numbers differ: \(differing.map { "\($0) public=[\(a[$0] ?? "-")] generated=[\(b[$0] ?? "-")]" })")
    }
}
