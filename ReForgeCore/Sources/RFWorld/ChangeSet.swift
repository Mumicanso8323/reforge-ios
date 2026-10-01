import RFKernel

/// 1 回の進行で何が変わったか(画面の射影をどこだけ作り直すか)。システムが StepContext 経由で印を付ける。
/// 世界状態には入れない(保存しない)。
public struct ChangeSet: Equatable, Sendable {
    public struct Areas: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let clock = Areas(rawValue: 1 << 0)
        public static let terrain = Areas(rawValue: 1 << 1)
        public static let fog = Areas(rawValue: 1 << 2)
        public static let people = Areas(rawValue: 1 << 3)
        public static let placements = Areas(rawValue: 1 << 4)
        public static let inventory = Areas(rawValue: 1 << 5)
        public static let notebook = Areas(rawValue: 1 << 6)
        /// 知っている事実が増えた → 名前・説明の見え方が変わったかもしれない(画面の文字を全部引き直す)。
        public static let perception = Areas(rawValue: 1 << 7)
        public static let survival = Areas(rawValue: 1 << 8)
        public static let combat = Areas(rawValue: 1 << 9)
        public static let research = Areas(rawValue: 1 << 10)
        public static let narrative = Areas(rawValue: 1 << 11)
        public static let run = Areas(rawValue: 1 << 12)
        public static let all = Areas(rawValue: ~0)
    }

    public var areas: Areas = []
    /// 地形・霧が変わったマス(画面はこれを含む区画だけ描き直す)。
    public var dirtyTiles: Set<WorldPoint> = []

    public init() {}

    public mutating func mark(_ a: Areas) { areas.formUnion(a) }
    public mutating func markTile(_ p: WorldPoint, _ a: Areas = .terrain) {
        areas.formUnion(a)
        dirtyTiles.insert(p)
    }

    public mutating func merge(_ o: ChangeSet) {
        areas.formUnion(o.areas)
        dirtyTiles.formUnion(o.dirtyTiles)
    }

    public var isEmpty: Bool { areas.isEmpty && dirtyTiles.isEmpty }
}
