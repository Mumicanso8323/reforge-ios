import Foundation
import RFKernel
import RFWorld

/// 通しの台本(A-07): ボットが送った命令を、送った時のシミュレーションの歩みの番号つきで並べたもの。
/// アプリの DEBUG の組みが、同じ seed の新しい世界へ、歩みが届くたびに命令を流し込む。内容の名前は持たない。
public struct ReplayScript: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// 命令を送った時の歩みの通し番号(世界の clock.now の秒 / SimStep.gameSeconds)。
        public var step: Int
        public var command: Command
        /// 前の命令を送ってから、実時間で最低これだけ(秒)あけて送る。時計が保留の間(暗い場面の長押し)は歩みが進まないので、押している時間をこれで持つ。無ければ歩みだけで決める。
        public var after: Double?

        public init(step: Int, command: Command, after: Double? = nil) {
            self.step = step
            self.command = command
            self.after = after
        }
    }

    /// 世界の保存データ(SaveCodec のバイト列)。流し込みが、ボットの世界と合わせ直すのに使う。
    /// 命令の列だけでは、ボットの世界とアプリの世界の小さな差(時刻・歩く道の細かい違い)が積もって、10 分の途中から合わなくなる。
    public struct Checkpoint: Codable, Equatable, Sendable {
        /// この番号の命令を送る前に、この世界へ合わせる(0 始まり)。
        public var index: Int
        public var save: Data

        public init(index: Int, save: Data) {
            self.index = index
            self.save = save
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public var seed: Int
    /// 最後の命令までの実時間の見込み(秒)。
    public var seconds: Double
    public var commands: [Entry]
    /// 世界の合わせ直しの点(無ければ命令だけ)。
    public var checkpoints: [Checkpoint]?

    public init(version: Int = ReplayScript.currentVersion, seed: Int, seconds: Double, commands: [Entry],
                checkpoints: [Checkpoint]? = nil) {
        self.version = version
        self.seed = seed
        self.seconds = seconds
        self.commands = commands
        self.checkpoints = checkpoints
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> ReplayScript {
        let s = try JSONDecoder().decode(ReplayScript.self, from: data)
        guard s.version == currentVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unsupported version \(s.version)"))
        }
        return s
    }

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> ReplayScript {
        try decode(Data(contentsOf: url))
    }
}
