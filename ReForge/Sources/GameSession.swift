import Observation
import ReForgeCore

/// ゲーム画面の仮の状態。中身(資源の種類・進行ルール)は要件定義が固まってから差し替える。
/// 時間の進み方は GameClock に任せるので、ターン制/リアルタイムはここを差し替えるだけで切り替わる。
@Observable
final class GameSession {
    private(set) var resource: ResourceCounter
    private var clock: any GameClock

    init(resource: ResourceCounter = ResourceCounter(capacity: 10),
         clock: any GameClock = TurnBasedClock()) {
        self.resource = resource
        self.clock = clock
    }

    var elapsedTicks: Int { clock.elapsedTicks }

    /// 資源を 1 増やす(上限で止まる)。
    func gather() {
        resource.add(1)
    }

    /// 行動を終えて時間を進める。進んだティックごとに資源を 1 消費する(仮ルール)。
    func endTurn() {
        let ticks = clock.playerDidAct()
        resource.consume(ticks)
    }
}
