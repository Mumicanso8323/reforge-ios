import RFContent
import RFKernel
import RFPresent
import RFRules
import RFTestSupport
import RFWorld
import XCTest

/// U15: 記録・句・名簿を、設計画面と同じ工程表(ProcessSheet)で開く(REQ-S8)。
final class RecordSheetTests: XCTestCase {
    private let ledger: SheetID = "sheet.test.ledger"

    func testRecordsOpenInTheSameSheetShapeAsTrialsWithCountableGap() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        XCTAssertNil(b.sheet(.record(ledger), in: ctx.world))
        ctx.learn("fact.test.device_fixed")
        let w = ctx.world
        let s = try XCTUnwrap(b.sheet(.record(ledger), in: w))
        XCTAssertEqual(s.tally, ProcessSheet.Tally(filled: 5, slots: 6))
        XCTAssertEqual(s.rows.map(\.slot), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(s.rows.filter(\.empty).map(\.slot), [4], "欠けは並びの中にあって数えられる")
        XCTAssertEqual(s.rows[1].person, "person.test_a")
        // 記録の 1 件は試作と同じ形(行 = 工程の見出しと注、結果 = 名前)。工程の見出しはプレイヤーの炉と同じ名前
        let e = try XCTUnwrap(b.sheet(.recordEntry(ledger, slot: 2), in: w))
        XCTAssertEqual(e.rows.map(\.title), ["元", "炉", "書き込み"])
        XCTAssertEqual(e.rows[1], ProcessSheet.Row(title: "炉", note: "試験の行"))
        XCTAssertNotNil(e.result)
        // 空いた席を開くと、行も結果も無い
        let gap = try XCTUnwrap(b.sheet(.recordEntry(ledger, slot: 4), in: w))
        XCTAssertEqual(gap.rows, [])
        XCTAssertNil(gap.result)
        XCTAssertNil(b.sheet(.recordEntry(ledger, slot: 7), in: w))
    }

    func testVerseRowsShowFiguresAndPlacedAnswer() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var w = rig.factory.newWorld(seed: 1)
        var ctx = StepContext(world: w, content: rig.content)
        let made = ctx.record(.crafted, .item("wood"), actor: .noah, detail: ["purity": .int(6400)])
        w = ctx.world
        XCTAssertEqual(b.answerCandidates("sheet.test.verse", row: "line.make", in: w).map(\.record), [made])
        XCTAssertNil(rig.simulation.apply(.narrative(.placeAnswer(sheet: "sheet.test.verse", row: "line.make", record: made)),
                                          to: &w).rejection)
        let s = try XCTUnwrap(b.sheet(.record("sheet.test.verse"), in: w))
        XCTAssertEqual(s.rows.map(\.answerRow), ["line.make", "line.keep"])
        XCTAssertEqual(s.rows[0].figure, 1)
        XCTAssertEqual(s.rows[1].figure, 6400)
        XCTAssertNotNil(s.rows[0].answer)
        XCTAssertNil(s.rows[1].answer)
    }

    func testManifestListsPeopleWithTheirOwnWord() throws {
        let rig = try TestRig.publicOnly()
        let b = FrameBuilder(content: rig.content)
        var ctx = StepContext(world: rig.factory.newWorld(seed: 1), content: rig.content)
        ctx.learn("fact.test.vessel_ready")
        var w = ctx.world
        _ = rig.simulation.apply(.narrative(.openSheet(sheet: "sheet.test.manifest", slot: nil)), to: &w)
        let s = try XCTUnwrap(b.sheet(.record("sheet.test.manifest"), in: w))
        let byPerson = Dictionary(uniqueKeysWithValues: s.rows.compactMap { r in r.person.map { ($0, r) } })
        XCTAssertEqual(byPerson["person.test_a"]?.declared, false)
        XCTAssertEqual(byPerson["person.test_b"]?.aboard, true)
        XCTAssertNotNil(byPerson[.noah])
        XCTAssertNil(byPerson[.noah]?.aboard)
    }
}
