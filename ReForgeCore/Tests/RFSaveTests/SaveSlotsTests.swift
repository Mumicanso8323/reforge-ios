import Foundation
import RFFailure
import RFKernel
import RFRules
import RFSave
import RFSim
import RFTestSupport
import RFWorld
import XCTest

/// 自動(夜明け)と手動の枠の分け方(D §7。S-04)。4 択のそれぞれの後・寝る → 夜明け・一覧の分け方。
final class SaveSlotsTests: XCTestCase {
    struct Setup {
        let rig: TestRig
        let storage: MemorySaveStorage
        let book: SaveBook
        let recovery: Recovery
    }

    func setup() throws -> Setup {
        let rig = try TestRig.publicOnly()
        let storage = MemorySaveStorage()
        let book = SaveBook(storage: storage, content: Fixture.stamp)
        let factory = rig.factory
        return Setup(rig: rig, storage: storage, book: book,
                     recovery: Recovery(content: rig.content, book: book, newWorld: { factory.newWorld(seed: $0) }))
    }

    /// 昼を過ごして寝る。夜明けに着いたら自動セーブを当てる(画面が dawn の出来事を見て呼ぶ)。
    @discardableResult
    func sleepToDawn(_ s: Setup, _ w: inout WorldState) throws -> Bool {
        _ = s.rig.playDay(&w)
        let r = s.rig.simulation.apply(.time(.sleep), to: &w)
        XCTAssertTrue(r.events.contains(.dawn(day: w.clock.day)))
        return try s.book.autosaveDawn(w)
    }

    func fail(_ w: inout WorldState, _ rig: TestRig) {
        w.narrative.counters["counter.test.doom"] = 1
        _ = rig.simulation.runSteps(1, &w)
    }

    func autoDays(_ s: Setup) throws -> [Int] {
        try s.book.savePointGroups(activeOnly: false).auto.compactMap { if case .dawn(let d) = $0.slot { d } else { nil } }
    }

    func manualIndexes(_ s: Setup) throws -> [Int] {
        try s.book.savePointGroups(activeOnly: false).manual.compactMap { if case .manual(let i) = $0.slot { i } else { nil } }
    }

    /// 1〜3 日目の夜明け(自動)・手動 0・中断のある、3 日目で失敗した世界。
    func failedAtDay3(_ s: Setup, seed: UInt64 = 8) throws -> WorldState {
        var w = s.rig.factory.newWorld(seed: seed)
        try s.book.startNew(w)
        try s.book.saveManual(w, index: 0)
        try sleepToDawn(s, &w)
        try sleepToDawn(s, &w)
        XCTAssertEqual(w.clock.day, 3)
        try s.book.writeResume(w)
        fail(&w, s.rig)
        XCTAssertFalse(w.run.isActive)
        return w
    }

    /// 最初から: 自動と中断は新しい 1 日目だけ。手動は残る。
    func testRestartKeepsOnlyNewDayOneAndManual() throws {
        let s = try setup()
        let failed = try failedAtDay3(s)
        XCTAssertEqual(try autoDays(s), [3, 2, 1])
        let fresh = try s.recovery.perform(.restart, failed: failed, newSeed: 77).world
        XCTAssertEqual(try autoDays(s), [1])
        XCTAssertEqual(try manualIndexes(s), [0])
        XCTAssertEqual(try s.book.load(.dawn(day: 1))?.summary.seed, 77)
        XCTAssertEqual(try s.book.readResume()?.world, fresh)
        XCTAssertEqual(try s.book.load(.manual(index: 0))?.summary.seed, 8, "手動は前の走行のまま残る")
    }

    /// 巻き戻し: 戻った夜明けより先の自動が消える。戻り先は上書きされ、手動は残る。
    func testRewindDropsLaterAutosAndKeepsManual() throws {
        let s = try setup()
        let failed = try failedAtDay3(s)
        let r = try s.recovery.perform(.rewindWithMemory, failed: failed, target: .dawn(day: 2), newSeed: 0).world
        XCTAssertEqual(try autoDays(s), [2, 1])
        XCTAssertEqual(try manualIndexes(s), [0])
        XCTAssertEqual(try s.book.load(.dawn(day: 2))?.world, r, "戻り先は巻き戻した世界で上書きされる")
        XCTAssertEqual(try s.book.readResume()?.world, r)
    }

    /// 失って続ける: 自動はそのまま・中断が書き直される。次の夜明けで自動の枠が 1 つ足される。
    func testContinueKeepsAutosAndNextDawnAddsOne() throws {
        let s = try setup()
        var w = s.rig.factory.newWorld(seed: 8)
        try s.book.startNew(w)
        try sleepToDawn(s, &w)
        XCTAssertEqual(try autoDays(s), [2, 1])
        fail(&w, s.rig)
        let before = try s.book.points(of: [.dawn(day: 1), .dawn(day: 2)])
        var r = try s.recovery.perform(.continueWithLoss, failed: w, newSeed: 0).world
        XCTAssertEqual(try autoDays(s), [2, 1])
        XCTAssertEqual(try s.book.points(of: [.dawn(day: 1), .dawn(day: 2)]), before, "自動の枠の中身は変わらない")
        XCTAssertEqual(try s.book.readResume()?.world, r, "中断が書き直される")
        XCTAssertTrue(r.run.isActive)
        try sleepToDawn(s, &r)
        XCTAssertEqual(try autoDays(s), [3, 2, 1])
    }

    /// セーブから読む: 別の走行の自動が消え、手動は残る。先の日の自動も消える。
    func testLoadDropsOtherRunAutosAndKeepsManual() throws {
        let s = try setup()
        let failed = try failedAtDay3(s)
        let other = s.rig.factory.newWorld(seed: 99)
        var otherAt5 = other
        otherAt5.clock.day = 5
        try s.storage.write(SaveCodec.encode(SaveEnvelope(slot: .dawn(day: 5), world: otherAt5, content: Fixture.stamp)),
                            slot: .dawn(day: 5))
        XCTAssertEqual(try autoDays(s), [5, 3, 2, 1])
        let loaded = try s.recovery.perform(.loadSavePoint, failed: failed, target: .manual(index: 0), newSeed: 0).world
        XCTAssertEqual(loaded.clock.day, 1)
        XCTAssertEqual(try autoDays(s), [1])
        XCTAssertEqual(try manualIndexes(s), [0])
        XCTAssertEqual(try s.book.readResume()?.world, loaded)
    }

    /// 寝る → 夜明けで自動の枠が 1 つ増える。4 日分たまると古いものから消える(3 つ残る)。
    func testSleepAddsAutosAndOldestIsDropped() throws {
        let s = try setup()
        var w = s.rig.factory.newWorld(seed: 3)
        try s.book.startNew(w)
        XCTAssertEqual(try autoDays(s), [1])
        _ = s.rig.playDay(&w)
        XCTAssertEqual(try autoDays(s), [1], "寝る前に自動の枠は書かない")
        for expected in [[2, 1], [3, 2, 1], [4, 3, 2], [5, 4, 3]] {
            if w.clock.phase == .day { _ = s.rig.playDay(&w) }
            XCTAssertTrue(s.rig.simulation.apply(.time(.sleep), to: &w).events.contains(.dawn(day: w.clock.day)))
            XCTAssertTrue(try s.book.autosaveDawn(w))
            XCTAssertEqual(try autoDays(s), expected)
        }
    }

    /// activeOnly は終わった走行の枠を含めない。読めない枠は problem つきで残る。
    func testGroupsActiveOnlyAndUnreadable() throws {
        let s = try setup()
        let w = s.rig.factory.newWorld(seed: 1)
        var failed = w
        fail(&failed, s.rig)
        try s.book.autosaveDawn(w)
        try s.book.saveManual(w, index: 0)
        try s.book.saveManual(failed, index: 2)
        try s.storage.write(Data("broken".utf8), slot: .manual(index: 1))
        try s.storage.write(Data("broken".utf8), slot: .dawn(day: 9))
        try s.book.writeResume(w)

        let all = try s.book.savePointGroups(activeOnly: false)
        XCTAssertEqual(all.manual.map(\.slot), [.manual(index: 0), .manual(index: 1), .manual(index: 2)])
        let active = try s.book.savePointGroups(activeOnly: true)
        XCTAssertEqual(active.manual.map(\.slot), [.manual(index: 0), .manual(index: 1)], "終わった走行の枠は含めない")
        XCTAssertEqual(active.auto.map(\.slot), [.dawn(day: 9), .dawn(day: 1)])
        XCTAssertNotNil(active.manual[1].problem)
        XCTAssertNil(active.manual[1].summary)
        XCTAssertNotNil(active.auto[0].problem)
        XCTAssertFalse(active.auto.contains { $0.slot == .resume } || active.manual.contains { $0.slot == .resume })
        XCTAssertEqual(active.auto + active.manual, try s.book.savePoints().filter { $0.summary?.active != false })
    }
}

extension SaveBook {
    /// 枠の中身の比較用(テストだけ)。
    func points(of slots: [SaveSlot]) throws -> [Data?] { try slots.map { try storage.read(slot: $0) } }
}
