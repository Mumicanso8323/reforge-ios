import Foundation
import XCTest
@testable import ReForgeCore

/// TEST-08(REQ-05): プレイヤーが目にする全文字列に Era 1 の禁止語が 0 件。
/// 対象: アプリの Localizable.xcstrings、アプリのソース中の日本語リテラル、GameText が組み立てる全文言
/// (日誌・警告・理由・結果・選択肢)、コンテンツの名前と効果文。
final class T08_PerceptionTruthTests: XCTestCase {
    /// §7「文言の総点検」の禁止語リスト。`_` は英語の内部 ID が漏れていないかの検出を兼ねる。
    static let forbidden = [
        "Ferrum", "ferrum", "惑星", "宇宙船", "Re:Forged", "ポッド", "カプセル", "異界", "先住", "魔術",
        "帰還船", "Re:Genesis", "_",
    ]

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private func assertClean(_ strings: [String], _ origin: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(strings.isEmpty, "\(origin): 検査対象が空", file: file, line: line)
        for s in strings {
            for word in Self.forbidden where s.contains(word) {
                XCTFail("\(origin): 禁止語「\(word)」が「\(s)」に含まれる", file: file, line: line)
            }
            // 英語の内部 ID(小文字で始まる英単語)が混ざっていないか
            if s.range(of: "[a-z]{3,}", options: .regularExpression) != nil {
                XCTFail("\(origin): 英語の識別子らしきものが「\(s)」に含まれる", file: file, line: line)
            }
        }
    }

    // MARK: アプリ

    private func appLiterals() throws -> [String] {
        let dir = Self.repoRoot.appendingPathComponent("ReForge/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let regex = try NSRegularExpression(pattern: #""((?:[^"\\\n]|\\.)*)""#)
        var found = Set<String>()
        for url in files {
            for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n") {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let ns = line as NSString
                for m in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let text = ns.substring(with: m.range(at: 1))
                    if text.unicodeScalars.contains(where: { $0.value > 127 }) { found.insert(text) }
                }
            }
        }
        return found.sorted()
    }

    private func catalog() throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent("ReForge/Resources/Localizable.xcstrings")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(obj as? [String: Any])
    }

    func testStringCatalogHasNoForbiddenTerms() throws {
        let cat = try catalog()
        XCTAssertEqual(cat["sourceLanguage"] as? String, "ja")
        let strings = try XCTUnwrap(cat["strings"] as? [String: Any])
        var all = Array(strings.keys)
        for (_, entry) in strings {
            let locs = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for (_, loc) in locs {
                if let v = ((loc as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String { all.append(v) }
            }
        }
        assertClean(all, "Localizable.xcstrings")
    }

    func testAppLiteralsAreCataloguedAndClean() throws {
        let literals = try appLiterals()
        assertClean(literals, "ReForge/Sources")
        let keys = Set(try XCTUnwrap(try catalog()["strings"] as? [String: Any]).keys)
        for s in literals {
            XCTAssertFalse(s.contains("\\("), "画面の文言に補間を書かない(GameText で組み立てる): \(s)")
            XCTAssertTrue(keys.contains(s), "Localizable.xcstrings に無い(tools/gen-xcstrings.py を実行): \(s)")
        }
    }

    // MARK: ロジック層が組み立てる文言

    func testContentTextsAreClean() {
        let c = Fixture.content
        assertClean(c.items.map(\.name) + c.recipes.flatMap { [$0.name, $0.journal] }
            + c.blueprints.flatMap { [$0.name, $0.effect] }, "コンテンツ")
        XCTAssertEqual(c.itemName("no_such_item"), "不明な物", "未知の ID でも英語を出さない")
    }

    func testAllGameTextsAreClean() {
        let g = Fixture.game
        let t = Fixture.text
        var samples: [String] = []

        // いろいろな状態を作る
        var s = g.newGame(seed: 8).with(ID.plantFiber, 9).with(ID.ironIngot, 4).with(ID.coal, 3)
        let states: [GameState] = [
            s, s.with(ID.food, 0), s.with(ID.food, 3), s.with(ID.water, 0), s.with(ID.water, 4),
            s.withBuildings(g.content.blueprints.map(\.id)),
        ]
        for st in states {
            samples += [t.dayLabel(st.day), t.actionsLabel(st), t.victoryBody(st), t.savePointLabel(st)]
            samples += t.warnings(st).map(\.text)
            samples += GatherKind.allCases.flatMap { [t.gatherName($0), t.gatherPreview($0, in: st)] }
            samples += g.content.items.map { t.stockLabel($0.id, in: st) }
            samples += g.content.recipes.compactMap { t.craftBlocker($0, in: st) }
        }
        samples += g.content.recipes.map(t.recipeFormula)
        samples += g.content.blueprints.map(t.costLabel)
        samples += (1...4).map { t.craftButton(times: $0) }
        samples.append(t.gainFlash([ItemAmount(ID.food, 4)]))

        // 拒否の理由(すべての種類 × 時間帯)
        let phases: [Phase] = [.day, .dusk, .night, .dawn]
        var errors: [ActionError] = phases.map { .notAllowed($0) }
        errors += [.noActionPoints, .insufficient([ID.coal, ID.charcoal], have: 0, need: 1), .needsBuilding([ID.campfire, ID.basicFurnace]),
                   .alreadyBuilt(ID.well), .scavengeExhausted, .noFireAtNight, .gameNotActive, .invalidQuantity, .unknown]
        samples += errors.map(t.message)

        // 1 日を通して日誌を貯め、ありとあらゆる日誌の種類を出す
        s = g.must(.build(ID.campfire), s)
        for a in [Action.gather(.food), .gather(.water), .gather(.wood), .gather(.stone), .gather(.ore), .gather(.scavenge),
                  .craft(ID.charcoalBurn, times: 2), .craft(ID.smeltIron, times: 1)] {
            s = g.must(a, s)
        }
        s = g.must(.rest, s)
        s = g.mustSleep(s)
        s = g.markManualSave(s)
        var events = s.log.map(\.event)
        let report = DawnReport(endedDay: 1, tally: {
            var d = DayTally()
            d.consumed = [ID.food: 5, ID.water: 5, ID.ration: 1]
            d.produced = [ID.water: 2, ID.food: 2, ID.charcoal: 2]
            d.foodShort = true
            d.waterShort = true
            return d
        }(), daysWithoutFood: 1, daysWithoutWater: 1)
        events += [.dawn(report), .victory, .gameOver(.starvation), .gameOver(.dehydration),
                   .rewound(carried: [ItemAmount(ID.wood, 10)]), .rewound(carried: []),
                   .continuedWithLoss(lostCompanions: ["ルーメン"], lostItems: [ItemAmount(ID.wood, 3)]),
                   .continuedWithLoss(lostCompanions: [], lostItems: []),
                   .loadedSavePoint(day: 3), .manualSave, .newGame, .restedDay,
                   .crafted(ID.ironPlatePound, times: 1, output: ItemAmount(ID.ironPlate, 1)),
                   .crafted(ID.rationRecipe, times: 1, output: ItemAmount(ID.ration, 2)),
                   .gathered(.wood, gains: [ItemAmount(ID.wood, 5), ItemAmount(ID.plantFiber, 1)], scavengeLeft: nil),
                   .gathered(.stone, gains: [ItemAmount(ID.stone, 3), ItemAmount(ID.clay, 1)], scavengeLeft: nil)]
        samples += events.map { t.journal(LogEntry(day: 1, event: $0)) }
        samples += t.dawnLines(report)
        samples += t.dawnSummary(report) + t.dawnSummary(DawnReport(endedDay: 1, tally: DayTally(), daysWithoutFood: 0, daysWithoutWater: 0))
        samples += [t.duskHint(canWorkAtNight: true), t.duskHint(canWorkAtNight: false)]
        samples += [t.failureReasonText(.starvation), t.failureReasonText(.dehydration)]

        // ゲームオーバーの選択肢
        let failed = g.idleDays(3, g.newGame(seed: 1).with(ID.water, 0).with(ID.wood, 40))
        for sp in [failed, g.newGame(seed: 2)] as [GameState?] + [nil] {
            for choice in g.recoveryChoices(for: failed, savePoint: sp) {
                samples.append(t.recoveryTitle(choice.recovery.option))
                samples.append(t.recoveryDetail(choice.recovery, failed: failed, savePoint: sp))
            }
        }
        var alone = failed
        alone.companions = []
        samples += g.recoveryChoices(for: alone, savePoint: nil).map { t.recoveryDetail($0.recovery, failed: alone, savePoint: nil) }

        assertClean(samples, "GameText")
    }

    func testCheckerCatchesForbiddenTerms() {
        // 検査そのものが働くこと(わざと禁止語を入れた文が引っかかる)
        let bad = ["脱出ポッドを漁った", "iron_ingot", "Ferrum の空", "カプセルの残骸"]
        for s in bad {
            XCTAssertTrue(Self.forbidden.contains { s.contains($0) } || s.range(of: "[a-z]{3,}", options: .regularExpression) != nil, s)
        }
    }
}
