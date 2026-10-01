/// アプリを閉じていた間の扱い(DEC-03、REQ-09)。
public protocol OfflinePolicy: Sendable {
    /// 復帰時に呼ばれる。elapsedWallClock は閉じていた実時間(秒)。
    func onResume(_ s: GameState, elapsedWallClock: Double) -> GameState
}

/// 既定: 閉じている間、拠点は進まない(消費も餓死もない)。
public struct NoOfflineProgress: OfflinePolicy {
    public init() {}

    public func onResume(_ s: GameState, elapsedWallClock: Double) -> GameState { s }
}
