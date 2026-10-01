import RFContent
import RFKernel
import RFRules
import RFSave
import RFWorld

/// ゲームオーバーの 4 択(オーナー決定。推奨の順位を付けない。画面は同じ重さで並べる)。
public enum RecoveryOption: String, Codable, CaseIterable, Sendable {
    /// 最初から。
    case restart
    /// 記憶を持って巻き戻す(夜明けへ。知った事実・ノート・地図の既知・関係・残る記憶は持ち越す)。
    case rewindWithMemory
    /// 失って、その場から続ける。
    case continueWithLoss
    /// セーブ地点からロードする(夜明けの自動セーブか手動セーブ)。
    case loadSavePoint
}

/// 4 択の 1 つ。選べないときは理由(文字列表のキー)を持つ(画面は灰色にして理由を 1 行)。
public struct RecoveryChoice: Equatable, Sendable {
    public var option: RecoveryOption
    public var available: Bool
    public var reason: TextID?
    /// 選べる行き先(巻き戻し: 夜明けの新しい順。ロード: セーブ地点の一覧)。最初からと失って続けるは空。
    public var targets: [SaveSlot]
}

public enum RecoveryError: Error, Equatable {
    case notFailed
    case unavailable(RecoveryOption, reason: TextID)
    case noSuchSave(SaveSlot)
}

/// 4 択の結果。
public struct RecoveryResult: Sendable {
    public var world: WorldState
    /// 効果の仕組みがまだ無いなど(テストは 0 件を確かめる)。
    public var warnings: [String]
}

/// 4 択の実行(GameHost が呼び、返った世界を host.replace(world:) する)。保存の書き換えもここでする。
///
/// - 最初から: 新しい seed の世界(newWorld)。前の走行の夜明けと続きを消す(手動セーブは残す)。
/// - 記憶を持って巻き戻す: 選んだ夜明け(既定は最新)へ MemoryCarry。その夜明けの保存を巻き戻した世界で上書きし、
///   その先の夜明けを消す。
/// - 失って続ける: LossCarry。選べるのは、失った後に失敗の規則が 1 つも成り立たないときだけ。
/// - セーブ地点からロード: 持ち越しなし。その先の夜明けを消す。
public struct Recovery: Sendable {
    public let content: ContentDB
    public let book: SaveBook
    /// 新しい世界を作る(RFSim の WorldFactory.newWorld。RFFailure は RFSim を import できないので閉包で受ける)。
    public let newWorld: @Sendable (UInt64) -> WorldState

    public init(content: ContentDB, book: SaveBook, newWorld: @escaping @Sendable (UInt64) -> WorldState) {
        self.content = content
        self.book = book
        self.newWorld = newWorld
    }

    /// 4 つを決まった順(RecoveryOption.allCases)で。
    public func choices(for failed: WorldState) throws -> [RecoveryChoice] {
        guard case .failed = failed.run.outcome else { throw RecoveryError.notFailed }
        let dawns = try book.rewindTargets(for: failed).map(\.slot)
        let points = try book.savePoints().filter { $0.summary?.active == true }.map(\.slot)
        let canContinue = LossCarry.continueWithLoss(failed: failed, content: content) != nil
        return [
            RecoveryChoice(option: .restart, available: true, reason: nil, targets: []),
            RecoveryChoice(option: .rewindWithMemory, available: !dawns.isEmpty,
                           reason: dawns.isEmpty ? "reason.recovery.no_dawn" : nil, targets: dawns),
            RecoveryChoice(option: .continueWithLoss, available: canContinue,
                           reason: canContinue ? nil : "reason.recovery.still_failing", targets: []),
            RecoveryChoice(option: .loadSavePoint, available: !points.isEmpty,
                           reason: points.isEmpty ? "reason.recovery.no_save" : nil, targets: points),
        ]
    }

    /// 選んだものを実行する。target は巻き戻しの夜明け・ロードするセーブ地点(nil なら巻き戻しは最新の夜明け)。
    public func perform(_ option: RecoveryOption, failed: WorldState, target: SaveSlot? = nil,
                        newSeed: UInt64) throws -> RecoveryResult
    {
        guard case .failed = failed.run.outcome else { throw RecoveryError.notFailed }
        switch option {
        case .restart:
            let w = newWorld(newSeed)
            try book.startNew(w)
            return RecoveryResult(world: w, warnings: [])

        case .rewindWithMemory:
            let dawns = try book.rewindTargets(for: failed)
            let dawn: SaveEnvelope
            if let target {
                guard let d = dawns.first(where: { $0.slot == target }) else { throw RecoveryError.noSuchSave(target) }
                dawn = d
            } else {
                guard let d = dawns.first else {
                    throw RecoveryError.unavailable(.rewindWithMemory, reason: "reason.recovery.no_dawn")
                }
                dawn = d
            }
            let w = MemoryCarry.rewind(failed: failed, dawn: dawn.world, content: content)
            try book.adoptTimeline(w)
            try book.autosaveDawn(w)
            try book.writeResume(w)
            return RecoveryResult(world: w, warnings: [])

        case .continueWithLoss:
            guard let r = LossCarry.continueWithLoss(failed: failed, content: content) else {
                throw RecoveryError.unavailable(.continueWithLoss, reason: "reason.recovery.still_failing")
            }
            try book.writeResume(r.world)
            return RecoveryResult(world: r.world, warnings: r.warnings)

        case .loadSavePoint:
            guard let target, target != .resume, target != .screen else {
                throw RecoveryError.unavailable(.loadSavePoint, reason: "reason.recovery.no_save")
            }
            guard let e = try book.load(target), e.summary.active else { throw RecoveryError.noSuchSave(target) }
            try book.adoptTimeline(e.world)
            try book.writeResume(e.world)
            return RecoveryResult(world: e.world, warnings: [])
        }
    }
}
