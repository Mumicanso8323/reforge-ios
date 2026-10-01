import XCTest
@testable import ReForgeCore
import ReForgeContent

enum Fixture {
    static let content: ContentDB = {
        do { return try ContentLoader.bundled() } catch { fatalError("コンテンツが読めない: \(error)") }
    }()

    static let game = Game(content: content)
    static let turnGame = Game(content: content, timeModel: DayTurnTimeModel())
    static var text: GameText { GameText(content: content, balance: .mvp) }
}

extension Game {
    /// 成功を前提に行動する(失敗ならテストを落とす)。
    func must(_ a: Action, _ s: GameState, file: StaticString = #filePath, line: UInt = #line) -> GameState {
        switch perform(a, on: s) {
        case .success(let n): return n
        case .failure(let e):
            XCTFail("\(a) が拒否された: \(e)", file: file, line: line)
            return s
        }
    }

    func mustSleep(_ s: GameState, file: StaticString = #filePath, line: UInt = #line) -> GameState {
        switch sleep(s) {
        case .success(let n): return n
        case .failure(let e):
            XCTFail("寝られない: \(e)", file: file, line: line)
            return s
        }
    }

    /// 何もせずに n 日過ごす(昼を使い切って寝る)。
    func idleDays(_ n: Int, _ s: GameState) -> GameState {
        var s = s
        for _ in 0..<n where s.isActive {
            s = tick(s, deltaSeconds: timeModel.daySeconds)
            s = mustSleep(s)
        }
        return s
    }
}

extension GameState {
    /// テスト用に在庫を書き換える。
    func with(_ item: ItemID, _ n: Int) -> GameState {
        var s = self
        s.inventory[item] = n
        return s
    }

    func withBuildings(_ ids: [BuildingID]) -> GameState {
        var s = self
        for id in ids where !s.has(id) { s.buildings.append(Building(id: id, builtOnDay: s.day)) }
        return s
    }
}
