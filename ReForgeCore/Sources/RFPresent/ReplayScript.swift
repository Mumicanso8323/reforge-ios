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

        public init(step: Int, command: Command) {
            self.step = step
            self.command = command
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public var seed: Int
    /// 最後の命令までの実時間の見込み(秒)。
    public var seconds: Double
    public var commands: [Entry]

    public init(version: Int = ReplayScript.currentVersion, seed: Int, seconds: Double, commands: [Entry]) {
        self.version = version
        self.seed = seed
        self.seconds = seconds
        self.commands = commands
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
