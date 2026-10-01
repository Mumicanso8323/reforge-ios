/// 「休む」「寝る」の取り消し用の控え。押し間違いを確認ダイアログではなく取り消しで守る。
///
/// 実行直前の状態(before)と直後の状態(after)を持つ。いまの状態が after と完全に一致する間だけ
/// 取り消せる。間に別の行動や時間の経過が入ったら、もう取り消せない。
/// 結末(ゲームオーバー・勝利)に入った休みは取り消さない(結末の画面そのものが選択なので)。
public struct RestUndo: Equatable, Sendable {
    /// 休む前の状態。取り消すとこれに戻る。
    public let before: GameState
    /// 休んだ直後の状態。
    public let after: GameState

    public init(before: GameState, after: GameState) {
        self.before = before
        self.after = after
    }

    /// いまの状態 current から取り消せるか。
    public func canUndo(_ current: GameState) -> Bool {
        after.isActive && current == after
    }

    /// 取り消した状態(= 休む前と完全に同じ)。取り消せなければ nil。
    public func undo(_ current: GameState) -> GameState? {
        canUndo(current) ? before : nil
    }

    /// まだ取り消せる休みの直後にもう一度休んだ(「休む」の連打で「寝る」まで押したなど)ときは、
    /// 2 つをまとめて 1 つの控えにする。取り消すと最初の休みの前まで戻る。
    public func following(_ previous: RestUndo?) -> RestUndo {
        guard let previous, previous.canUndo(before) else { return self }
        return RestUndo(before: previous.before, after: after)
    }
}

extension Game {
    /// 休む(昼)・寝る(日没・夜作業中)を行い、取り消し用の控えを返す。新しい状態は `after`。
    public func restWithUndo(_ s: GameState) -> Result<RestUndo, ActionError> {
        perform(.rest, on: s).map { RestUndo(before: s, after: $0) }
    }
}
